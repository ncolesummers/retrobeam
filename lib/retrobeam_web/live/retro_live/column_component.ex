defmodule RetrobeamWeb.RetroLive.ColumnComponent do
  @moduledoc """
  One column of the retro board, with its cards as a LiveView stream.

  The parent `RetroLive.Show` forwards card events from the retro's topic
  with `send_update(ColumnComponent, id: ..., card_event: event)` and bumps
  `board_version` when every card must be reloaded (for example when the
  Group phase reveals hidden cards).
  """
  use RetrobeamWeb, :live_component

  alias Retrobeam.Retros
  alias Retrobeam.Retros.{Card, RetroServer, RetroSession}

  @impl true
  def render(assigns) do
    ~H"""
    <section
      id={@id}
      aria-labelledby={"#{@id}-name"}
      class="flex flex-col gap-3 rounded-box border border-base-300 bg-base-200 p-4"
    >
      <div>
        <h2 id={"#{@id}-name"} class="font-bold tracking-tight">{@column.name}</h2>
        <p :if={@column.description} class="text-sm leading-6 text-base-content/70">
          {@column.description}
        </p>
      </div>

      <ul id={"#{@id}-cards"} phx-update="stream" class="space-y-2">
        <li id={"#{@id}-empty"} class="hidden only:block text-sm text-base-content/60">
          No cards yet.
        </li>
        <li
          :for={{dom_id, card} <- @streams.cards}
          id={dom_id}
          class="rounded-box border border-base-300 bg-base-100 p-3"
        >
          <.form
            :if={@editing_id == card.id}
            for={@edit_form}
            id={"edit-card-#{card.id}"}
            phx-submit="save"
            phx-target={@myself}
          >
            <input type="hidden" name="card[id]" value={card.id} />
            <label for={"edit-card-#{card.id}-body"} class="sr-only">Edit card</label>
            <textarea
              id={"edit-card-#{card.id}-body"}
              name="card[body]"
              phx-hook=".CardInput"
              phx-target={@myself}
              data-cancel-event="cancel_edit"
              data-card-id={card.id}
              data-save-on-blur
              data-autofocus
              rows="3"
              maxlength={Card.max_body_length()}
              class={["textarea w-full", @edit_form[:body].errors != [] && "textarea-error"]}
            >{@edit_form[:body].value}</textarea>
            <.card_errors field={@edit_form[:body]} />
            <p class="mt-1 text-xs text-base-content/70">
              Enter to save, Escape to cancel.
            </p>
          </.form>

          <div :if={@editing_id != card.id}>
            <p class="whitespace-pre-wrap break-words leading-6">{card.body}</p>
            <div class="mt-2 flex items-center justify-between gap-2">
              <.author card={card} retro={@retro} current_user_id={@current_user_id} />
              <div :if={can_edit?(card, @retro, @current_user_id)} class="flex gap-1">
                <button
                  type="button"
                  phx-click="edit"
                  phx-value-id={card.id}
                  phx-target={@myself}
                  class="btn btn-ghost btn-xs"
                  aria-label="Edit card"
                >
                  <.icon name="hero-pencil-square" class="size-4" />
                </button>
                <button
                  type="button"
                  phx-click="delete"
                  phx-value-id={card.id}
                  phx-target={@myself}
                  data-confirm="Delete this card?"
                  class="btn btn-ghost btn-xs"
                  aria-label="Delete card"
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </div>
            </div>
          </div>
        </li>
      </ul>

      <p
        :if={@hidden_count > 0}
        id={"#{@id}-hidden-count"}
        class="flex items-center gap-2 text-sm text-base-content/70"
      >
        <.icon name="hero-eye-slash" class="size-4" />
        {hidden_text(@hidden_count)}
      </p>

      <.form
        :if={can_add?(@retro, @participant?)}
        for={@add_form}
        id={"add-card-#{@column.id}"}
        phx-submit="add"
        phx-target={@myself}
        class="mt-auto"
      >
        <label for={"add-card-#{@column.id}-body"} class="sr-only">
          Add a card to {@column.name}
        </label>
        <textarea
          id={"add-card-#{@column.id}-body"}
          name="card[body]"
          phx-hook=".CardInput"
          phx-target={@myself}
          rows="2"
          maxlength={Card.max_body_length()}
          placeholder="Add a card"
          class={["textarea w-full", @add_form[:body].errors != [] && "textarea-error"]}
        >{@add_form[:body].value}</textarea>
        <.card_errors field={@add_form[:body]} />
        <div class="mt-2 flex items-center justify-between gap-2">
          <p class="text-xs text-base-content/70">Enter to add, Shift+Enter for a new line</p>
          <button type="submit" class="btn btn-primary btn-sm">Add card</button>
        </div>
      </.form>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".CardInput">
        // Enter submits, Shift+Enter adds a new line. Edit fields also save
        // on blur and cancel on Escape.
        export default {
          mounted() {
            this.done = false
            this.el.addEventListener("keydown", (e) => {
              if (e.key === "Enter" && !e.shiftKey && !e.isComposing) {
                e.preventDefault()
                this.done = this.el.dataset.saveOnBlur !== undefined
                this.el.form.requestSubmit()
              } else if (e.key === "Escape" && this.el.dataset.cancelEvent) {
                e.preventDefault()
                this.done = true
                this.pushEventTo(this.el, this.el.dataset.cancelEvent, {id: this.el.dataset.cardId})
              }
            })
            if (this.el.dataset.saveOnBlur !== undefined) {
              this.el.addEventListener("blur", () => {
                if (!this.done && this.el.isConnected) this.el.form.requestSubmit()
              })
            }
            this.handleEvent("reset-card-input", ({id}) => {
              if (id === this.el.id) this.el.value = ""
            })
            if (this.el.dataset.autofocus !== undefined) {
              this.el.focus()
              this.el.setSelectionRange(this.el.value.length, this.el.value.length)
            }
          }
        }
      </script>
    </section>
    """
  end

  attr :card, Card, required: true
  attr :retro, RetroSession, required: true
  attr :current_user_id, :integer, required: true

  defp author(assigns) do
    ~H"""
    <span
      :if={@retro.anonymous and @card.author_id == @current_user_id}
      class="text-xs text-base-content/70"
    >
      Your card
    </span>
    <span
      :if={not @retro.anonymous and @card.author}
      class="flex min-w-0 items-center gap-2 text-sm text-base-content/70"
    >
      <.avatar user={@card.author} class="size-5 text-[0.625rem]" />
      <span class="truncate">{@card.author.display_name}</span>
    </span>
    <span :if={@retro.anonymous and @card.author_id != @current_user_id}></span>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true

  defp card_errors(assigns) do
    ~H"""
    <p
      :for={msg <- Enum.map(@field.errors, &translate_error/1)}
      class="mt-1 flex items-center gap-2 text-sm text-error"
    >
      <.icon name="hero-exclamation-circle" class="size-4" /> Card {msg}
    </p>
    """
  end

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:editing_id, nil)
     |> assign(:hidden_count, 0)
     |> assign(:add_form, card_form())
     |> assign(:edit_form, card_form())}
  end

  @impl true
  def update(%{card_event: event}, socket), do: {:ok, apply_card_event(socket, event)}

  def update(assigns, socket) do
    reload? = socket.assigns[:board_version] != assigns.board_version
    socket = assign(socket, assigns)

    {:ok, if(reload?, do: load_cards(socket), else: socket)}
  end

  @impl true
  def handle_event("add", %{"card" => %{"body" => body}}, socket) do
    %{scope: scope, retro: retro, column: column} = socket.assigns

    case Retros.add_card(scope, retro.id, %{"column_id" => column.id, "body" => body}) do
      {:ok, card} ->
        {:noreply,
         socket
         |> stream_insert(:cards, card)
         |> assign(:add_form, card_form())
         |> push_event("reset-card-input", %{id: "add-card-#{column.id}-body"})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :add_form, to_form(changeset, as: :card))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    case fetch_card(socket, id) do
      {:ok, card} ->
        {:noreply,
         socket
         |> close_editor()
         |> assign(:editing_id, card.id)
         |> assign(:edit_form, card_form(card))
         |> stream_insert(:cards, card)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel_edit", _params, socket), do: {:noreply, close_editor(socket)}

  def handle_event("save", %{"card" => %{"id" => id, "body" => body}}, socket) do
    %{scope: scope, retro: retro} = socket.assigns

    case Retros.update_card(scope, retro.id, id, %{"body" => body}) do
      {:ok, card} ->
        {:noreply,
         socket
         |> assign(:editing_id, nil)
         |> assign(:edit_form, card_form())
         |> stream_insert(:cards, card)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:ok, card} = fetch_card(socket, id)

        {:noreply,
         socket
         |> assign(:edit_form, to_form(changeset, as: :card))
         |> stream_insert(:cards, card)}

      {:error, reason} ->
        {:noreply, socket |> close_editor() |> put_flash(:error, error_message(reason))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    %{scope: scope, retro: retro} = socket.assigns

    case Retros.delete_card(scope, retro.id, id) do
      {:ok, card} -> {:noreply, stream_delete(socket, :cards, card)}
      {:error, reason} -> {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  ## Card events from the retro topic

  defp apply_card_event(socket, {event, card}) do
    cond do
      hidden?(card, socket.assigns) ->
        case event do
          :created -> update(socket, :hidden_count, &(&1 + 1))
          :deleted -> update(socket, :hidden_count, &max(&1 - 1, 0))
          :updated -> socket
        end

      event == :deleted ->
        stream_delete(socket, :cards, card)

      # Keep an open editor as it is; the author's own save already
      # rendered the new body.
      event == :updated and socket.assigns.editing_id == card.id ->
        socket

      true ->
        stream_insert(socket, :cards, card)
    end
  end

  ## Helpers

  defp load_cards(socket) do
    %{retro: retro, column: column} = socket.assigns
    {:ok, state} = RetroServer.get_state(retro.id)

    cards =
      state.cards
      |> Map.values()
      |> Enum.filter(&(&1.retro_column_id == column.id))
      |> Enum.sort_by(&{&1.position, &1.id})

    {hidden, visible} = Enum.split_with(cards, &hidden?(&1, socket.assigns))

    socket
    |> assign(:editing_id, nil)
    |> assign(:hidden_count, length(hidden))
    |> stream(:cards, visible, reset: true)
  end

  defp close_editor(%{assigns: %{editing_id: nil}} = socket), do: socket

  defp close_editor(socket) do
    socket =
      case fetch_card(socket, socket.assigns.editing_id) do
        {:ok, card} -> socket |> assign(:editing_id, nil) |> stream_insert(:cards, card)
        :error -> assign(socket, :editing_id, nil)
      end

    assign(socket, :edit_form, card_form())
  end

  defp fetch_card(socket, id) do
    {:ok, state} = RetroServer.get_state(socket.assigns.retro.id)

    with {int, ""} <- Integer.parse(to_string(id)),
         %Card{retro_column_id: column_id} = card when column_id == socket.assigns.column.id <-
           state.cards[int] do
      {:ok, card}
    else
      _ -> :error
    end
  end

  defp card_form(card \\ %Card{}), do: to_form(Retros.change_card(card), as: :card)

  # Other participants' cards stay hidden during Collect when the
  # facilitator turned that option on.
  defp hidden?(%Card{author_id: author_id}, %{retro: retro, current_user_id: user_id}) do
    retro.hide_cards_during_collect and retro.phase == :collect and author_id != user_id
  end

  defp can_add?(retro, participant?),
    do: participant? and retro.phase == :collect and not RetroSession.ended?(retro)

  defp can_edit?(card, retro, user_id),
    do: card.author_id == user_id and retro.phase == :collect and not RetroSession.ended?(retro)

  defp hidden_text(1), do: "1 card from others is hidden until Collect ends."
  defp hidden_text(n), do: "#{n} cards from others are hidden until Collect ends."

  defp error_message(:wrong_phase), do: "Cards can only be changed during Collect."
  defp error_message(:unauthorized), do: "You can only change your own cards."
  defp error_message(:ended), do: "This retro is finished."
  defp error_message(:not_found), do: "That card no longer exists."
end
