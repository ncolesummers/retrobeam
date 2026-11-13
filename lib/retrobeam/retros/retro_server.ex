defmodule Retrobeam.Retros.RetroServer do
  @moduledoc """
  One process per active retro.

  The server serializes every change to its retro, so all participants see
  the same events in the same order. Each change follows the same path:

    1. authorize the caller and check the phase
    2. write the change to Postgres
    3. update the cached state
    4. broadcast a `Retrobeam.Retros.Events` event on the retro's topic

  Postgres always holds the full retro, so a process that crashes or stops
  rebuilds its state with one query when it is next needed.

  Servers are registered in `Retrobeam.Retros.Registry` by retro id and
  started on demand under `Retrobeam.Retros.SessionSupervisor`. A server
  monitors the LiveViews that `join/2` it and stops itself after
  `:idle_timeout` milliseconds (30 minutes by default) with none connected.
  """
  use GenServer, restart: :transient

  import Ecto.Query, warn: false

  alias Retrobeam.Accounts.Scope
  alias Retrobeam.Repo
  alias Retrobeam.Retros.{Card, Changes, Events, RetroParticipation, RetroSession}

  @registry Retrobeam.Retros.Registry
  @supervisor Retrobeam.Retros.SessionSupervisor
  @default_idle_timeout :timer.minutes(30)

  defmodule State do
    @moduledoc """
    A retro's cached state: the session with its columns, its participations
    with their users, and its cards (by id) with their authors.
    """
    @enforce_keys [:retro, :participants]
    defstruct [:retro, :participants, cards: %{}]

    @type t :: %__MODULE__{
            retro: Retrobeam.Retros.RetroSession.t(),
            participants: [Retrobeam.Retros.RetroParticipation.t()],
            cards: %{integer() => Retrobeam.Retros.Card.t()}
          }
  end

  ## Client API

  @doc """
  Starts the server for `retro_id` unless it is already running.

  Safe to call from many processes at once: the registry makes sure only
  one server runs per retro. Returns `{:error, :not_found}` when no retro
  has that id.
  """
  @spec ensure_started(integer()) :: {:ok, pid()} | {:error, :not_found}
  def ensure_started(retro_id), do: ensure_started(retro_id, 3)

  defp ensure_started(retro_id, attempts) do
    case whereis(retro_id) do
      pid when is_pid(pid) ->
        {:ok, pid}

      nil ->
        # Carry the caller chain so the server can use the caller's database
        # sandbox in tests, the same way Task does.
        callers = [self() | Process.get(:"$callers", [])]

        case DynamicSupervisor.start_child(@supervisor, {__MODULE__, {retro_id, callers}}) do
          {:ok, pid} ->
            {:ok, pid}

          # Another process started it first.
          {:error, {:already_started, pid}} ->
            if Process.alive?(pid) or attempts == 0,
              do: {:ok, pid},
              else: ensure_started(retro_id, attempts - 1)

          {:error, :not_found} ->
            {:error, :not_found}

          {:error, reason} ->
            exit({reason, {__MODULE__, :ensure_started, [retro_id]}})
        end
    end
  end

  @doc """
  Returns the pid of the retro's running server, or nil.

  A server that has just stopped can stay in the registry for a moment, so
  only live pids are returned.
  """
  @spec whereis(integer()) :: pid() | nil
  def whereis(retro_id) do
    case Registry.lookup(@registry, retro_id) do
      [{pid, _value}] -> if Process.alive?(pid), do: pid
      [] -> nil
    end
  end

  @doc "Returns the retro's cached state, starting the server if needed."
  @spec get_state(integer()) :: {:ok, State.t()} | {:error, :not_found}
  def get_state(retro_id), do: call(retro_id, :get_state)

  @doc """
  Registers `pid` (the calling LiveView by default) as connected to the
  retro for the scope's user and returns the state. The server monitors
  `pid` and forgets it when it exits.

  If the user joined the retro after the server started, their
  participation is loaded so they can make changes.
  """
  @spec join(integer(), Scope.t(), pid()) :: {:ok, State.t()} | {:error, :not_found}
  def join(retro_id, %Scope{} = scope, pid \\ self()),
    do: call(retro_id, {:join, scope.user.id, pid})

  @doc """
  Moves the retro to its next phase. Only the facilitator may do this.

  Phases only move forward, one step at a time. Pass the phase the caller
  saw as `expected` so a double click or two facilitator tabs cannot skip a
  phase: if the retro has already moved on, the call returns
  `{:error, :stale_phase}`.

  On success the phase is written to Postgres and `{:phase_changed, phase}`
  is broadcast.
  """
  @spec advance_phase(integer(), Scope.t(), RetroSession.phase() | nil) ::
          {:ok, RetroSession.t()}
          | {:error, :not_found | :unauthorized | :ended | :final_phase | :stale_phase}
  def advance_phase(retro_id, %Scope{} = scope, expected \\ nil),
    do: change(retro_id, Changes.Phases, :advance, [scope.user.id, expected])

  @doc """
  Updates the retro's options (vote limit, multiple votes, anonymous cards,
  hidden cards during Collect). Only the facilitator may do this, and only
  during Setup.

  On success broadcasts `{:retro_updated, retro}`.
  """
  @spec update_options(integer(), Scope.t(), map()) ::
          {:ok, RetroSession.t()}
          | {:error, Ecto.Changeset.t() | :not_found | :unauthorized | :ended | :locked}
  def update_options(retro_id, %Scope{} = scope, attrs),
    do: change(retro_id, Changes.Phases, :update_options, [scope.user.id, attrs])

  @doc """
  Finishes the retro: sets `ended_at`, after which it is read-only. Only the
  facilitator may do this, and only in the Summary phase.

  On success broadcasts `{:retro_updated, retro}`.
  """
  @spec finish(integer(), Scope.t()) ::
          {:ok, RetroSession.t()}
          | {:error, :not_found | :unauthorized | :ended | :not_in_summary}
  def finish(retro_id, %Scope{} = scope),
    do: change(retro_id, Changes.Phases, :finish, [scope.user.id])

  @doc """
  Adds a card during Collect. `attrs` holds `"column_id"` and `"body"`.
  Any participant may add cards. Broadcasts `{:card_created, card}`.
  """
  @spec add_card(integer(), Scope.t(), map()) ::
          {:ok, Card.t()} | {:error, Ecto.Changeset.t() | atom()}
  def add_card(retro_id, %Scope{} = scope, attrs),
    do: change(retro_id, Changes.Cards, :add, [scope.user.id, attrs])

  @doc """
  Edits the caller's own card during Collect. Broadcasts
  `{:card_updated, card}`.
  """
  @spec update_card(integer(), Scope.t(), integer() | String.t(), map()) ::
          {:ok, Card.t()} | {:error, Ecto.Changeset.t() | atom()}
  def update_card(retro_id, %Scope{} = scope, card_id, attrs),
    do: change(retro_id, Changes.Cards, :update, [scope.user.id, card_id, attrs])

  @doc """
  Deletes the caller's own card during Collect. Broadcasts
  `{:card_deleted, card}`.
  """
  @spec delete_card(integer(), Scope.t(), integer() | String.t()) ::
          {:ok, Card.t()} | {:error, atom()}
  def delete_card(retro_id, %Scope{} = scope, card_id),
    do: change(retro_id, Changes.Cards, :delete, [scope.user.id, card_id])

  defp change(retro_id, module, fun, args), do: call(retro_id, {:change, module, fun, args})

  # A server can stop (idle timeout) between the lookup and the call. In
  # that case start a fresh one and try once more.
  defp call(retro_id, message, retries \\ 2) do
    with {:ok, pid} <- ensure_started(retro_id) do
      try do
        GenServer.call(pid, message)
      catch
        :exit, {reason, _} when reason in [:noproc, :normal, :shutdown] and retries > 0 ->
          call(retro_id, message, retries - 1)
      end
    end
  end

  @doc false
  def start_link({retro_id, callers}) do
    GenServer.start_link(__MODULE__, {retro_id, callers}, name: via(retro_id))
  end

  defp via(retro_id), do: {:via, Registry, {@registry, retro_id}}

  ## Server callbacks

  @impl true
  def init({retro_id, callers}) do
    Process.put(:"$callers", callers)

    case load(retro_id) do
      nil ->
        {:stop, :not_found}

      state ->
        server = %{
          retro_id: retro_id,
          state: state,
          viewers: %{},
          idle_timeout: idle_timeout(),
          idle_ref: nil
        }

        {:ok, schedule_idle_stop(server)}
    end
  end

  @impl true
  def handle_call(:get_state, _from, server) do
    {:reply, {:ok, server.state}, server}
  end

  def handle_call({:join, user_id, pid}, _from, server) do
    server = ensure_participant(server, user_id)

    server =
      if Enum.any?(server.viewers, fn {_ref, viewer} -> viewer == pid end) do
        server
      else
        ref = Process.monitor(pid)
        %{server | viewers: Map.put(server.viewers, ref, pid), idle_ref: nil}
      end

    {:reply, {:ok, server.state}, server}
  end

  # Every change: authorize, write to Postgres, update the cache, broadcast.
  def handle_call({:change, module, fun, args}, _from, server) do
    case apply(module, fun, [server.state | args]) do
      {:ok, reply, state, events} ->
        Enum.each(events, &(:ok = Events.broadcast(server.retro_id, &1)))
        {:reply, {:ok, reply}, %{server | state: state}}

      {:error, reason} ->
        {:reply, {:error, reason}, server}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, server) do
    server = %{server | viewers: Map.delete(server.viewers, ref)}
    {:noreply, schedule_idle_stop(server)}
  end

  def handle_info({:idle_stop, ref}, %{idle_ref: ref, viewers: viewers} = server)
      when map_size(viewers) == 0 do
    {:stop, :normal, server}
  end

  # A stale timer: someone joined after it was set.
  def handle_info({:idle_stop, _ref}, server), do: {:noreply, server}

  ## Helpers

  defp load(retro_id) do
    case Repo.get(RetroSession, retro_id) do
      nil ->
        nil

      session ->
        participants =
          Repo.all(
            from p in RetroParticipation,
              where: p.retro_session_id == ^retro_id,
              order_by: [asc: p.joined_at, asc: p.id],
              preload: :user
          )

        cards =
          Repo.all(
            from c in Card,
              where: c.retro_session_id == ^retro_id,
              order_by: [asc: c.position, asc: c.id],
              preload: :author
          )

        %State{
          retro: Repo.preload(session, :columns),
          participants: participants,
          cards: Map.new(cards, &{&1.id, &1})
        }
    end
  end

  # Someone who joined after the server started is not in the cached
  # participants yet.
  defp ensure_participant(server, user_id) do
    if Changes.participant?(server.state, user_id) do
      server
    else
      case Repo.one(
             from p in RetroParticipation,
               where: p.retro_session_id == ^server.retro_id and p.user_id == ^user_id,
               preload: :user
           ) do
        nil -> server
        participation -> update_in(server.state.participants, &(&1 ++ [participation]))
      end
    end
  end

  defp schedule_idle_stop(%{viewers: viewers} = server) when map_size(viewers) > 0, do: server

  defp schedule_idle_stop(server) do
    ref = make_ref()
    Process.send_after(self(), {:idle_stop, ref}, server.idle_timeout)
    %{server | idle_ref: ref}
  end

  defp idle_timeout do
    :retrobeam
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:idle_timeout, @default_idle_timeout)
  end
end
