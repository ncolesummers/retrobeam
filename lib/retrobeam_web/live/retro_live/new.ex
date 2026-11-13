defmodule RetrobeamWeb.RetroLive.New do
  use RetrobeamWeb, :live_view

  alias Retrobeam.Retros
  alias Retrobeam.Retros.{RetroSession, Template}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        New retro
        <:subtitle>Pick a format. You can share the join code once it's created.</:subtitle>
      </.header>

      <.form for={@form} id="retro-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <.input field={@form[:title]} label="Title" placeholder="Sprint 42 retro" maxlength="100" />

        <fieldset class="space-y-3">
          <legend class="label mb-2">Template</legend>
          <label
            :for={template <- @templates}
            for={"retro_template_#{template.key}"}
            class="flex cursor-pointer gap-3 rounded-box border border-base-300 bg-base-200 p-4 has-checked:border-primary has-focus-visible:outline-2 has-focus-visible:outline-primary"
          >
            <input
              type="radio"
              id={"retro_template_#{template.key}"}
              name={@form[:template].name}
              value={template.key}
              checked={selected?(@form, template.key)}
              class="radio radio-primary mt-1"
            />
            <span class="min-w-0">
              <span class="block font-semibold">{template.name}</span>
              <span class="block text-sm leading-6 text-base-content/70">
                {template.description}
              </span>
              <span :if={template.columns != []} class="mt-2 flex flex-wrap gap-1.5">
                <span :for={column <- template.columns} class="badge badge-ghost">
                  {column.name}
                </span>
              </span>
            </span>
          </label>
        </fieldset>

        <fieldset :if={selected?(@form, :custom)} id="custom-columns" class="space-y-2">
          <legend class="label mb-2">
            Columns ({Template.min_custom_columns()} to {Template.max_custom_columns()})
          </legend>
          <div :for={{name, index} <- Enum.with_index(@custom_columns)} class="flex gap-2">
            <label for={"retro_custom_columns_#{index}"} class="sr-only">
              Column {index + 1} name
            </label>
            <input
              type="text"
              id={"retro_custom_columns_#{index}"}
              name={@form[:custom_columns].name <> "[]"}
              value={name}
              maxlength={Template.max_column_name_length()}
              placeholder={"Column #{index + 1}"}
              class={["input w-full", @custom_errors != [] && "input-error"]}
            />
            <button
              :if={length(@custom_columns) > Template.min_custom_columns()}
              type="button"
              phx-click="remove_column"
              phx-value-index={index}
              class="btn btn-ghost btn-square"
              aria-label={"Remove column #{index + 1}"}
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>
          <p :for={msg <- @custom_errors} class="flex items-center gap-2 text-sm text-error">
            <.icon name="hero-exclamation-circle" class="size-5" />
            {msg}
          </p>
          <button
            :if={length(@custom_columns) < Template.max_custom_columns()}
            type="button"
            id="add-column"
            phx-click="add_column"
            class="btn btn-primary btn-soft btn-sm"
          >
            <.icon name="hero-plus" class="size-4" /> Add column
          </button>
        </fieldset>

        <div class="flex items-center gap-3">
          <.button variant="primary" phx-disable-with="Creating...">Create retro</.button>
          <.link navigate={~p"/retros"} class="btn btn-ghost">Cancel</.link>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    params = %{"template" => "start_stop_continue", "custom_columns" => ["", "", ""]}

    {:ok,
     socket
     |> assign(:page_title, "New retro")
     |> assign(:templates, Template.all() ++ [Template.custom()])
     |> assign(:custom_touched, false)
     |> assign_form(params)}
  end

  @impl true
  def handle_event("validate", %{"retro" => params}, socket) do
    params = keep_custom_columns(params, socket.assigns.params)
    touched = socket.assigns.custom_touched or Enum.any?(params["custom_columns"], &(&1 != ""))

    {:noreply,
     socket
     |> assign(:custom_touched, touched)
     |> assign_form(params, :validate)}
  end

  def handle_event("add_column", _params, socket) do
    params = socket.assigns.params
    columns = params["custom_columns"]

    columns =
      if length(columns) < Template.max_custom_columns(), do: columns ++ [""], else: columns

    {:noreply, assign_form(socket, Map.put(params, "custom_columns", columns))}
  end

  def handle_event("remove_column", %{"index" => index}, socket) do
    params = socket.assigns.params
    columns = params["custom_columns"]

    with {index, ""} when index >= 0 <- Integer.parse(to_string(index)),
         true <- length(columns) > Template.min_custom_columns() do
      columns = List.delete_at(columns, index)
      {:noreply, assign_form(socket, Map.put(params, "custom_columns", columns))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("save", %{"retro" => params}, socket) do
    params = keep_custom_columns(params, socket.assigns.params)

    case Retros.create_retro(socket.assigns.current_scope, params) do
      {:ok, retro} ->
        {:noreply,
         socket
         |> put_flash(:info, "Retro created. Share the join code with your team.")
         |> push_navigate(to: ~p"/retros/#{retro}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:custom_touched, true)
         |> assign(:params, params)
         |> assign(:custom_columns, params["custom_columns"])
         |> assign_changeset(changeset)}
    end
  end

  # The column inputs are only rendered for the Custom template, so keep the
  # names typed so far when another template is selected.
  defp keep_custom_columns(params, previous) do
    case params do
      %{"custom_columns" => columns} when is_list(columns) -> params
      _ -> Map.put(params, "custom_columns", previous["custom_columns"])
    end
  end

  defp assign_form(socket, params, action \\ nil) do
    changeset =
      socket.assigns.current_scope
      |> Retros.change_retro(%RetroSession{}, params)
      |> Map.put(:action, action)

    socket
    |> assign(:params, params)
    |> assign(:custom_columns, params["custom_columns"])
    |> assign_changeset(changeset)
  end

  defp assign_changeset(socket, changeset) do
    custom_errors =
      if socket.assigns.custom_touched do
        for {:custom_columns, {msg, _opts}} <- changeset.errors, do: msg
      else
        []
      end

    socket
    |> assign(:custom_errors, custom_errors)
    |> assign(:form, to_form(changeset, as: :retro))
  end

  defp selected?(form, key) do
    to_string(form[:template].value) == to_string(key)
  end
end
