defmodule RetrobeamWeb.RetroLive.Show do
  use RetrobeamWeb, :live_view

  alias Retrobeam.Retros
  alias Retrobeam.Retros.RetroSession

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <.header>
        {@retro.title}
        <:subtitle>
          <span id="retro-phase">Phase: {RetroSession.phase_label(@retro.phase)}</span>
        </:subtitle>
        <:actions>
          <div class="text-right">
            <p class="text-sm leading-6 text-base-content/70">Join code</p>
            <p
              id="join-code"
              class="font-mono text-2xl font-bold tracking-[0.2em]"
              aria-label={"Join code #{spell(@retro.join_code)}"}
            >
              {@retro.join_code}
            </p>
          </div>
        </:actions>
      </.header>

      <div id="retro-columns" class={["grid gap-4", grid_class(length(@retro.columns))]}>
        <section
          :for={column <- @retro.columns}
          id={"column-#{column.id}"}
          aria-labelledby={"column-#{column.id}-name"}
          class="rounded-box border border-base-300 bg-base-200 p-4"
        >
          <h2 id={"column-#{column.id}-name"} class="font-bold tracking-tight">
            {column.name}
          </h2>
          <p :if={column.description} class="text-sm leading-6 text-base-content/70">
            {column.description}
          </p>
          <p class="mt-4 text-sm text-base-content/60">No cards yet.</p>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Retros.fetch_retro(socket.assigns.current_scope, id) do
      {:ok, retro} ->
        {:ok,
         socket
         |> assign(:page_title, retro.title)
         |> assign(:retro, retro)}

      {:error, :not_participant, _retro} ->
        {:ok,
         socket
         |> put_flash(
           :error,
           "You haven't joined that retro. Ask the facilitator for its join code."
         )
         |> push_navigate(to: ~p"/retros")}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "That retro doesn't exist.")
         |> push_navigate(to: ~p"/retros")}
    end
  end

  # Spell the code out so screen readers read it character by character.
  defp spell(code), do: code |> String.graphemes() |> Enum.join(" ")

  defp grid_class(count) when count <= 2, do: "md:grid-cols-2"
  defp grid_class(3), do: "md:grid-cols-3"
  defp grid_class(4), do: "md:grid-cols-2 lg:grid-cols-4"
  defp grid_class(_count), do: "md:grid-cols-3"
end
