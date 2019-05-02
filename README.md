# Maracuja

A microlibrary that helps you spawn a process that lives at most once per cluster.

It can cope with netsplits by checking if the count of the currently connected nodes 
would have an _absolute_ majority in the historically biggest known cluster size.

## How it handles net splits

With an exemplary amount of 5 nodes in a healthy cluster, imagine the following 
split scenarios:

`5`: No split - one of the nodes will host the singleton

`4 - 1`: The cluster with 4 nodes will host the singleton

`3 - 2`: The cluster with 3 nodes will host the singleton

`1 - 2 - 2`: None of the clusters will host the singleton because none of 
them have an absolute majority

`1 - 2 - 1 - 1`: Even though the cluster with 2 nodes would have the majority, 
it doesn't know that it's the cluster with the most nodes, so it doesn't 
host the singleton

`1 - 1 - 1 - 1 - 1`: None of these nodes will host the singleton either

As you can see, it is possible that in some net split situations, it is possible
that no singleton is hosted. As such, this library is not for you if you often
experience net splits and don't recover quickly from them.

## Usage

In the `start_link` callback of your GenServer, instead of directly using the `GenServer` module to start the server, use `Maracuja.start_link/3`:

```elixir
def MySingleton do
  use GenServer

  def start_link(args) do
    Maracuja.start_link(__MODULE__, args, :my_global_name)
  end

  # init and rest of the server
end
```

Maracuja uses `:global` to register the name, so you can find the pid of a singleton by passing its name to 
`:global.whereis_name`:

```elixir
iex> :global.whereis_name(:my_global_name)
#Pid<0.170.0>
```

In the case the cluster is experiencing a net split and the current node is part of a faction that's too small, `whereis_name` will return `:undefined`!

## Planned features

 - [ ] Support for other behaviours 
 - [ ] Maybe support for other coping strategies

## Installation

The package can be installed by adding `maracuja` 
to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:maracuja, "~> 0.1.0"}
  ]
end
```

Documentation can be found at [https://hexdocs.pm/maracuja](https://hexdocs.pm/maracuja).