defmodule Maracuja.TestProcess do
  use GenServer

  @spec start_link() :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link do
    Maracuja.start_link(__MODULE__, :ok, :test_process)
  end

  @spec init(:ok) :: {:ok, nil}
  def init(:ok) do
    :timer.send_interval(50, :ensure_name)
    {:ok, nil}
  end

  def terminate(_, _) do
    :ok
  end

  def handle_info(:ensure_name, state) do
    if not File.exists?("singleton_lock") do
      File.touch!(leader_file())
      lines = File.read!(leader_file()) |> String.split("\n")
      local = node_slug()
      if not Enum.any?(lines, &(&1 == local)) do
        IO.puts "Writing #{local}"
        File.write!(leader_file(), "#{local}\n", [:append])
      end
    end
    {:noreply, state}
  end

  @spec node_slug(node) :: binary
  def node_slug(node \\ Node.self()) do
    node
    |> to_string()
  end

  def leader_file do
    "leaders.txt"
  end
end
