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

  test "lets joined participants open the retro", %{conn: conn, user: user} do
    retro = retro_fixture(user_scope_fixture())
    participation_fixture(retro, user)

    assert {:ok, _view, _html} = live(conn, ~p"/retros/#{retro}")
  end

  test "redirects users who have not joined", %{conn: conn} do
    retro = retro_fixture(user_scope_fixture())

    assert {:error, {:live_redirect, %{to: "/retros", flash: flash}}} =
             live(conn, ~p"/retros/#{retro}")

    assert flash["error"] =~ "haven't joined"
  end

  test "redirects for unknown retros", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/retros", flash: flash}}} = live(conn, ~p"/retros/0")
    assert flash["error"] =~ "doesn't exist"
  end
end
