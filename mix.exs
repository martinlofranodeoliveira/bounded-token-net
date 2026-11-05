defmodule BoundedTokenNet.MixProject do
  use Mix.Project

  def project do
    [
      app: :bounded_token_net,
      version: "0.1.0",
      elixir: "~> 1.18",
      description: "Pure bounded token-flow models and budgeted reachability",
      source_url: "https://github.com/martinlofranodeoliveira/bounded-token-net",
      homepage_url: "https://lofranotecnologia.com.br",
      package: [
        licenses: ["MIT"],
        maintainers: ["Lofrano Tecnologia"],
        links: %{
          "GitHub" => "https://github.com/martinlofranodeoliveira/bounded-token-net",
          "Homepage" => "https://lofranotecnologia.com.br"
        }
      ],
      deps: [],
      aliases: [run: ["compile --quiet", "run --no-compile"]]
    ]
  end

  def application, do: []
end
