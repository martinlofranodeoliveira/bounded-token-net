defmodule BoundedTokenNet.Examples do
  @moduledoc "Synthetic finite models; not models of any identified person or system."

  def toggle do
    %{
      places: [%{id: "a", capacity: 1}, %{id: "b", capacity: 1}],
      transitions: [
        %{id: "go", pre: [{"a", 1}], post: [{"b", 1}]},
        %{id: "back", pre: [{"b", 1}], post: [{"a", 1}]}
      ],
      initial: [1, 0],
      terminals: []
    }
  end

  @doc "One-shot resource acquisition with no releases; not a circular-wait proof."
  def two_resources do
    %{
      places: Enum.map(["r1", "r2", "h1", "h2"], &%{id: &1, capacity: 1}),
      transitions: [
        %{id: "take2", pre: [{"r2", 1}], post: [{"h2", 1}]},
        %{id: "take1", pre: [{"r1", 1}], post: [{"h1", 1}]}
      ],
      initial: [1, 1, 0, 0],
      terminals: []
    }
  end
end
