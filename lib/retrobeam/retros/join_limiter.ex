defmodule Retrobeam.Retros.JoinLimiter do
  @moduledoc """
  Limits failed join-code attempts, per user and per IP address.

  Join codes are short, so without a limit a script could guess its way into
  retros. Each failed attempt counts against the user and, when known, their
  IP address, in a fixed window. Once either count reaches its limit, further
  attempts are refused until the window ends. Successful joins don't count.

  Counts live in an ETS table owned by this process, so they reset when the
  node restarts. That's fine for a single-node app; a cluster would need a
  shared store.

  Limits are read from config:

      config :retrobeam, Retrobeam.Retros.JoinLimiter,
        window_ms: :timer.minutes(10),
        user_limit: 10,
        ip_limit: 50

  `check/2` also takes `:user_limit` and `:ip_limit` overrides, so tests can
  use a small limit without changing config that other tests share.
  """
  use GenServer

  @table __MODULE__
  @defaults [window_ms: :timer.minutes(10), user_limit: 10, ip_limit: 50]

  @type key :: {:user, term()} | {:ip, term()}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Returns `:ok` when every key is under its limit, or `{:error, :rate_limited}`.
  """
  @spec check([key()], keyword()) :: :ok | {:error, :rate_limited}
  def check(keys, limits \\ []) do
    window = current_window()

    if Enum.any?(keys, &(count(&1, window) >= limit(&1, limits))),
      do: {:error, :rate_limited},
      else: :ok
  end

  @doc """
  Records one failed attempt against each key.
  """
  @spec record_failure([key()]) :: :ok
  def record_failure(keys) do
    window = current_window()

    for key <- keys do
      :ets.update_counter(@table, {key, window}, 1, {{key, window}, 0})
    end

    :ok
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    schedule_prune()
    {:ok, nil}
  end

  @impl true
  def handle_info(:prune, state) do
    window = current_window()
    :ets.select_delete(@table, [{{{:_, :"$1"}, :_}, [{:<, :"$1", window}], [true]}])
    schedule_prune()
    {:noreply, state}
  end

  defp count(key, window) do
    case :ets.lookup(@table, {key, window}) do
      [{_, count}] -> count
      [] -> 0
    end
  end

  defp limit({:user, _}, limits),
    do: Keyword.get_lazy(limits, :user_limit, fn -> config(:user_limit) end)

  defp limit({:ip, _}, limits),
    do: Keyword.get_lazy(limits, :ip_limit, fn -> config(:ip_limit) end)

  defp current_window, do: div(System.monotonic_time(:millisecond), config(:window_ms))

  defp schedule_prune, do: Process.send_after(self(), :prune, config(:window_ms))

  defp config(key) do
    :retrobeam
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key, @defaults[key])
  end
end
