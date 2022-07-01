defmodule Maracuja.Agent do
  def start_link(fun, name) do
    Maracuja.start_link(__MODULE__, fun, name)
  end

  def start_server(fun, name) do
    Agent.start_link(fun, name: name)
  end
end
