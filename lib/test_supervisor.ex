defmodule Maracuja.TestSupervisor do
  use Supervisor

  def start_link() do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    children = [
      worker(Maracuja.TestProcess, [])
    ]

    opts = [strategy: :one_for_one]
    Supervisor.init(children, opts)
  end
end
