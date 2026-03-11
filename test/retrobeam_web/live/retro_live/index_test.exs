defmodule RetrobeamWeb.RetroLive.IndexTest do
  use RetrobeamWeb.ConnCase, async: true

  import Retrobeam.AccountsFixtures

  describe "GET /retros" do
    test "redirects to login when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/retros")
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "renders the retro dashboard for authenticated users", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/retros")
      response = html_response(conn, 200)
      assert response =~ "My Retrospectives"
    end
  end
end
