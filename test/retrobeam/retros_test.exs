defmodule Retrobeam.RetrosTest do
  use Retrobeam.DataCase, async: true

  import Retrobeam.AccountsFixtures
  import Retrobeam.RetrosFixtures

  alias Retrobeam.Retros
  alias Retrobeam.Retros.{JoinCode, RetroColumn, RetroParticipation, RetroSession, Template}

  setup do
    %{scope: user_scope_fixture()}
  end

  describe "create_retro/3" do
    test "creates a retro in setup with default options", %{scope: scope} do
      assert {:ok, %RetroSession{} = retro} =
               Retros.create_retro(scope, %{
                 "title" => "  Sprint 1  ",
                 "template" => "mad_sad_glad"
               })

      assert retro.title == "Sprint 1"
      assert retro.template == :mad_sad_glad
      assert retro.phase == :setup
      assert retro.vote_limit == 5
      assert retro.allow_multiple_votes
      refute retro.anonymous
      refute retro.hide_cards_during_collect
      assert retro.facilitator_id == scope.user.id
      assert JoinCode.valid?(retro.join_code)
    end

    for template <- Template.all() do
      @template template
      test "copies the #{@template.name} columns", %{scope: scope} do
        retro = retro_fixture(scope, %{"template" => to_string(@template.key)})

        columns =
          Repo.all(
            from c in RetroColumn, where: c.retro_session_id == ^retro.id, order_by: c.position
          )

        assert Enum.map(columns, &{&1.name, &1.description, &1.position}) ==
                 Enum.map(@template.columns, &{&1.name, &1.description, &1.position})
      end
    end

    test "creates custom columns", %{scope: scope} do
      retro =
        retro_fixture(scope, %{
          "template" => "custom",
          "custom_columns" => [" Wins ", "Puzzles"]
        })

      names =
        Repo.all(
          from c in RetroColumn,
            where: c.retro_session_id == ^retro.id,
            order_by: c.position,
            select: c.name
        )

      assert names == ["Wins", "Puzzles"]
      assert retro.template == :custom
    end

    test "adds the facilitator as a participant", %{scope: scope} do
      retro = retro_fixture(scope)

      assert [participation] =
               Repo.all(from p in RetroParticipation, where: p.retro_session_id == ^retro.id)

      assert participation.user_id == scope.user.id
      assert participation.role == :facilitator
      assert participation.joined_at
    end

    test "rejects invalid custom columns and writes nothing", %{scope: scope} do
      assert {:error, changeset} =
               Retros.create_retro(scope, %{
                 "title" => "X",
                 "template" => "custom",
                 "custom_columns" => ["Only one"]
               })

      assert "Add at least 2 columns." in errors_on(changeset).custom_columns
      assert Repo.aggregate(RetroSession, :count) == 0
      assert Repo.aggregate(RetroColumn, :count) == 0
      assert Repo.aggregate(RetroParticipation, :count) == 0
    end

    test "reports blank custom column names", %{scope: scope} do
      assert {:error, changeset} =
               Retros.create_retro(
                 scope,
                 valid_retro_attributes(%{
                   "template" => "custom",
                   "custom_columns" => ["A", " ", "B"]
                 })
               )

      assert "Every column needs a name." in errors_on(changeset).custom_columns
    end

    test "requires a title and a known template", %{scope: scope} do
      assert {:error, changeset} =
               Retros.create_retro(scope, %{"title" => " ", "template" => "nope"})

      errors = errors_on(changeset)
      assert "can't be blank" in errors.title
      assert "is invalid" in errors.template
    end

    test "limits the title length", %{scope: scope} do
      title = String.duplicate("a", 101)

      assert {:error, changeset} =
               Retros.create_retro(scope, valid_retro_attributes(%{"title" => title}))

      assert "should be at most 100 character(s)" in errors_on(changeset).title
    end

    test "retries with a new join code when the code is taken", %{scope: scope} do
      {:ok, first} =
        Retros.create_retro(scope, valid_retro_attributes(),
          generate_join_code: fn -> "ABCDEF" end
        )

      codes = start_supervised!({Agent, fn -> ["ABCDEF", "ABCDEF", "GHJKMN"] end})
      next_code = fn -> Agent.get_and_update(codes, fn [code | rest] -> {code, rest} end) end

      assert {:ok, second} =
               Retros.create_retro(scope, valid_retro_attributes(), generate_join_code: next_code)

      assert first.join_code == "ABCDEF"
      assert second.join_code == "GHJKMN"
      assert Repo.aggregate(RetroSession, :count) == 2
    end

    test "gives up after repeated join code collisions", %{scope: scope} do
      same = fn -> "ABCDEF" end
      {:ok, _} = Retros.create_retro(scope, valid_retro_attributes(), generate_join_code: same)

      assert {:error, changeset} =
               Retros.create_retro(scope, valid_retro_attributes(), generate_join_code: same)

      assert "has already been taken" in errors_on(changeset).join_code
    end
  end

  describe "change_retro/3" do
    test "returns a form changeset", %{scope: scope} do
      changeset =
        Retros.change_retro(scope, %RetroSession{}, %{"title" => "Hi", "template" => "four_ls"})

      assert changeset.valid?

      changeset = Retros.change_retro(scope)
      refute changeset.valid?
    end
  end

  describe "list_retros/1" do
    test "lists facilitated and joined retros, newest first", %{scope: scope} do
      other_scope = user_scope_fixture()
      mine = retro_fixture(scope, %{"title" => "Mine"})
      joined = retro_fixture(other_scope, %{"title" => "Joined"})
      _hidden = retro_fixture(other_scope, %{"title" => "Not mine"})
      participation_fixture(joined, scope.user)

      assert Enum.map(Retros.list_retros(scope), & &1.id) == [joined.id, mine.id]
    end

    test "returns an empty list for a new user", %{scope: scope} do
      assert Retros.list_retros(scope) == []
    end
  end

  describe "fetch_retro/2" do
    test "returns the retro with columns in order", %{scope: scope} do
      retro = retro_fixture(scope, %{"template" => "sailboat"})

      assert {:ok, fetched} = Retros.fetch_retro(scope, to_string(retro.id))
      assert fetched.id == retro.id
      assert Enum.map(fetched.columns, & &1.name) == ~w(Wind Anchor Rocks Island)
      assert {:ok, _} = Retros.fetch_retro(scope, retro.id)
    end

    test "rejects users who have not joined", %{scope: scope} do
      retro = retro_fixture(scope)
      outsider = user_scope_fixture()

      assert {:error, :not_participant, %RetroSession{id: id}} =
               Retros.fetch_retro(outsider, retro.id)

      assert id == retro.id
    end

    test "returns not found for unknown or malformed ids", %{scope: scope} do
      assert {:error, :not_found} = Retros.fetch_retro(scope, -1)
      assert {:error, :not_found} = Retros.fetch_retro(scope, "abc")
      assert {:error, :not_found} = Retros.fetch_retro(scope, "1abc")
      assert {:error, :not_found} = Retros.fetch_retro(scope, nil)
    end
  end

  test "facilitator?/2", %{scope: scope} do
    retro = retro_fixture(scope)
    assert Retros.facilitator?(scope, retro)
    refute Retros.facilitator?(user_scope_fixture(), retro)
  end

  describe "RetroSession helpers" do
    test "phase labels and ended?" do
      assert Enum.map(RetroSession.phases(), &RetroSession.phase_label/1) ==
               ~w(Setup Collect Group Vote Discuss Summary)

      refute RetroSession.ended?(%RetroSession{})
      assert RetroSession.ended?(%RetroSession{ended_at: DateTime.utc_now()})
    end
  end
end
