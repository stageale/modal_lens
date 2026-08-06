defmodule AxiomRefiner.MixProject do
  use Mix.Project

  def project do
    [
      app: :modal_lens,
      version: "0.3.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: [main_module: Src.Interface.CLI],
      aliases: aliases()
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
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:hpc_connect, github: "penthooose/hpc_connect"},
      {:jason, "~> 1.4"}
    ]
  end

  defp aliases do
    [
      "test.all": ["cmd ./cmd/test_all.sh"]
    ]
  end
end
