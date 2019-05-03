defmodule Maracuja do
  @behaviour :gen_statem
  require Logger

  @type args :: term
  @type name :: atom

  @doc """
  Called when the wrapper wants the server to be started. The name argument
  already uses the :global registry, simply pass this to the underlying server
  module's opts argument.

  Example if using a GenServer:
  ```
  def start_server(args, name) do
    GenServer.start_link(__MODULE__, args, [name: name])
  end
  ```
  """
  @callback start_server(args, name :: {:global, name}) :: {:ok, pid}
    | {:error, {:already_started, pid}}
    | {:error, any}

  defmodule Data do
    @moduledoc false
    defstruct pid: nil, mod: nil, args: nil, name: nil, maxnodes: 1, monitor: nil, leader_node: nil
  end

  @doc """
  Starts the Maracuja singleton wrapper. It will decide whether to start the actual instance using the
  global name registry.

  Whenever the wrapper wants to start the singleton, it will call the
  `start_server/2` callback.
  """
  @spec start_link(module, args, name) :: {:ok, pid} | {:error, any} | :ignore
  def start_link(module, args, global_name) do
    :gen_statem.start_link({:local, process_name(global_name)}, __MODULE__, {module, args, global_name}, [])
  end

  @doc false
  def init({mod, args, name}) do
    # monitor node joins and leaves
    :net_kernel.monitor_nodes(true)
    Process.flag(:trap_exit, true)

    data = %Data{mod: mod,
      args: args,
      name: name,
      maxnodes: count_nodes()
    }

    {:next_state, state, data} = restart(data)
    {:ok, state, data}
  end

  @doc false
  def process_name(global_name) do
    :"#{global_name}_wrapper"
  end

  @doc false
  def get_state(global_name) do
    :gen_statem.call(process_name(global_name), :get_state)
  end

  @doc false
  def callback_mode() do
    [:handle_event_function, :state_enter]
  end

  @doc false
  def handle_event(:enter, old_state, state, data) do
    Logger.debug("[#{Node.self()}] global wrapper for #{data.name} changed state: #{old_state} -> #{state}")
    {:keep_state, data}
  end

  def handle_event(:info, {:EXIT, _, :normal}, :monitoring, data) do
    # global registry killed our process because 2 clusters with the same singletons were joined
    {:keep_state, data}
  end

  def handle_event(:info, {:EXIT, pid, _reason}, :hosting, %{pid: pid} = data) do
    restart(data)
  end

  def handle_event(:info, {:DOWN, _, :process, pid, _reason}, :monitoring, %{pid: pid} = data) do
    restart(data)
  end

  def handle_event(:info, {:nodedown, node}, :monitoring, %{leader_node: node} = data) do
    # node that lead the cluster went down, we check if we can safely start an instance
    Logger.debug("[#{Node.self()}] nodedown in state monitoring, #{count_nodes()} / #{data.maxnodes}")
    maybe_start(data)
  end

  def handle_event(:info, {:nodedown, _}, state, data) when state in [:hosting, :monitoring] do
    Logger.debug("[#{Node.self()}] nodedown in state #{state}, #{count_nodes()} / #{data.maxnodes}")
    maybe_stop(state, data)
  end

  def handle_event(:info, {:nodeup, _}, :net_split, data) do
    data = update_maxnodes(data)
    Logger.debug("[#{Node.self()}] nodeup in state net_split, #{count_nodes()} / #{data.maxnodes}")
    maybe_start(data)
  end

  def handle_event(:info, {:nodeup, _}, state, data) do
    data = update_maxnodes(data)
    Logger.debug("[#{Node.self()}] nodeup in state #{state}, #{count_nodes()} / #{data.maxnodes}")
    {:keep_state, data}
  end

  def handle_event(:info, other, state, data) do
    Logger.warn "[#{Node.self()}] Unhandled info: #{inspect other} in state #{state}"
    {:keep_state, data}
  end

  def handle_event({:call, from}, :get_state, state, data) do
    {:keep_state_and_data, [{:reply, from, {state, data.pid}}]}
  end

  # EVENT HANDLERS

  @doc """
  This event handler reacts to DOWN or EXIT messages.

  It tries to start the singleton with global name registration.

  In case the name is already registered, the server changes to the state :monitoring

  Otherwise, the server links to the pid and changes state to :hosting
  """
  def restart(data) do
    # sleep for a random amount of time to prevent duplicate starts
    300..600
    |> Enum.random()
    |> Process.sleep()

    name = {:global, data.name}
    start_result = data.mod.start_server(data.args, name)
    case start_result do
      {:ok, pid} ->
        Process.link(pid)
        {:next_state, :hosting, %{data | pid: pid, leader_node: Node.self()}}
      {:error, {:already_started, pid}} ->
        ref = Process.monitor(pid)
        {:next_state, :monitoring, %{data | pid: pid, monitor: ref, leader_node: node(pid)}}
    end
  end

  @doc """
  handle_stop reacts to :nodedown infos in the states :monitoring and :hosting

  It will decide if the current amount of connected nodes implies a net split.

  If a net split was detected, it will stop the process (if it was hosting one),
  and change to state :net_split
  """
  def maybe_stop(state, data) do
    if not has_majority?(data) do
      Logger.info("Net split detected in cluster of #{Node.self()}, giving up leadership")
      if state == :hosting do
        Process.unlink(data.pid)
        Process.exit(data.pid, :net_split)
      else
        Process.demonitor(data.monitor)
      end
      {:next_state, :net_split, data}
    else
      {:keep_state, data}
    end
  end

  @doc """
  handle_start reacts to nodeup infos when in state :net_split, as well as
  to nodedown infos when in state :monitoring and the disconnected node was the old leader_node

  When it has verified that the net split is over or at least a majority of the nodes are in the current
  cluster, it will call restart, which will lead to states :monitoring or :hosting
  """
  def maybe_start(data) do
    if not has_majority?(data) do
      {:keep_state, data}
    else
      Logger.info("Restarting in cluster of #{Node.self()}, net split seems to be over")
      restart(data)
    end
  end

  # UTILS

  @doc false
  def has_majority?(data) do
    count_nodes() > data.maxnodes / 2
  end

  @doc false
  def count_nodes() do
    length(Node.list()) + 1
  end

  @doc false
  def update_maxnodes(data) do
    new_count = max(data.maxnodes, count_nodes())
    %{data | maxnodes: new_count}
  end
end
