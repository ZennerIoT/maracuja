defmodule Maracuja.MixProject do
  use Mix.Project

  def project do
    [
      app: :maracuja,
      version: "0.1.0",
      elixir: "~> 1.8",
      start_permanent: true,
      deps: deps(),
      aliases: [
        test: "test --no-start"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
    ]
  end
end
