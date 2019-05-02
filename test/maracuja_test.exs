defmodule MaracujaTest do
  use ExUnit.Case, async: false
  require Logger

  @global_name :test_process

  def start_nodes do
    hostname =
      Node.self()
      |> to_string
      |> String.split("@")
      |> Enum.at(1)

    ct_slave_opts = [kill_if_fail: true]
    {:ok, node1} = :ct_slave.start(:"node1@#{hostname}", ct_slave_opts)
    {:ok, node2} = :ct_slave.start(:"node2@#{hostname}", ct_slave_opts)

    nodes = [node1, node2]

    # part below from local_cluster library
    rpc = &({ _, [] } = :rpc.multicall(nodes, &1, &2, &3))

    :rpc.multicall(Applicaton, :put_env, [:kernel, :dist_auto_connect, :never])
    rpc.(:code, :add_paths, [ :code.get_path() ])

    rpc.(Application, :ensure_all_started, [ :mix ])
    rpc.(Application, :ensure_all_started, [ :logger ])

    rpc.(Logger, :configure, [ level: Logger.level() ])
    rpc.(Mix, :env, [ Mix.env() ])

    for { app_name, _, _ } <- Application.loaded_applications() do
      for { key, val } <- Application.get_all_env(app_name) do
        rpc.(Application, :put_env, [ app_name, key, val ])
      end
      rpc.(Application, :ensure_all_started, [ app_name ])
    end

    on_exit(fn ->
      Logger.info "Shutting down"
      Enum.each(nodes, fn node ->
        Node.connect(node)
        {:ok, ^node} = :ct_slave.stop(node)
      end)
    end)
    {:ok, nodes}
  end

  @tag timeout: :infinity
  test "cluster only has a single singleton" do
    {:ok, nodes} = start_nodes()
    [node1, node2] = nodes

    {agents, []} = :rpc.multicall(Agent, :start, [Maracuja.TestSupervisor, :start_link, []])
    IO.inspect agents
    IO.inspect(:rpc.multicall(Process, :whereis, [Maracuja.process_name(@global_name)]))

    clear_leader_records()


    # wait until all nodes have started their singleton wrapper
    Process.sleep(1200)

    # check if :global works, basically
    assert {[pid, pid, pid], []} = :rpc.multicall(:global, :whereis_name, [@global_name])

    # check if the leader has written itself into the file
    assert_leader(node(pid))

    # simulate a 1 - 1 - 1 net split (no node should be hosting)
    :rpc.call(node1, Node, :disconnect, [node2])
    :rpc.call(node2, Node, :disconnect, [node1])
    Node.disconnect(node1)
    Node.disconnect(node2)
    Process.sleep(610)

    clear_leader_records()

    assert_no_leader()

    # connect to node1 to simulate recovery and a 2 - 1 net split (this cluster should be hosting)
    Node.connect(node1)
    Process.sleep(610)

    clear_leader_records()

    leader = assert_single_leader()
    pid = :global.whereis_name(@global_name)
    assert node(pid) == leader
    assert leader in [Node.self(), node1]

    # connect to node2 to simulate full recovery
    Node.connect(node2)
    Process.sleep(610)

    clear_leader_records()

    leader = assert_single_leader()
    pid = :global.whereis_name(@global_name)
    assert node(pid) == leader

    assert {[pid, pid, pid], []} = :rpc.multicall(:global, :whereis_name, [@global_name])
    case :rpc.multicall(Maracuja, :get_state, [@global_name]) do
      {[hosting: pid, monitoring: pid, monitoring: pid], []} -> assert true
      {[monitoring: pid, hosting: pid, monitoring: pid], []} -> assert true
      {[monitoring: pid, monitoring: pid, hosting: pid], []} -> assert true
      o -> flunk(inspect(o))
    end
  end

  test "hosting wrapper handles crashes" do
    Maracuja.TestSupervisor.start_link()

    send :global.whereis_name(@global_name), :smth
    Process.sleep(610)

    assert Process.alive?(:global.whereis_name(@global_name))
  end

  def assert_leader(leader) do
    actual_leader = assert_single_leader()
    assert leader == actual_leader, "Different leader than expected: #{inspect actual_leader}"
  end

  def assert_single_leader() do
    leaders = get_current_leaders()
    assert [actual_leader] = leaders, "More than one leader: #{inspect leaders}"
    actual_leader
  end

  def assert_no_leader() do
    leaders = get_current_leaders()
    assert [] = leaders, "More than zero leaders: #{inspect leaders}"
  end

  def get_current_leaders() do
    with_lock(fn ->
      file = Maracuja.TestProcess.leader_file()
      if File.exists?(file) do
        file
        |> File.read!()
        |> String.split("\n")
        |> Enum.filter(&(&1 != ""))
        |> Enum.map(&String.trim/1)
        |> Enum.map(&String.to_atom/1)
      else
        []
      end
    end)
  end

  def clear_leader_records() do
    with_lock(fn ->
      file = Maracuja.TestProcess.leader_file()
      if File.exists? file do
        File.rm! file
      end
    end)

    # wait a bit until the timeout in testprocess hits
    Process.sleep(75)
  end

  def with_lock(fun) do
    File.touch("singleton_lock")
    result = fun.()
    File.rm!("singleton_lock")
    result
  end
end
