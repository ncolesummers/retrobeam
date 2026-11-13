defmodule RetrobeamWeb.RetroLive.CardsTest do
  use RetrobeamWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Retrobeam.AccountsFixtures
  import Retrobeam.RetrosFixtures

  alias Retrobeam.Accounts.Scope
  alias Retrobeam.Repo
  alias Retrobeam.Retros
  alias Retrobeam.Retros.Card

  setup :register_and_log_in_user

  setup %{scope: scope} = context do
    member = user_fixture(%{display_name: "Robin"})
    member_scope = Scope.for_user(member)
    retro = retro_fixture(scope)
    participation_fixture(retro, member)

    if options = context[:options], do: {:ok, _} = Retros.update_options(scope, retro.id, options)
    {:ok, _} = Retros.advance_phase(scope, retro.id)

    retro = retro |> Repo.reload!() |> Repo.preload(:columns)
    [column | _] = retro.columns

    %{
      retro: retro,
      column: column,
      member: member,
      member_scope: member_scope,
      member_conn: build_conn() |> log_in_user(member)
    }
  end

  defp add_card(view, column, body) do
    view
    |> form("#add-card-#{column.id}", card: %{body: body})
    |> render_submit()
  end

  test "adding a card shows it to the author and to everyone else", %{
    conn: conn,
    member_conn: member_conn,
    retro: retro,
    column: column,
    member: member
  } do
    {:ok, facilitator_view, _} = live(conn, ~p"/retros/#{retro}")
    {:ok, member_view, _} = live(member_conn, ~p"/retros/#{retro}")

    add_card(member_view, column, "Standups ran long")

    card = Repo.get_by!(Card, body: "Standups ran long")
    assert has_element?(member_view, "#cards-#{card.id}", "Standups ran long")
    assert has_element?(facilitator_view, "#cards-#{card.id}", "Standups ran long")
    assert has_element?(facilitator_view, "#cards-#{card.id}", member.display_name)
    assert has_element?(member_view, "#cards-#{card.id} button[aria-label='Edit card']")
    refute has_element?(facilitator_view, "#cards-#{card.id} button[aria-label='Edit card']")
  end

  test "shows validation errors", %{conn: conn, retro: retro, column: column} do
    {:ok, view, _} = live(conn, ~p"/retros/#{retro}")

    assert add_card(view, column, "   ") =~ "Card can&#39;t be blank"
    assert Repo.aggregate(Card, :count) == 0
  end

  test "the author edits inline and everyone sees the change", %{
    conn: conn,
    member_conn: member_conn,
    member_scope: member_scope,
    retro: retro,
    column: column
  } do
    {:ok, card} =
      Retros.add_card(member_scope, retro.id, %{"column_id" => column.id, "body" => "Old"})

    {:ok, facilitator_view, _} = live(conn, ~p"/retros/#{retro}")
    {:ok, view, _} = live(member_conn, ~p"/retros/#{retro}")

    view |> element("#cards-#{card.id} button[aria-label='Edit card']") |> render_click()
    assert has_element?(view, "#edit-card-#{card.id}-body", "Old")

    assert view
           |> form("#edit-card-#{card.id}", card: %{body: ""})
           |> render_submit() =~ "Card can&#39;t be blank"

    view |> form("#edit-card-#{card.id}", card: %{body: "New text"}) |> render_submit()

    refute has_element?(view, "#edit-card-#{card.id}")
    assert has_element?(view, "#cards-#{card.id}", "New text")
    assert has_element?(facilitator_view, "#cards-#{card.id}", "New text")
  end

  test "Escape cancels an edit", %{
    member_conn: member_conn,
    member_scope: member_scope,
    retro: retro,
    column: column
  } do
    {:ok, card} =
      Retros.add_card(member_scope, retro.id, %{"column_id" => column.id, "body" => "Keep"})

    {:ok, view, _} = live(member_conn, ~p"/retros/#{retro}")

    view |> element("#cards-#{card.id} button[aria-label='Edit card']") |> render_click()

    view
    |> element("#edit-card-#{card.id}-body")
    |> render_hook("cancel_edit", %{"id" => card.id})

    refute has_element?(view, "#edit-card-#{card.id}")
    assert has_element?(view, "#cards-#{card.id}", "Keep")
  end

  test "the author deletes a card for everyone", %{
    conn: conn,
    member_conn: member_conn,
    member_scope: member_scope,
    retro: retro,
    column: column
  } do
    {:ok, card} =
      Retros.add_card(member_scope, retro.id, %{"column_id" => column.id, "body" => "Bye"})

    {:ok, facilitator_view, _} = live(conn, ~p"/retros/#{retro}")
    {:ok, view, _} = live(member_conn, ~p"/retros/#{retro}")

    view |> element("#cards-#{card.id} button[aria-label='Delete card']") |> render_click()

    refute has_element?(view, "#cards-#{card.id}")
    refute has_element?(facilitator_view, "#cards-#{card.id}")
  end

  test "forged edits of someone else's card are rejected", %{
    conn: conn,
    member_scope: member_scope,
    retro: retro,
    column: column
  } do
    {:ok, card} =
      Retros.add_card(member_scope, retro.id, %{"column_id" => column.id, "body" => "Mine"})

    {:ok, view, _} = live(conn, ~p"/retros/#{retro}")

    view
    |> element("#add-card-#{column.id}-body")
    |> render_hook("delete", %{"id" => card.id})

    assert render(view) =~ "You can only change your own cards."
    assert Repo.get(Card, card.id)
  end

  test "cards are read-only after Collect", %{
    conn: conn,
    scope: scope,
    member_conn: member_conn,
    member_scope: member_scope,
    retro: retro,
    column: column
  } do
    {:ok, card} =
      Retros.add_card(member_scope, retro.id, %{"column_id" => column.id, "body" => "Done"})

    {:ok, view, _} = live(member_conn, ~p"/retros/#{retro}")
    {:ok, facilitator_view, _} = live(conn, ~p"/retros/#{retro}")

    facilitator_view |> element("#next-phase") |> render_click()
    _ = scope

    assert has_element?(view, "#cards-#{card.id}", "Done")
    refute has_element?(view, "#cards-#{card.id} button[aria-label='Edit card']")
    refute has_element?(view, "#add-card-#{column.id}")
  end

  @tag options: %{"anonymous" => "true"}
  test "anonymous retros never render other authors' names", %{
    conn: conn,
    member_conn: member_conn,
    retro: retro,
    column: column,
    member: member
  } do
    {:ok, facilitator_view, _} = live(conn, ~p"/retros/#{retro}")
    {:ok, member_view, _} = live(member_conn, ~p"/retros/#{retro}")

    add_card(member_view, column, "Honest feedback")
    card = Repo.get_by!(Card, body: "Honest feedback")

    assert has_element?(member_view, "#cards-#{card.id}", "Your card")
    refute render(facilitator_view) =~ member.display_name
    assert has_element?(facilitator_view, "#cards-#{card.id}", "Honest feedback")
  end

  @tag options: %{"hide_cards_during_collect" => "true"}
  test "hidden cards show as counts until Group reveals them", %{
    conn: conn,
    member_conn: member_conn,
    member_scope: member_scope,
    retro: retro,
    column: column
  } do
    {:ok, early} =
      Retros.add_card(member_scope, retro.id, %{"column_id" => column.id, "body" => "Secret one"})

    {:ok, facilitator_view, _} = live(conn, ~p"/retros/#{retro}")
    {:ok, member_view, _} = live(member_conn, ~p"/retros/#{retro}")

    assert has_element?(
             facilitator_view,
             "#column-#{column.id}-hidden-count",
             "1 card from others"
           )

    refute render(facilitator_view) =~ "Secret one"
    assert has_element?(member_view, "#cards-#{early.id}", "Secret one")

    add_card(member_view, column, "Secret two")

    assert has_element?(
             facilitator_view,
             "#column-#{column.id}-hidden-count",
             "2 cards from others"
           )

    member_view
    |> element("#cards-#{early.id} button[aria-label='Delete card']")
    |> render_click()

    assert has_element?(
             facilitator_view,
             "#column-#{column.id}-hidden-count",
             "1 card from others"
           )

    add_card(facilitator_view, column, "My own")
    assert render(facilitator_view) =~ "My own"

    facilitator_view |> element("#next-phase") |> render_click()

    refute has_element?(facilitator_view, "#column-#{column.id}-hidden-count")
    assert render(facilitator_view) =~ "Secret two"
    assert render(member_view) =~ "My own"
  end
end
