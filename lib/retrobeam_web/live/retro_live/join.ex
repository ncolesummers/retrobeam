defmodule RetrobeamWeb.RetroLive.Join do
  use RetrobeamWeb, :live_view

  alias Retrobeam.Retros

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Join a retro
        <:subtitle>Enter the 6-character code your facilitator shared.</:subtitle>
      </.header>

      <.form for={@form} id="join-form" phx-change="change" phx-submit="join" class="space-y-4">
        <div class="fieldset">
          <label for="join_code" class="label mb-1">Join code</label>
          <input
            type="text"
            id="join_code"
            name={@form[:code].name}
            value={@form[:code].value}
            maxlength="12"
            autocomplete="off"
            autocapitalize="characters"
            spellcheck="false"
            aria-invalid={@error && "true"}
            aria-describedby={@error && "join-code-error"}
            class={[
              "input w-full max-w-xs font-mono text-xl uppercase tracking-[0.2em]",
              @error && "input-error"
            ]}
          />
          <p
            :if={@error}
            id="join-code-error"
            class="mt-1.5 flex items-center gap-2 text-sm text-error"
          >
            <.icon name="hero-exclamation-circle" class="size-5" />
            {@error}
          </p>
        </div>
        <.button variant="primary" phx-disable-with="Joining...">Join retro</.button>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Join a retro")
     |> assign(:client_ip, client_ip(socket))
     |> assign(:error, nil)
     |> assign(:form, to_form(%{"code" => params["code"] || ""}, as: :join))}
  end

  @impl true
  def handle_event("change", %{"join" => params}, socket) do
    {:noreply, socket |> assign(:error, nil) |> assign(:form, to_form(params, as: :join))}
  end

  def handle_event("join", %{"join" => %{"code" => code} = params}, socket) do
    %{current_scope: scope, client_ip: ip} = socket.assigns

    case Retros.join_retro(scope, code, ip: ip) do
      {:ok, retro} ->
        {:noreply, push_navigate(socket, to: ~p"/retros/#{retro}")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:error, error_message(reason))
         |> assign(:form, to_form(params, as: :join))}
    end
  end

  # Ignore malformed events instead of crashing the page.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp error_message(:not_found), do: "No retro has that code. Check it and try again."

  defp error_message(:rate_limited),
    do: "Too many attempts. Wait a few minutes and try again."

  # On Fly.io the proxy puts the client's address in Fly-Client-IP and
  # overwrites any value the client sends. Elsewhere, use the socket's peer.
  defp client_ip(socket) do
    if connected?(socket) do
      fly_ip =
        Enum.find_value(get_connect_info(socket, :x_headers) || [], fn
          {"fly-client-ip", ip} -> ip
          _ -> nil
        end)

      fly_ip || peer_ip(get_connect_info(socket, :peer_data))
    end
  end

  defp peer_ip(%{address: address}), do: address |> :inet.ntoa() |> to_string()
  defp peer_ip(_), do: nil
end
