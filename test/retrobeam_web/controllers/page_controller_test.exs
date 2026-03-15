defmodule RetrobeamWeb.PageControllerTest do
  use RetrobeamWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Better retros."
  end
end
