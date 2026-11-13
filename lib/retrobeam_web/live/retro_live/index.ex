defmodule RetrobeamWeb.RetroLive.Index do
  use RetrobeamWeb, :live_view

  alias Retrobeam.Retros
  alias Retrobeam.Retros.RetroSession

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        My Retrospectives
        <:subtitle>Retros you facilitate or have joined, newest first.</:subtitle>
        <:actions>
          <.button variant="primary" navigate={~p"/retros/new"}>
            <.icon name="hero-plus" class="size-5" /> New retro
          </.button>
        </:actions>
      </.header>

      <ul id="retros" phx-update="stream" class="space-y-3">
        <li
          id="retros-empty"
          class="hidden only:block rounded-box border border-dashed border-base-300 p-8 text-center"
        >
          <p class="font-semibold">No retros yet</p>
          <p class="mt-1 text-sm leading-6 text-base-content/70">
            Start one with "New retro" and share the join code with your team.
          </p>
        </li>
        <li :for={{dom_id, retro} <- @streams.retros} id={dom_id}>
          <.link
            navigate={~p"/retros/#{retro}"}
            class="flex items-center justify-between gap-4 rounded-box border border-base-300 bg-base-200 p-4 hover:border-primary focus-visible:outline-2 focus-visible:outline-primary"
          >
            <div class="min-w-0">
              <p class="truncate font-semibold">{retro.title}</p>
              <p class="text-sm leading-6 text-base-content/70">
                Created {Calendar.strftime(retro.inserted_at, "%b %-d, %Y")}
              </p>
            </div>
            <div class="flex flex-none items-center gap-2">
              <span
                :if={retro.facilitator_id == @current_scope.user.id}
                class="badge badge-secondary badge-soft"
              >
                Facilitator
              </span>
              <span class="badge badge-neutral badge-outline">
                {phase_text(retro)}
              </span>
            </div>
          </.link>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    retros = Retros.list_retros(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:page_title, "My Retrospectives")
     |> stream(:retros, retros)}
  end

  defp phase_text(%RetroSession{} = retro) do
    if RetroSession.ended?(retro), do: "Finished", else: RetroSession.phase_label(retro.phase)
  end
end
