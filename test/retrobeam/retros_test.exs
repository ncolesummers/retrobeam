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

    test "a failed child insert rolls back the whole retro", %{scope: scope} do
      changeset =
        RetroSession.create_changeset(
          %RetroSession{},
          valid_retro_attributes(),
          scope.user.id,
          JoinCode.generate()
        )

      # Two facilitator rows for the same user: the retro and its columns are
      # written first, then the second participation hits the unique index.
      participation = %RetroParticipation{
        user_id: scope.user.id,
        role: :facilitator,
        joined_at: DateTime.utc_now(:second)
      }

      changeset =
        Ecto.Changeset.put_assoc(changeset, :participations, [participation, participation])

      assert_raise Ecto.ConstraintError, fn -> Repo.insert(changeset) end
      assert Repo.aggregate(RetroSession, :count) == 0
      assert Repo.aggregate(RetroColumn, :count) == 0
      assert Repo.aggregate(RetroParticipation, :count) == 0
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

      assert {:error, :not_found} = Retros.fetch_retro(outsider, retro.id)
    end

    test "returns not found for unknown or malformed ids", %{scope: scope} do
      assert {:error, :not_found} = Retros.fetch_retro(scope, -1)
      assert {:error, :not_found} = Retros.fetch_retro(scope, "abc")
      assert {:error, :not_found} = Retros.fetch_retro(scope, "1abc")
      assert {:error, :not_found} = Retros.fetch_retro(scope, nil)
      assert {:error, :not_found} = Retros.fetch_retro(scope, 0)
      assert {:error, :not_found} = Retros.fetch_retro(scope, "99999999999999999999")
      assert {:error, :not_found} = Retros.fetch_retro(scope, 9_223_372_036_854_775_808)
    end
  end

  describe "join_retro/2" do
    setup %{scope: scope} do
      %{retro: retro_fixture(scope), joiner: user_scope_fixture()}
    end

    test "adds the user as a participant", %{retro: retro, joiner: joiner} do
      assert {:ok, %RetroSession{id: id}} = Retros.join_retro(joiner, retro.join_code)
      assert id == retro.id

      participation = Repo.get_by!(RetroParticipation, user_id: joiner.user.id)
      assert participation.role == :participant
      assert {:ok, _} = Retros.fetch_retro(joiner, retro.id)
    end

    test "matches lower-case codes with surrounding spaces", %{retro: retro, joiner: joiner} do
      assert {:ok, _} = Retros.join_retro(joiner, "  #{String.downcase(retro.join_code)}\n")
    end

    test "joining twice keeps one participation", %{retro: retro, joiner: joiner} do
      assert {:ok, _} = Retros.join_retro(joiner, retro.join_code)
      assert {:ok, _} = Retros.join_retro(joiner, retro.join_code)

      assert Repo.aggregate(
               from(p in RetroParticipation, where: p.user_id == ^joiner.user.id),
               :count
             ) == 1
    end

    test "the facilitator keeps their role", %{retro: retro, scope: scope} do
      assert {:ok, _} = Retros.join_retro(scope, retro.join_code)
      assert Repo.get_by!(RetroParticipation, user_id: scope.user.id).role == :facilitator
    end

    test "ended retros can be joined", %{retro: retro, joiner: joiner} do
      retro |> Ecto.Changeset.change(ended_at: DateTime.utc_now(:second)) |> Repo.update!()
      assert {:ok, _} = Retros.join_retro(joiner, retro.join_code)
    end

    test "rejects unknown and malformed codes", %{joiner: joiner} do
      assert {:error, :not_found} = Retros.join_retro(joiner, "ZZZZZZ")
      assert {:error, :not_found} = Retros.join_retro(joiner, "ABC")
      assert {:error, :not_found} = Retros.join_retro(joiner, nil)
    end

    test "limits failed attempts per user", %{retro: retro, joiner: joiner} do
      for _ <- 1..10, do: assert({:error, :not_found} = Retros.join_retro(joiner, "ZZZZZZ"))

      assert {:error, :rate_limited} = Retros.join_retro(joiner, "ZZZZZZ")
      # Even the right code is refused until the window ends.
      assert {:error, :rate_limited} = Retros.join_retro(joiner, retro.join_code)

      # Other users are unaffected.
      assert {:ok, _} = Retros.join_retro(user_scope_fixture(), retro.join_code)
    end

    test "limits failed attempts per IP address across users", %{retro: retro} do
      ip = "203.0.113.#{System.unique_integer([:positive])}"
      # A per-call limit, so other tests sharing the config aren't affected.
      opts = [ip: ip, limits: [ip_limit: 3]]

      for _ <- 1..3 do
        assert {:error, :not_found} = Retros.join_retro(user_scope_fixture(), "ZZZZZZ", opts)
      end

      assert {:error, :rate_limited} =
               Retros.join_retro(user_scope_fixture(), retro.join_code, opts)

      assert {:ok, _} =
               Retros.join_retro(user_scope_fixture(), retro.join_code,
                 ip: "198.51.100.1",
                 limits: [ip_limit: 3]
               )
    end

    test "successful joins don't count against the limit", %{retro: retro, joiner: joiner} do
      for _ <- 1..15, do: assert({:ok, _} = Retros.join_retro(joiner, retro.join_code))
    end

    test "a retro deleted before the insert is not found, not a crash", %{joiner: joiner} do
      changeset =
        %RetroParticipation{retro_session_id: -1}
        |> RetroParticipation.changeset(%{
          user_id: joiner.user.id,
          role: :participant,
          joined_at: DateTime.utc_now(:second)
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset).retro_session_id
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
