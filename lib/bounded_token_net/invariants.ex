defmodule BoundedTokenNet.Invariants do
  @moduledoc false
  alias BoundedTokenNet.{Error, Validation}

  def verify(net, weights) do
    with {:ok, compiled} <- Validation.compile(net),
         :ok <-
           Validation.check(
             Validation.integer_vector?(weights, length(compiled.places), -1_000_000, 1_000_000),
             :InvalidInvariant,
             "weights"
           ) do
      violation =
        Enum.find_value(compiled.transitions, fn transition ->
          delta = incidence(weights, transition.pre, transition.post)
          if delta != 0, do: {transition.id, delta}
        end)

      case violation do
        nil ->
          {:ok, %{conserved_value: dot(weights, compiled.initial.tokens)}}

        {id, delta} ->
          Error.error(:InvariantViolation, id, %{transition: id, delta: delta})
      end
    end
  end

  defp incidence([], [], []), do: 0

  defp incidence([weight | weights], [pre | pres], [post | posts]) do
    weight * (post - pre) + incidence(weights, pres, posts)
  end

  defp dot([], []), do: 0
  defp dot([weight | weights], [token | tokens]), do: weight * token + dot(weights, tokens)
end
