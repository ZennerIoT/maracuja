defmodule Maracuja.MixProject do
  use Mix.Project

  def project do
    [
      app: :maracuja,
      version: "0.2.0",
      elixir: "~> 1.8",
      start_permanent: true,
      deps: deps(),
      aliases: [
        test: "test --no-start"
      ],
      package: package()
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
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end

  def package() do
    [
      description: "Spawns singletons that live at most once per cluster",
      licenses: ["MIT"],
      maintainers: ["Moritz Schmale"],
      links: %{github: "https://github.com/ZennerIoT/maracuja"}
    ]
  end
end
