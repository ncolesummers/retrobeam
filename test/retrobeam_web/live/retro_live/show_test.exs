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

    # Subscribed to the retro's topic.
    assert Retrobeam.Retros.Events.topic(retro.id) in Registry.keys(Retrobeam.PubSub, view.pid)

    # Unknown events are ignored.
    :ok = Retrobeam.Retros.Events.broadcast(retro.id, :unknown_event)
    assert render(view) =~ retro.title
  end

  test "joins the restarted server after a crash", %{conn: conn, scope: scope} do
    retro = retro_fixture(scope)
    retro_id = retro.id
    {:ok, view, _html} = live(conn, ~p"/retros/#{retro}")
    # Let the view finish handling the server's start event first. Killing
    # the server in the middle of a query would break the test's sandbox.
    _ = render(view)

    :ok = Retrobeam.Retros.Events.subscribe(retro_id)
    server = Retrobeam.Retros.RetroServer.whereis(retro_id)
    ref = Process.monitor(server)
    Process.exit(server, :kill)
    assert_receive {:DOWN, ^ref, :process, ^server, :killed}

    # The supervisor restarts it and the restart announces itself. The view
    # got the same broadcast first, so after render/1 it has joined again.
    assert_receive {:retro_server_started, ^retro_id}, 1_000
    _ = render(view)

    restarted = Retrobeam.Retros.RetroServer.whereis(retro_id)
    assert is_pid(restarted) and restarted != server
    assert view.pid in Map.values(:sys.get_state(restarted).viewers)
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
