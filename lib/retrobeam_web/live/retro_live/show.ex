defmodule RetrobeamWeb.RetroLive.Show do
  use RetrobeamWeb, :live_view

  alias Retrobeam.Retros
  alias Retrobeam.Retros.{Card, Events, RetroServer, RetroSession}
  alias RetrobeamWeb.RetroLive.ColumnComponent

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

      <nav aria-label="Retro phases">
        <ol id="phase-steps" class="steps w-full">
          <li
            :for={phase <- RetroSession.phases()}
            id={"phase-#{phase}"}
            data-state={phase_state(@retro, phase)}
            data-content={phase_state(@retro, phase) == :done && "✓"}
            aria-current={phase_state(@retro, phase) == :current && "step"}
            class={[
              "step",
              phase_state(@retro, phase) != :upcoming && "step-primary",
              phase_state(@retro, phase) == :current && "font-semibold"
            ]}
          >
            {RetroSession.phase_label(phase)}
            <span class="sr-only">({phase_state_text(phase_state(@retro, phase))})</span>
          </li>
        </ol>
      </nav>

      <div
        :if={@facilitator? and not RetroSession.ended?(@retro)}
        id="facilitator-controls"
        class="flex flex-wrap items-center gap-3 rounded-box border border-secondary/40 bg-base-200 p-4"
      >
        <span class="badge badge-secondary">Facilitator</span>
        <button
          :if={next = RetroSession.next_phase(@retro.phase)}
          id="next-phase"
          type="button"
          phx-click="advance_phase"
          phx-value-from={@retro.phase}
          phx-disable-with="Moving on..."
          class="btn btn-primary"
        >
          Next phase: {RetroSession.phase_label(next)}
          <.icon name="hero-arrow-right" class="size-5" />
        </button>
        <button
          :if={@retro.phase == :summary}
          id="finish-retro"
          type="button"
          phx-click="finish"
          data-confirm="Finish this retro? Nobody will be able to change it afterwards."
          class="btn btn-primary"
        >
          <.icon name="hero-check-circle" class="size-5" /> Finish retro
        </button>
      </div>

      <section
        :if={@options_form}
        id="setup-options"
        aria-labelledby="setup-options-title"
        class="rounded-box border border-base-300 bg-base-200 p-4"
      >
        <h2 id="setup-options-title" class="font-bold tracking-tight">Setup options</h2>
        <p class="text-sm leading-6 text-base-content/70">
          These lock when the retro moves past Setup.
        </p>
        <.form
          for={@options_form}
          id="options-form"
          phx-change="validate_options"
          phx-submit="save_options"
          class="mt-3 grid gap-x-6 sm:grid-cols-2"
        >
          <.input
            field={@options_form[:vote_limit]}
            type="number"
            min="1"
            max="20"
            label="Votes per person (1 to 20)"
          />
          <div class="space-y-1 pt-6">
            <.input
              field={@options_form[:allow_multiple_votes]}
              type="checkbox"
              label="Allow several votes on one card"
            />
            <.input
              field={@options_form[:anonymous]}
              type="checkbox"
              label="Anonymous cards"
            />
            <.input
              field={@options_form[:hide_cards_during_collect]}
              type="checkbox"
              label="Hide cards until Collect ends"
            />
          </div>
          <div class="sm:col-span-2">
            <.button variant="primary" phx-disable-with="Saving...">Save options</.button>
          </div>
        </.form>
      </section>

      <dl
        :if={!@options_form}
        id="retro-options"
        class="flex flex-wrap gap-x-6 gap-y-1 text-sm leading-6 text-base-content/70"
      >
        <div class="flex gap-1">
          <dt>Votes per person:</dt>
          <dd class="font-semibold text-base-content">{@retro.vote_limit}</dd>
        </div>
        <div class="flex gap-1">
          <dt>Several votes per card:</dt>
          <dd class="font-semibold text-base-content">{yes_no(@retro.allow_multiple_votes)}</dd>
        </div>
        <div class="flex gap-1">
          <dt>Anonymous cards:</dt>
          <dd class="font-semibold text-base-content">{yes_no(@retro.anonymous)}</dd>
        </div>
        <div class="flex gap-1">
          <dt>Cards hidden during Collect:</dt>
          <dd class="font-semibold text-base-content">
            {yes_no(@retro.hide_cards_during_collect)}
          </dd>
        </div>
      </dl>

      <div
        :if={RetroSession.ended?(@retro)}
        id="retro-ended"
        role="status"
        class="alert alert-info alert-soft"
      >
        <.icon name="hero-lock-closed" class="size-5" />
        <span>This retro is finished. You can look, but nothing can change.</span>
      </div>

      <div :if={!RetroSession.ended?(@retro)} class="flex flex-wrap items-end gap-2">
        <label for="join-link" class="w-full text-sm leading-6 text-base-content/70 sm:w-auto">
          Join link
        </label>
        <input
          id="join-link"
          type="text"
          value={@join_url}
          readonly
          class="input input-sm min-w-0 flex-1 font-mono"
        />
        <button
          id="copy-join-link"
          type="button"
          phx-hook=".CopyJoinLink"
          data-text={@join_url}
          class="btn btn-primary btn-soft btn-sm"
        >
          <.icon name="hero-clipboard-document" class="size-4" /> Copy link
        </button>
        <span id="copy-join-link-status" aria-live="polite" class="text-sm text-base-content/70">
        </span>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyJoinLink">
        export default {
          mounted() {
            const status = document.getElementById("copy-join-link-status")
            this.el.addEventListener("click", () => {
              navigator.clipboard.writeText(this.el.dataset.text).then(
                () => { status.textContent = "Copied" },
                () => { status.textContent = "Copy failed. Select the link and copy it." }
              )
            })
          }
        }
      </script>

      <div id="retro-columns" class={["grid items-start gap-4", grid_class(length(@retro.columns))]}>
        <.live_component
          :for={column <- @retro.columns}
          module={ColumnComponent}
          id={"column-#{column.id}"}
          column={column}
          retro={@retro}
          scope={@current_scope}
          current_user_id={@current_scope.user.id}
          participant?={true}
          board_version={@board_version}
        />
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Retros.fetch_retro(socket.assigns.current_scope, id) do
      {:ok, retro} ->
        retro = connect_to_session(socket, retro)

        {:ok,
         socket
         |> assign(:page_title, retro.title)
         |> assign(:join_url, url(~p"/retros/join/#{retro.join_code}"))
         |> assign(:facilitator?, Retros.facilitator?(socket.assigns.current_scope, retro))
         |> assign(:board_version, 0)
         |> assign_retro(retro)}

      {:error, :not_participant, retro} ->
        {:ok,
         socket
         |> put_flash(:info, "Join this retro to take part.")
         |> push_navigate(to: ~p"/retros/join/#{retro.join_code}")}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "That retro doesn't exist.")
         |> push_navigate(to: ~p"/retros")}
    end
  end

  @impl true
  def handle_event("advance_phase", %{"from" => from}, socket) do
    %{current_scope: scope, retro: retro} = socket.assigns

    case Retros.advance_phase(scope, retro.id, to_phase(from)) do
      {:ok, retro} -> {:noreply, assign_retro(socket, retro)}
      {:error, reason} -> {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  def handle_event("validate_options", %{"retro_session" => params}, socket) do
    form =
      socket.assigns.retro
      |> Retros.change_options(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :options_form, form)}
  end

  def handle_event("save_options", %{"retro_session" => params}, socket) do
    %{current_scope: scope, retro: retro} = socket.assigns

    case Retros.update_options(scope, retro.id, params) do
      {:ok, retro} ->
        {:noreply, socket |> put_flash(:info, "Options saved.") |> assign_retro(retro)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :options_form, to_form(changeset))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  def handle_event("finish", _params, socket) do
    %{current_scope: scope, retro: retro} = socket.assigns

    case Retros.finish_retro(scope, retro.id) do
      {:ok, retro} ->
        {:noreply, socket |> put_flash(:info, "Retro finished.") |> assign_retro(retro)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  @impl true
  # A new phase can reveal hidden cards or lock them, so every column
  # reloads its cards.
  def handle_info({:phase_changed, %RetroSession{} = retro}, socket) do
    {:noreply, socket |> assign_retro(retro) |> update(:board_version, &(&1 + 1))}
  end

  def handle_info({:retro_updated, %RetroSession{} = retro}, socket) do
    {:noreply, assign_retro(socket, retro)}
  end

  def handle_info({event, %Card{} = card}, socket)
      when event in [:card_created, :card_updated, :card_deleted] do
    action =
      case event do
        :card_created -> :created
        :card_updated -> :updated
        :card_deleted -> :deleted
      end

    send_update(ColumnComponent, id: "column-#{card.retro_column_id}", card_event: {action, card})
    {:noreply, socket}
  end

  # Stories that add retro events add a clause above this one for each event.
  def handle_info(_event, socket), do: {:noreply, socket}

  # Keeps the columns already loaded and rebuilds the options form, which
  # only the facilitator sees, and only during Setup.
  defp assign_retro(socket, %RetroSession{} = retro) do
    retro =
      case {retro.columns, socket.assigns[:retro]} do
        {%Ecto.Association.NotLoaded{}, %RetroSession{columns: columns}} ->
          %{retro | columns: columns}

        _ ->
          retro
      end

    options_form =
      if socket.assigns.facilitator? and retro.phase == :setup and not RetroSession.ended?(retro),
        do: to_form(Retros.change_options(retro)),
        else: nil

    socket
    |> assign(:retro, retro)
    |> assign(:options_form, options_form)
  end

  defp phase_state(%RetroSession{} = retro, phase) do
    phases = RetroSession.phases()
    current = Enum.find_index(phases, &(&1 == retro.phase))
    index = Enum.find_index(phases, &(&1 == phase))

    cond do
      RetroSession.ended?(retro) -> :done
      index < current -> :done
      index == current -> :current
      true -> :upcoming
    end
  end

  defp phase_state_text(:done), do: "completed"
  defp phase_state_text(:current), do: "current phase"
  defp phase_state_text(:upcoming), do: "upcoming"

  # An unknown value never matches the current phase, so it is rejected
  # as stale rather than advancing anything.
  defp to_phase(from) do
    Enum.find(RetroSession.phases(), :unknown, &(Atom.to_string(&1) == from))
  end

  defp yes_no(true), do: "Yes"
  defp yes_no(_), do: "No"

  defp error_message(:unauthorized), do: "Only the facilitator can do that."
  defp error_message(:ended), do: "This retro is finished."
  defp error_message(:locked), do: "Options lock once the retro leaves Setup."
  defp error_message(:stale_phase), do: "The retro has already moved on."
  defp error_message(:final_phase), do: "This is the last phase."
  defp error_message(:not_in_summary), do: "You can finish the retro from the Summary phase."
  defp error_message(:not_found), do: "That retro doesn't exist."

  # Once the socket is connected, register with the retro's session process
  # and listen for its events. The server's cached state is the source of
  # truth from then on.
  defp connect_to_session(socket, retro) do
    if connected?(socket) do
      :ok = Events.subscribe(retro.id)

      {:ok, %RetroServer.State{retro: retro}} =
        RetroServer.join(retro.id, socket.assigns.current_scope)

      retro
    else
      retro
    end
  end

  # Spell the code out so screen readers read it character by character.
  defp spell(code), do: code |> String.graphemes() |> Enum.join(" ")

  defp grid_class(count) when count <= 2, do: "md:grid-cols-2"
  defp grid_class(3), do: "md:grid-cols-3"
  defp grid_class(4), do: "md:grid-cols-2 lg:grid-cols-4"
  defp grid_class(_count), do: "md:grid-cols-3"
end
