defmodule Singleton do
  def start(_, _) do
    Supervisor.start_link([], [name: Singleton.Application, strategy: :one_for_one])
  end
end
