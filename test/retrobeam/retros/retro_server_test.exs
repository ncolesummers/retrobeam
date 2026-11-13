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
  defp spawn_viewer(retro_id, scope) do
    test = self()

    pid =
      spawn(fn ->
        # Like a LiveView under test, share the test's database sandbox.
        Process.put(:"$callers", [test])
        {:ok, state} = RetroServer.join(retro_id, scope)
        send(test, {:joined, self(), state})

        receive do
          :leave -> :ok
        end
      end)

    assert_receive {:joined, ^pid, state}
    {pid, state}
  end

  test "starts on demand and registers by retro id", %{retro: retro} do
    assert RetroServer.whereis(retro.id) == nil
    assert {:ok, pid} = RetroServer.ensure_started(retro.id)
    assert RetroServer.whereis(retro.id) == pid
    assert {:ok, ^pid} = RetroServer.ensure_started(retro.id)
  end

  test "concurrent ensure_started calls share one server", %{retro: retro} do
    pids =
      1..25
      |> Task.async_stream(fn _ -> RetroServer.ensure_started(retro.id) end, max_concurrency: 25)
      |> Enum.map(fn {:ok, {:ok, pid}} -> pid end)
      |> Enum.uniq()

    assert [pid] = pids
    assert RetroServer.whereis(retro.id) == pid
  end

  test "returns not found for an unknown retro" do
    assert {:error, :not_found} = RetroServer.ensure_started(-1)
    assert {:error, :not_found} = RetroServer.get_state(-1)
    assert {:error, :not_found} = RetroServer.join(-1, user_scope_fixture())
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

  test "join/3 monitors the viewer and returns the state", %{scope: scope, retro: retro} do
    {viewer, state} = spawn_viewer(retro.id, scope)

    assert %RetroServer.State{retro: %RetroSession{id: id}} = state
    assert id == retro.id

    server = RetroServer.whereis(retro.id)
    ref = Process.monitor(server)
    assert map_size(:sys.get_state(server).viewers) == 1

    # Joining again from the same process does not add a second viewer.
    {:ok, _} = RetroServer.join(retro.id, scope, viewer)
    assert map_size(:sys.get_state(server).viewers) == 1

    send(viewer, :leave)
    assert await_exit(ref, server) == :normal
  end

  test "stays up while a viewer is connected", %{scope: scope, retro: retro} do
    {viewer, _state} = spawn_viewer(retro.id, scope)
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

  test "join/3 loads participants who joined after the server started", %{retro: retro} do
    {:ok, _pid} = RetroServer.ensure_started(retro.id)
    late = user_scope_fixture()
    {:ok, _} = Retrobeam.Retros.join_retro(late, retro.join_code)

    {:ok, state} = RetroServer.get_state(retro.id)
    refute Enum.any?(state.participants, &(&1.user_id == late.user.id))

    {:ok, state} = RetroServer.join(retro.id, late)
    assert Enum.any?(state.participants, &(&1.user_id == late.user.id))

    # Joining again does not add the participant twice.
    {:ok, state} = RetroServer.join(retro.id, late)
    assert Enum.count(state.participants, &(&1.user_id == late.user.id)) == 1
  end

  test "stale idle timers are ignored", %{retro: retro} do
    {:ok, server} = RetroServer.ensure_started(retro.id)
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
