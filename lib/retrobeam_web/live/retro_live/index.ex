defmodule RetrobeamWeb.RetroLive.Index do
  use RetrobeamWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        My Retrospectives
        <:subtitle>Your retro dashboard will appear here.</:subtitle>
      </.header>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
