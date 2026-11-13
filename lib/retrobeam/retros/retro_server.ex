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

  When a server starts, including a restart after a crash, it broadcasts
  `{:retro_server_started, retro_id}` on the retro's topic. Subscribers
  answer with `join/2`, so viewers that were connected to a crashed server
  are watched again and the restarted server doesn't stop as idle under
  them.

  If loading the retro raises (for example while Postgres is down), `init`
  returns `:ignore` rather than crashing. A failed restart then doesn't
  count towards the supervisor's restart limit, so one retro's trouble
  can't take the other retros' servers down with it.
  """
  use GenServer, restart: :transient

  import Ecto.Query, warn: false

  alias Retrobeam.Accounts.Scope
  alias Retrobeam.Repo
  alias Retrobeam.Retros.{Events, RetroParticipation, RetroSession}

  @registry Retrobeam.Retros.Registry
  @supervisor Retrobeam.Retros.SessionSupervisor
  @default_idle_timeout :timer.minutes(30)

  defmodule State do
    @moduledoc """
    A retro's cached state: the session with its columns, and its
    participations with their users.
    """
    @enforce_keys [:retro, :participants]
    defstruct [:retro, :participants]

    @type t :: %__MODULE__{
            retro: Retrobeam.Retros.RetroSession.t(),
            participants: [Retrobeam.Retros.RetroParticipation.t()]
          }
  end

  ## Client API

  @doc """
  Starts the server for `retro_id` unless it is already running.

  Safe to call from many processes at once: the registry makes sure only
  one server runs per retro. Returns `{:error, :not_found}` when no retro
  has that id and `{:error, :unavailable}` when its state can't be loaded.
  """
  @spec ensure_started(integer()) :: {:ok, pid()} | {:error, :not_found | :unavailable}
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

          # init/1 couldn't load the retro.
          :ignore ->
            {:error, if(retro_exists?(retro_id), do: :unavailable, else: :not_found)}

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
  @spec get_state(integer()) :: {:ok, State.t()} | {:error, :not_found | :unavailable}
  def get_state(retro_id), do: read(retro_id, :get_state)

  @doc """
  Registers `pid` (the calling LiveView by default) as connected to the
  retro and returns the state. The server monitors `pid` and forgets it
  when it exits.

  Joining reloads the participant list, so people who joined the retro by
  code after the server started are included.
  """
  @spec join(integer(), pid()) :: {:ok, State.t()} | {:error, :not_found | :unavailable}
  def join(retro_id, pid \\ self()), do: read(retro_id, {:join, pid})

  @doc """
  Moves the retro to its next phase. Only the facilitator may do this.

  Phases only move forward, one step at a time. `expected` is the phase the
  caller saw and is required, so a double click, two facilitator tabs or a
  retried call cannot skip a phase: if the retro has already moved on, the
  call returns `{:error, :stale_phase}`.

  On success the phase is written to Postgres and
  `{:phase_changed, %RetroSession{}}` is broadcast with the updated retro.
  """
  @spec advance_phase(integer(), Scope.t(), RetroSession.phase()) ::
          {:ok, RetroSession.t()}
          | {:error,
             :not_found
             | :unavailable
             | :unauthorized
             | :ended
             | :final_phase
             | :stale_phase}
  def advance_phase(retro_id, %Scope{} = scope, expected),
    do: change_call(retro_id, {:advance_phase, scope.user.id, expected})

  @doc """
  Updates the retro's options (vote limit, multiple votes, anonymous cards,
  hidden cards during Collect). Only the facilitator may do this, and only
  during Setup.

  On success broadcasts `{:retro_updated, retro}`.
  """
  @spec update_options(integer(), Scope.t(), map()) ::
          {:ok, RetroSession.t()}
          | {:error,
             Ecto.Changeset.t() | :not_found | :unavailable | :unauthorized | :ended | :locked}
  def update_options(retro_id, %Scope{} = scope, attrs),
    do: change_call(retro_id, {:update_options, scope.user.id, attrs})

  @doc """
  Finishes the retro: sets `ended_at`, after which it is read-only. Only the
  facilitator may do this, and only in the Summary phase.

  On success broadcasts `{:retro_updated, retro}`.
  """
  @spec finish(integer(), Scope.t()) ::
          {:ok, RetroSession.t()}
          | {:error, :not_found | :unavailable | :unauthorized | :ended | :not_in_summary}
  def finish(retro_id, %Scope{} = scope), do: change_call(retro_id, {:finish, scope.user.id})

  # A server can stop between the lookup and the call. Then start a fresh
  # one and try again.
  #
  # Reads may retry whatever stopped the server (a crash included), since
  # repeating them changes nothing. Changes may only retry when the server
  # stopped before handling the call: :noproc (already gone) or :normal (the
  # idle stop, which runs between messages). A :shutdown or a crash can come
  # while a change is half done, after its write committed, so retrying it
  # could apply the change twice.
  @read_retry :any
  @change_retry [:noproc, :normal]

  defp read(retro_id, message), do: call(retro_id, message, @read_retry, 2)

  @doc false
  def change_call(retro_id, message), do: call(retro_id, message, @change_retry, 2)

  defp call(retro_id, message, retry_on, retries) do
    with {:ok, pid} <- ensure_started(retro_id) do
      try do
        GenServer.call(pid, message)
      catch
        :exit, {reason, _} = exit_reason ->
          if (retry_on == :any or reason in retry_on) and retries > 0,
            do: call(retro_id, message, retry_on, retries - 1),
            else: exit(exit_reason)
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

    case safe_load(retro_id) do
      {:ok, state} ->
        server = %{
          retro_id: retro_id,
          state: state,
          viewers: %{},
          idle_timeout: idle_timeout(),
          idle_ref: nil
        }

        Events.broadcast(retro_id, {:retro_server_started, retro_id})
        {:ok, schedule_idle_stop(server)}

      # Not found, or Postgres is unreachable. :ignore (unlike {:stop, _})
      # doesn't count as a failed restart, so the supervisor stays up.
      _error ->
        :ignore
    end
  end

  @impl true
  def handle_call(:get_state, _from, server) do
    {:reply, {:ok, server.state}, server}
  end

  def handle_call({:join, pid}, _from, server) do
    server = put_in(server.state.participants, load_participants(server.retro_id))

    server =
      if Enum.any?(server.viewers, fn {_ref, viewer} -> viewer == pid end) do
        server
      else
        ref = Process.monitor(pid)
        %{server | viewers: Map.put(server.viewers, ref, pid), idle_ref: nil}
      end

    {:reply, {:ok, server.state}, server}
  end

  def handle_call({action, user_id, _} = message, _from, server)
      when action in [:advance_phase, :update_options] do
    with_facilitator(server, user_id, fn -> handle_change(message, server) end)
  end

  def handle_call({:finish, user_id} = message, _from, server) do
    with_facilitator(server, user_id, fn -> handle_change(message, server) end)
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

  ## Changes

  # Every change: authorize, write to Postgres, update the cache, broadcast.
  defp with_facilitator(%{state: %State{retro: retro}} = server, user_id, fun) do
    cond do
      retro.facilitator_id != user_id -> {:reply, {:error, :unauthorized}, server}
      RetroSession.ended?(retro) -> {:reply, {:error, :ended}, server}
      true -> fun.()
    end
  end

  defp handle_change({:advance_phase, _user_id, expected}, server) do
    retro = server.state.retro

    cond do
      expected != retro.phase ->
        {:reply, {:error, :stale_phase}, server}

      is_nil(RetroSession.next_phase(retro.phase)) ->
        {:reply, {:error, :final_phase}, server}

      true ->
        retro
        |> RetroSession.advance_phase_changeset()
        |> write(server, &Events.phase_changed/1)
    end
  end

  defp handle_change({:update_options, _user_id, attrs}, server) do
    retro = server.state.retro

    if retro.phase == :setup do
      retro
      |> RetroSession.options_changeset(attrs)
      |> write(server, &Events.retro_updated/1)
    else
      {:reply, {:error, :locked}, server}
    end
  end

  defp handle_change({:finish, _user_id}, server) do
    retro = server.state.retro

    if retro.phase == :summary do
      retro
      |> RetroSession.finish_changeset()
      |> write(server, &Events.retro_updated/1)
    else
      {:reply, {:error, :not_in_summary}, server}
    end
  end

  # Writes the change, then updates the cache and broadcasts. A failed write
  # leaves the cached state as it was and replies with the error, so the
  # server and the caller's LiveView stay up.
  defp write(changeset, server, event) do
    case safe_update(changeset) do
      {:ok, retro} -> commit(retro, server, event)
      {:error, reason} -> {:reply, {:error, reason}, server}
    end
  end

  defp safe_update(changeset) do
    Repo.update(changeset)
  rescue
    # Postgres unreachable or timed out.
    _error in [DBConnection.ConnectionError, Postgrex.Error] -> {:error, :unavailable}
  end

  defp commit(%RetroSession{} = retro, server, event) do
    server = put_in(server.state.retro, retro)
    :ok = Events.broadcast(retro.id, event.(retro))
    {:reply, {:ok, retro}, server}
  end

  ## Helpers

  defp safe_load(retro_id) do
    case Repo.get(RetroSession, retro_id) do
      nil ->
        {:error, :not_found}

      session ->
        {:ok,
         %State{
           retro: Repo.preload(session, :columns),
           participants: load_participants(retro_id)
         }}
    end
  rescue
    # Any database failure: the server can't serve this retro right now.
    error -> {:error, error}
  end

  defp load_participants(retro_id) do
    Repo.all(
      from p in RetroParticipation,
        where: p.retro_session_id == ^retro_id,
        order_by: [asc: p.joined_at, asc: p.id],
        preload: :user
    )
  end

  defp retro_exists?(retro_id) do
    Repo.exists?(from s in RetroSession, where: s.id == ^retro_id)
  rescue
    _error -> true
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
