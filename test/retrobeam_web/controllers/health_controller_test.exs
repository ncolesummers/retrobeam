defmodule RetrobeamWeb.HealthControllerTest do
  use RetrobeamWeb.ConnCase, async: true

  test "GET /healthz returns 200 when database is connected", %{conn: conn} do
    conn = get(conn, ~p"/healthz")
    assert response(conn, 200) == "ok"
  end
end
