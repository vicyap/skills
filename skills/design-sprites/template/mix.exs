defmodule DecisionSprite.MixProject do
  use Mix.Project

  def project do
    [
      app: :decision_sprite,
      version: "0.2.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: [],
      deps: deps(),
      releases: [
        decision_sprite: [
          include_executables_for: [:unix],
          applications: [runtime_tools: :permanent]
        ]
      ]
    ]
  end

  def application do
    [
      mod: {DecisionSprite.Application, []},
      # :inets + :ssl power the :httpc calls in the Notifier adapters
      # (webhook + mail gateway). Without them :httpc crashes at runtime
      # with ":http_util is not available" — caught by submissions_test.
      extra_applications: [:logger, :runtime_tools, :crypto, :inets, :ssl]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.8"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_view, "~> 1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:jason, "~> 1.4"},
      {:bandit, "~> 1.0"},
      {:ash, "~> 3.0"},
      {:ash_sqlite, "~> 0.2"}
    ]
  end
end
