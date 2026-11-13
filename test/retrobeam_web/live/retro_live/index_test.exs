defmodule RetrobeamWeb.RetroLive.IndexTest do
  use RetrobeamWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Retrobeam.AccountsFixtures
  import Retrobeam.RetrosFixtures

  test "redirects to login when not authenticated", %{conn: conn} do
    conn = get(conn, ~p"/retros")
    assert redirected_to(conn) == ~p"/users/log-in"
  end

  describe "dashboard" do
    setup :register_and_log_in_user

    test "shows an empty state and a New retro button", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/retros")

      assert html =~ "My Retrospectives"
      assert html =~ "No retros yet"
      assert has_element?(view, ~s|a[href="/retros/new"]|, "New retro")
    end

    test "lists facilitated and joined retros with their phase", %{conn: conn, scope: scope} do
      other = user_scope_fixture()
      mine = retro_fixture(scope, %{"title" => "Team A retro"})
      joined = retro_fixture(other, %{"title" => "Team B retro"})
      hidden = retro_fixture(other, %{"title" => "Someone else's"})
      participation_fixture(joined, scope.user)

      {:ok, view, html} = live(conn, ~p"/retros")

      assert has_element?(view, "#retros-#{mine.id}", "Facilitator")
      assert has_element?(view, "#retros-#{mine.id}", "Setup")
      assert has_element?(view, "#retros-#{joined.id}", "Team B retro")
      refute has_element?(view, "#retros-#{joined.id}", "Facilitator")
      refute html =~ hidden.title
    end

    test "shows Finished for ended retros", %{conn: conn, scope: scope} do
      retro = retro_fixture(scope)

      retro
      |> Ecto.Changeset.change(ended_at: DateTime.utc_now(:second))
      |> Retrobeam.Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/retros")
      assert has_element?(view, "#retros-#{retro.id}", "Finished")
    end
  end
end
