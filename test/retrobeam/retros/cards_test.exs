defmodule Retrobeam.Retros.CardsTest do
  use Retrobeam.DataCase, async: true

  import Retrobeam.AccountsFixtures
  import Retrobeam.RetrosFixtures

  alias Retrobeam.Retros
  alias Retrobeam.Retros.{Card, Events, RetroServer}

  setup do
    facilitator = user_scope_fixture()
    member = user_scope_fixture()
    retro = retro_fixture(facilitator) |> Repo.preload(:columns)
    participation_fixture(retro, member.user)
    {:ok, _} = Retros.advance_phase(facilitator, retro.id)
    [column | _] = retro.columns

    %{facilitator: facilitator, member: member, retro: retro, column: column}
  end

  defp add(scope, retro, column, body \\ "Ship smaller PRs") do
    Retros.add_card(scope, retro.id, %{"column_id" => to_string(column.id), "body" => body})
  end

  describe "add_card" do
    test "adds a card with its author and broadcasts it", %{
      member: member,
      retro: retro,
      column: column
    } do
      :ok = Events.subscribe(retro.id)

      assert {:ok, %Card{} = card} = add(member, retro, column, "  Pairing helped  ")
      assert card.body == "Pairing helped"
      assert card.author.id == member.user.id
      assert card.retro_column_id == column.id
      assert_receive {:card_created, %Card{id: id}}
      assert id == card.id

      assert Repo.get!(Card, card.id).body == "Pairing helped"
      assert {:ok, %{cards: %{^id => _}}} = RetroServer.get_state(retro.id)
    end

    test "positions cards in the order they were added", %{
      member: member,
      retro: retro,
      column: column
    } do
      {:ok, first} = add(member, retro, column, "one")
      {:ok, second} = add(member, retro, column, "two")
      assert {first.position, second.position} == {0, 1}
    end

    test "validates the body", %{member: member, retro: retro, column: column} do
      assert {:error, changeset} = add(member, retro, column, "   ")
      assert "can't be blank" in errors_on(changeset).body

      assert {:error, changeset} = add(member, retro, column, String.duplicate("a", 501))
      assert "should be at most 500 character(s)" in errors_on(changeset).body

      assert {:ok, _} = add(member, retro, column, String.duplicate("a", 500))
    end

    test "rejects unknown columns and outsiders", %{member: member, retro: retro} do
      assert {:error, :not_found} =
               Retros.add_card(member, retro.id, %{"column_id" => "0", "body" => "x"})

      assert {:error, :not_found} =
               Retros.add_card(member, retro.id, %{"column_id" => "abc", "body" => "x"})

      outsider = user_scope_fixture()
      [column | _] = retro.columns
      assert {:error, :unauthorized} = add(outsider, retro, column)
    end

    test "only during Collect", %{
      facilitator: facilitator,
      member: member,
      retro: retro,
      column: column
    } do
      {:ok, _} = Retros.advance_phase(facilitator, retro.id)
      assert {:error, :wrong_phase} = add(member, retro, column)
    end
  end

  describe "update_card and delete_card" do
    setup %{member: member, retro: retro, column: column} do
      {:ok, card} = add(member, retro, column)
      %{card: card}
    end

    test "the author edits and deletes, with broadcasts", %{
      member: member,
      retro: retro,
      card: card
    } do
      :ok = Events.subscribe(retro.id)

      assert {:ok, updated} =
               Retros.update_card(member, retro.id, to_string(card.id), %{"body" => "Edited"})

      assert updated.body == "Edited"
      assert_receive {:card_updated, %Card{body: "Edited"}}
      assert Repo.get!(Card, card.id).body == "Edited"

      assert {:ok, _} = Retros.delete_card(member, retro.id, card.id)
      assert_receive {:card_deleted, %Card{id: id}}
      assert id == card.id
      refute Repo.get(Card, card.id)
      assert {:ok, %{cards: cards}} = RetroServer.get_state(retro.id)
      refute Map.has_key?(cards, card.id)
    end

    test "validates edits", %{member: member, retro: retro, card: card} do
      assert {:error, changeset} = Retros.update_card(member, retro.id, card.id, %{"body" => ""})
      assert "can't be blank" in errors_on(changeset).body
    end

    test "only the author may change a card", %{
      facilitator: facilitator,
      retro: retro,
      card: card
    } do
      assert {:error, :unauthorized} =
               Retros.update_card(facilitator, retro.id, card.id, %{"body" => "x"})

      assert {:error, :unauthorized} = Retros.delete_card(facilitator, retro.id, card.id)
    end

    test "unknown cards", %{member: member, retro: retro} do
      assert {:error, :not_found} =
               Retros.update_card(member, retro.id, "999999", %{"body" => "x"})

      assert {:error, :not_found} = Retros.delete_card(member, retro.id, nil)
    end

    test "cards are read-only after Collect", %{
      facilitator: facilitator,
      member: member,
      retro: retro,
      card: card
    } do
      {:ok, _} = Retros.advance_phase(facilitator, retro.id)

      assert {:error, :wrong_phase} =
               Retros.update_card(member, retro.id, card.id, %{"body" => "x"})

      assert {:error, :wrong_phase} = Retros.delete_card(member, retro.id, card.id)
    end
  end

  test "cards are reloaded from Postgres after a restart", %{
    member: member,
    retro: retro,
    column: column
  } do
    {:ok, card} = add(member, retro, column)
    pid = RetroServer.whereis(retro.id)
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

    {:ok, state} = RetroServer.get_state(retro.id)
    assert state.cards[card.id].body == card.body
    assert state.cards[card.id].author.id == member.user.id
  end

  test "change_card/2", %{} do
    assert Retros.change_card().errors == [body: {"can't be blank", [validation: :required]}]
    assert Retros.change_card(%Card{}, %{"body" => "ok"}).valid?
  end
end
