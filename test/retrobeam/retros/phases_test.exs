defmodule Retrobeam.Retros.PhasesTest do
  use Retrobeam.DataCase, async: true

  import Retrobeam.AccountsFixtures
  import Retrobeam.RetrosFixtures

  alias Retrobeam.Retros
  alias Retrobeam.Retros.{Events, RetroServer, RetroSession}

  doctest RetroSession

  setup do
    scope = user_scope_fixture()
    participant = user_scope_fixture()
    retro = retro_fixture(scope)
    participation_fixture(retro, participant.user)

    %{scope: scope, participant: participant, retro: retro}
  end

  defp advance_to(scope, retro, phase) do
    Enum.reduce_while(RetroSession.phases(), nil, fn _, _ ->
      {:ok, current} = RetroServer.get_state(retro.id)

      if current.retro.phase == phase do
        {:halt, current.retro}
      else
        {:ok, _} = Retros.advance_phase(scope, retro.id)
        {:cont, nil}
      end
    end)
  end

  describe "advance_phase" do
    test "moves through every phase in order, persisting and broadcasting each", %{
      scope: scope,
      retro: retro
    } do
      :ok = Events.subscribe(retro.id)

      for {from, to} <- Enum.zip(RetroSession.phases(), tl(RetroSession.phases())) do
        assert {:ok, %RetroSession{phase: ^to}} = Retros.advance_phase(scope, retro.id, from)
        assert_receive {:phase_changed, %RetroSession{phase: ^to}}
        assert Repo.get!(RetroSession, retro.id).phase == to
      end

      assert {:error, :final_phase} = Retros.advance_phase(scope, retro.id)
    end

    test "records started_at when leaving Setup", %{scope: scope, retro: retro} do
      assert {:ok, %RetroSession{started_at: %DateTime{}}} = Retros.advance_phase(scope, retro.id)
      assert Repo.get!(RetroSession, retro.id).started_at
    end

    test "rejects a stale expected phase, so phases cannot be skipped", %{
      scope: scope,
      retro: retro
    } do
      assert {:ok, %{phase: :collect}} = Retros.advance_phase(scope, retro.id, :setup)
      assert {:error, :stale_phase} = Retros.advance_phase(scope, retro.id, :setup)
      assert {:error, :stale_phase} = Retros.advance_phase(scope, retro.id, :unknown)
      assert Repo.get!(RetroSession, retro.id).phase == :collect
    end

    test "rejects participants", %{participant: participant, retro: retro} do
      assert {:error, :unauthorized} = Retros.advance_phase(participant, retro.id)
      assert Repo.get!(RetroSession, retro.id).phase == :setup
    end

    test "returns not found for unknown retros", %{scope: scope} do
      assert {:error, :not_found} = Retros.advance_phase(scope, -1)
    end

    test "next_phase/1 and advance_phase_changeset/1" do
      assert RetroSession.next_phase(:vote) == :discuss
      assert RetroSession.next_phase(:nope) == nil

      assert_raise ArgumentError, fn ->
        RetroSession.advance_phase_changeset(%RetroSession{phase: :summary})
      end
    end
  end

  describe "update_options" do
    test "saves options during Setup and broadcasts", %{scope: scope, retro: retro} do
      :ok = Events.subscribe(retro.id)

      attrs = %{
        "vote_limit" => "3",
        "allow_multiple_votes" => "false",
        "anonymous" => "true",
        "hide_cards_during_collect" => "true"
      }

      assert {:ok, updated} = Retros.update_options(scope, retro.id, attrs)
      assert_receive {:retro_updated, %RetroSession{vote_limit: 3}}

      saved = Repo.get!(RetroSession, retro.id)
      assert {saved.vote_limit, saved.allow_multiple_votes, saved.anonymous} == {3, false, true}
      assert saved.hide_cards_during_collect
      assert updated.vote_limit == 3
      assert {:ok, %{retro: %{vote_limit: 3}}} = RetroServer.get_state(retro.id)
    end

    test "validates the vote limit", %{scope: scope, retro: retro} do
      for limit <- ["0", "21", "many"] do
        assert {:error, %Ecto.Changeset{} = changeset} =
                 Retros.update_options(scope, retro.id, %{"vote_limit" => limit})

        refute changeset.valid?
      end

      assert Repo.get!(RetroSession, retro.id).vote_limit == 5
    end

    test "the database also enforces the range", %{retro: retro} do
      changeset =
        retro
        |> Ecto.Changeset.change(vote_limit: 50)
        |> Ecto.Changeset.check_constraint(:vote_limit,
          name: :vote_limit_range,
          message: "must be between 1 and 20"
        )

      assert {:error, changeset} = Repo.update(changeset)
      assert "must be between 1 and 20" in errors_on(changeset).vote_limit
    end

    test "locks options after Setup", %{scope: scope, retro: retro} do
      {:ok, _} = Retros.advance_phase(scope, retro.id)

      assert {:error, :locked} = Retros.update_options(scope, retro.id, %{"vote_limit" => "3"})
    end

    test "rejects participants", %{participant: participant, retro: retro} do
      assert {:error, :unauthorized} =
               Retros.update_options(participant, retro.id, %{"vote_limit" => "3"})
    end
  end

  describe "finish_retro" do
    test "only works in Summary", %{scope: scope, retro: retro} do
      assert {:error, :not_in_summary} = Retros.finish_retro(scope, retro.id)
    end

    test "sets ended_at and makes the retro read-only", %{scope: scope, retro: retro} do
      advance_to(scope, retro, :summary)
      :ok = Events.subscribe(retro.id)

      assert {:ok, %RetroSession{ended_at: %DateTime{}}} = Retros.finish_retro(scope, retro.id)
      assert_receive {:retro_updated, %RetroSession{ended_at: %DateTime{}}}
      assert Repo.get!(RetroSession, retro.id).ended_at

      assert {:error, :ended} = Retros.finish_retro(scope, retro.id)
      assert {:error, :ended} = Retros.advance_phase(scope, retro.id)
      assert {:error, :ended} = Retros.update_options(scope, retro.id, %{})
    end

    test "rejects participants", %{scope: scope, participant: participant, retro: retro} do
      advance_to(scope, retro, :summary)
      assert {:error, :unauthorized} = Retros.finish_retro(participant, retro.id)
    end
  end

  test "change_options/2 returns a changeset", %{retro: retro} do
    assert Retros.change_options(retro).valid?
    refute Retros.change_options(retro, %{"vote_limit" => "99"}).valid?
  end
end
