defmodule RetrobeamWeb.HealthController do
  use RetrobeamWeb, :controller

  def index(conn, _params) do
    Ecto.Adapters.SQL.query!(Retrobeam.Repo, "SELECT 1")
    conn |> put_resp_content_type("text/plain") |> send_resp(200, "ok")
  rescue
    _ ->
      conn |> put_resp_content_type("text/plain") |> send_resp(503, "unavailable")
  end
end
