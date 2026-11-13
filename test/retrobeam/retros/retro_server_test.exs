defmodule Retrobeam.Retros.RetroServerTest do
  use Retrobeam.DataCase, async: true

  import Retrobeam.AccountsFixtures
  import Retrobeam.RetrosFixtures

  alias Retrobeam.Retros.{Events, RetroServer, RetroSession}

  setup do
    scope = user_scope_fixture()
    %{scope: scope, retro: retro_fixture(scope, %{"title" => "Server retro"})}
  end

  # Waits for a monitored process to exit and returns its exit reason.
  defp await_exit(ref, pid, timeout \\ 1_000) do
    assert_receive {:DOWN, ^ref, :process, ^pid, reason}, timeout
    reason
  end

  # A stand-in for a connected LiveView.
  defp spawn_viewer(retro_id) do
    test = self()

    pid =
      spawn(fn ->
        # Like a LiveView under test, share the test's database sandbox.
        Process.put(:"$callers", [test])
        {:ok, state} = RetroServer.join(retro_id)
        send(test, {:joined, self(), state})

        receive do
          :leave -> :ok
        end
      end)

    assert_receive {:joined, ^pid, state}, 1_000
    {pid, state}
  end

  # Tests that need a server to stay put keep a viewer joined: with none,
  # the 100 ms test idle timer could stop it between steps on a slow runner.

  test "starts on demand and registers by retro id", %{retro: retro} do
    assert RetroServer.whereis(retro.id) == nil
    {_viewer, _state} = spawn_viewer(retro.id)
    pid = RetroServer.whereis(retro.id)
    assert is_pid(pid)
    assert {:ok, ^pid} = RetroServer.ensure_started(retro.id)
  end

  test "concurrent ensure_started calls share one server", %{retro: retro} do
    {_viewer, _state} = spawn_viewer(retro.id)

    pids =
      1..25
      |> Task.async_stream(fn _ -> RetroServer.ensure_started(retro.id) end, max_concurrency: 25)
      |> Enum.map(fn {:ok, {:ok, pid}} -> pid end)
      |> Enum.uniq()

    assert [pid] = pids
    assert RetroServer.whereis(retro.id) == pid
  end

  test "broadcasts when it starts, so viewers can join again after a crash", %{retro: retro} do
    :ok = Events.subscribe(retro.id)
    {:ok, pid} = RetroServer.ensure_started(retro.id)
    retro_id = retro.id
    assert_receive {:retro_server_started, ^retro_id}

    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert await_exit(ref, pid) == :killed

    # The supervisor restarts it, and the restart announces itself too.
    assert_receive {:retro_server_started, ^retro_id}
  end

  test "join/2 picks up people who joined by code after the server started", %{
    retro: retro
  } do
    {viewer, state} = spawn_viewer(retro.id)
    assert length(state.participants) == 1

    joiner = user_fixture()

    {:ok, _} =
      Retrobeam.Retros.join_retro(Retrobeam.Accounts.Scope.for_user(joiner), retro.join_code)

    {:ok, state} = RetroServer.join(retro.id, viewer)
    assert Enum.map(state.participants, & &1.user_id) |> Enum.member?(joiner.id)
  end

  test "returns not found for an unknown retro" do
    assert {:error, :not_found} = RetroServer.ensure_started(-1)
    assert {:error, :not_found} = RetroServer.get_state(-1)
    assert {:error, :not_found} = RetroServer.join(-1)
    assert RetroServer.whereis(-1) == nil
  end

  test "loads the retro, columns and participants from Postgres", %{scope: scope, retro: retro} do
    joiner = user_fixture()
    participation_fixture(retro, joiner)

    assert {:ok, %RetroServer.State{} = state} = RetroServer.get_state(retro.id)
    assert state.retro.title == "Server retro"
    assert Enum.map(state.retro.columns, & &1.name) == ["Start", "Stop", "Continue"]

    assert Enum.map(state.participants, &{&1.user_id, &1.role}) == [
             {scope.user.id, :facilitator},
             {joiner.id, :participant}
           ]

    assert Enum.all?(state.participants, &match?(%Retrobeam.Accounts.User{}, &1.user))
  end

  test "rebuilds its state from Postgres after a crash", %{retro: retro} do
    {:ok, pid} = RetroServer.ensure_started(retro.id)

    retro |> Ecto.Changeset.change(title: "Renamed") |> Repo.update!()
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert await_exit(ref, pid) == :killed

    assert {:ok, state} = RetroServer.get_state(retro.id)
    assert state.retro.title == "Renamed"
    refute RetroServer.whereis(retro.id) == pid
  end

  test "join/2 monitors the viewer and returns the state", %{retro: retro} do
    {viewer, state} = spawn_viewer(retro.id)

    assert %RetroServer.State{retro: %RetroSession{id: id}} = state
    assert id == retro.id

    server = RetroServer.whereis(retro.id)
    ref = Process.monitor(server)
    assert map_size(:sys.get_state(server).viewers) == 1

    # Joining again from the same process does not add a second viewer.
    {:ok, _} = RetroServer.join(retro.id, viewer)
    assert map_size(:sys.get_state(server).viewers) == 1

    send(viewer, :leave)
    assert await_exit(ref, server) == :normal
  end

  test "stays up while a viewer is connected", %{retro: retro} do
    {viewer, _state} = spawn_viewer(retro.id)
    server = RetroServer.whereis(retro.id)
    ref = Process.monitor(server)

    # Longer than the test idle timeout (100 ms).
    Process.sleep(250)
    assert Process.alive?(server)

    send(viewer, :leave)
    assert await_exit(ref, server) == :normal
  end

  test "stops when idle and a later visit starts a fresh server", %{retro: retro} do
    {:ok, first} = RetroServer.ensure_started(retro.id)
    ref = Process.monitor(first)
    assert await_exit(ref, first) == :normal

    assert {:ok, state} = RetroServer.get_state(retro.id)
    assert state.retro.id == retro.id
    refute RetroServer.whereis(retro.id) == first
  end

  test "stale idle timers are ignored", %{retro: retro} do
    {_viewer, _state} = spawn_viewer(retro.id)
    server = RetroServer.whereis(retro.id)
    send(server, {:idle_stop, make_ref()})
    assert {:ok, _state} = RetroServer.get_state(retro.id)
    assert RetroServer.whereis(retro.id) == server
  end

  describe "Events" do
    test "topics and broadcast", %{retro: retro} do
      assert Events.topic(retro.id) == "retro:#{retro.id}"
      assert Events.presence_topic(retro.id) == "retro:#{retro.id}:presence"
      assert Events.facilitator_topic(retro.id) == "retro:#{retro.id}:facilitator"

      :ok = Events.subscribe(retro.id)
      :ok = Events.broadcast(retro.id, {:ping, 1})
      assert_receive {:ping, 1}
    end
  end
end
