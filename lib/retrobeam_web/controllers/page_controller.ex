defmodule RetrobeamWeb.PageController do
  use RetrobeamWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
