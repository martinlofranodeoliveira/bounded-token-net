defmodule BoundedTokenNet.TestSupport.DirectSimulator do
  @moduledoc false
  # Independent test oracle: reads sparse raw arcs, indexes the original vector,
  # and enumerates bounded path layers. It never calls the production validator,
  # enabled predicate, firing logic, batch logic, or search implementation.

  def step(net, tokens, id) do
    transition = Enum.find(net.transitions, &(&1.id == id))
    index = net.places |> Enum.with_index() |> Map.new(fn {p, i} -> {p.id, i} end)

    enough =
      Enum.all?(transition.pre, fn {place, count} ->
        Enum.at(tokens, Map.fetch!(index, place)) >= count
      end)

    if enough do
      next =
        net.places
        |> Enum.with_index()
        |> Enum.map(fn {place, i} ->
          input = weight(transition.pre, place.id)
          output = weight(transition.post, place.id)
          Enum.at(tokens, i) - input + output
        end)

      fits =
        Enum.all?(Enum.with_index(net.places), fn {place, i} ->
          Enum.at(next, i) >= 0 and Enum.at(next, i) <= place.capacity
        end)

      if fits, do: {:ok, next}, else: :disabled
    else
      :disabled
    end
  end

  defp weight(arcs, id) do
    Enum.find_value(arcs, 0, fn {place, weight} -> if place == id, do: weight end)
  end

  def enabled(net, tokens) do
    net.transitions
    |> Enum.map(& &1.id)
    |> Enum.sort()
    |> Enum.filter(fn id -> match?({:ok, _}, step(net, tokens, id)) end)
  end

  def replay(net, initial, path) do
    Enum.reduce_while(path, {:ok, initial}, fn id, {:ok, tokens} ->
      case step(net, tokens, id) do
        {:ok, next} -> {:cont, {:ok, next}}
        :disabled -> {:halt, :disabled}
      end
    end)
  end

  def paths(net) do
    universe = Enum.reduce(net.places, 1, fn p, size -> size * (p.capacity + 1) end)
    if universe > 9, do: raise(ArgumentError, "oracle restricted to tiny fixtures")
    layers(net, [{net.initial, []}], %{}, 0, universe - 1)
  end

  # Every shortest path in a finite graph is simple, so universe - 1 suffices.
  # Full path enumeration, rather than the production visited-queue algorithm,
  # supplies an independently structured shortest/lexicographic oracle.
  defp layers(net, frontier, found, depth, maximum) do
    found =
      Enum.reduce(frontier, found, fn {tokens, path}, acc ->
        Map.put_new(acc, List.to_tuple(tokens), %{
          tokens: tokens,
          path: path,
          enabled: enabled(net, tokens),
          terminal: tokens in Map.get(net, :terminals, [])
        })
      end)

    if depth == maximum or frontier == [] do
      found
    else
      next =
        Enum.flat_map(frontier, fn {tokens, path} ->
          Enum.map(enabled(net, tokens), fn id ->
            {:ok, result} = step(net, tokens, id)
            {result, path ++ [id]}
          end)
        end)

      layers(net, next, found, depth + 1, maximum)
    end
  end
end
