defmodule ExMustache.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_mustache,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:bbmustache, "~> 1.4.0", only: [:dev, :test]},
      {:yaml_elixir, "~> 1.0", only: [:test]},
      {:benchee, "~> 1.0", only: :dev},
      {:poison, "~> 3.0.0", only: :dev},
      {:temp, "~> 0.4", only: :test}
    ]
  end
end
