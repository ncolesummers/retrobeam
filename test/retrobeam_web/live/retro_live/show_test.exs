defmodule RetrobeamWeb.RetroLive.ShowTest do
  use RetrobeamWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Retrobeam.AccountsFixtures
  import Retrobeam.RetrosFixtures

  setup :register_and_log_in_user

  test "shows the title, join code, phase and columns", %{conn: conn, scope: scope} do
    retro = retro_fixture(scope, %{"title" => "Sprint 4", "template" => "mad_sad_glad"})

    {:ok, view, html} = live(conn, ~p"/retros/#{retro}")

    assert html =~ "Sprint 4"
    assert has_element?(view, "#join-code", retro.join_code)
    assert has_element?(view, "#retro-phase", "Setup")

    for name <- ~w(Mad Sad Glad) do
      assert has_element?(view, "#retro-columns h2", name)
    end
  end

  test "joins the retro's session process when connected", %{conn: conn, scope: scope} do
    retro = retro_fixture(scope)

    {:ok, view, _html} = live(conn, ~p"/retros/#{retro}")

    server = Retrobeam.Retros.RetroServer.whereis(retro.id)
    assert is_pid(server)
    assert view.pid in Map.values(:sys.get_state(server).viewers)

    assert Phoenix.PubSub.broadcast(
             Retrobeam.PubSub,
             Retrobeam.Retros.Events.topic(retro.id),
             :unknown_event
           ) == :ok

    assert render(view) =~ retro.title
  end

  test "lets joined participants open the retro", %{conn: conn, user: user} do
    retro = retro_fixture(user_scope_fixture())
    participation_fixture(retro, user)

    assert {:ok, _view, _html} = live(conn, ~p"/retros/#{retro}")
  end

  test "treats retros the user hasn't joined as not found", %{conn: conn} do
    retro = retro_fixture(user_scope_fixture())

    assert {:error, {:live_redirect, %{to: "/retros/join", flash: joined_flash}}} =
             live(conn, ~p"/retros/#{retro}")

    assert {:error, {:live_redirect, %{to: "/retros/join", flash: unknown_flash}}} =
             live(conn, ~p"/retros/0")

    # The same answer either way, and never the retro's join code.
    assert joined_flash == unknown_flash
    assert joined_flash["error"] =~ "couldn't find that retro"
    refute joined_flash["error"] =~ retro.join_code
  end

  test "shows a copyable join link", %{conn: conn, scope: scope} do
    retro = retro_fixture(scope)

    {:ok, view, _html} = live(conn, ~p"/retros/#{retro}")

    join_url = url(~p"/retros/join/#{retro.join_code}")
    assert has_element?(view, ~s|#join-link[value="#{join_url}"]|)
    assert has_element?(view, ~s|#copy-join-link[data-text="#{join_url}"]|)
  end

  test "shows ended retros as read-only without a join link", %{conn: conn, scope: scope} do
    retro = retro_fixture(scope)

    retro
    |> Ecto.Changeset.change(ended_at: DateTime.utc_now(:second))
    |> Retrobeam.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/retros/#{retro}")

    assert has_element?(view, "#retro-ended", "finished")
    refute has_element?(view, "#join-link")
  end

  test "an id outside the bigint range is not found, not a crash", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/retros/join"}}} =
             live(conn, "/retros/99999999999999999999")
  end
end
