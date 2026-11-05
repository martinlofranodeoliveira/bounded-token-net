defmodule BoundedTokenNet.Validation do
  @moduledoc false
  alias BoundedTokenNet.{Error, Marking, Transition}

  def check(true, _code, _at), do: :ok
  def check(false, code, at), do: Error.error(code, at)

  # Stops after at most maximum + 1 cons cells, including improper lists.
  def list?([], maximum) when maximum >= 0, do: true
  def list?([_ | tail], maximum) when maximum > 0, do: list?(tail, maximum - 1)
  def list?(_, _), do: false

  def id?(id) do
    is_binary(id) and byte_size(id) in 1..64 and
      Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9_.-]*\z/, id)
  end

  def integer_vector?(values, size, minimum, maximum) do
    list?(values, 32) and length(values) == size and
      Enum.all?(values, &(is_integer(&1) and &1 >= minimum and &1 <= maximum))
  end

  defp object?(value, required, optional) do
    is_map(value) and not is_struct(value) and
      map_size(value) <= length(required) + length(optional) and
      Enum.all?(required, &Map.has_key?(value, &1)) and
      Enum.all?(Map.keys(value), &(&1 in required or &1 in optional))
  end

  defp unique?(values), do: MapSet.size(MapSet.new(values)) == length(values)

  def map_checked(items, fun) do
    items
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, acc} ->
      case fun.(item, index) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  def compile(spec) do
    with :ok <-
           check(
             object?(spec, [:places, :transitions, :initial], [:terminals]),
             :InvalidNet,
             "net"
           ),
         :ok <- check(list?(spec.places, 32) and spec.places != [], :InvalidNet, "places"),
         {:ok, pairs} <- map_checked(spec.places, &place/2),
         ids = Enum.map(pairs, &elem(&1, 0)),
         capacities = Enum.map(pairs, &elem(&1, 1)),
         :ok <- check(unique?(ids), :InvalidNet, "places.ids"),
         {:ok, initial} <- tokens(spec.initial, ids, capacities),
         {:ok, terminals} <- terminals(Map.get(spec, :terminals, []), ids, capacities),
         :ok <- check(list?(spec.transitions, 64), :InvalidNet, "transitions"),
         {:ok, transitions} <-
           map_checked(spec.transitions, fn item, index ->
             compile_transition(item, index, ids, capacities)
           end),
         :ok <- check(unique?(Enum.map(transitions, & &1.id)), :InvalidNet, "transitions.ids") do
      {:ok,
       %{
         places: ids,
         capacities: capacities,
         initial: initial,
         terminals: MapSet.new(terminals),
         transitions: Enum.sort_by(transitions, & &1.id)
       }}
    end
  end

  defp place(value, index) do
    at = "places[#{index}]"

    with :ok <- check(object?(value, [:id, :capacity], []), :InvalidNet, at),
         :ok <- check(id?(value.id), :InvalidNet, at <> ".id"),
         :ok <-
           check(
             is_integer(value.capacity) and value.capacity in 0..255,
             :InvalidNet,
             at <> ".capacity"
           ) do
      {:ok, {value.id, value.capacity}}
    end
  end

  defp terminals(values, ids, capacities) do
    with :ok <- check(list?(values, 256), :InvalidNet, "terminals"),
         {:ok, keys} <-
           map_checked(values, fn value, _index ->
             with {:ok, marking} <- tokens(value, ids, capacities) do
               {:ok, List.to_tuple(marking.tokens)}
             end
           end),
         :ok <- check(unique?(keys), :InvalidNet, "terminals.duplicates") do
      {:ok, keys}
    end
  end

  defp compile_transition(value, index, ids, capacities) do
    at = "transitions[#{index}]"

    with :ok <- check(object?(value, [:id, :pre, :post], []), :InvalidNet, at),
         :ok <- check(id?(value.id), :InvalidNet, at <> ".id"),
         {:ok, pre} <- arcs(value.pre, ids, at <> ".pre"),
         {:ok, post} <- arcs(value.post, ids, at <> ".post") do
      {:ok,
       %Transition{
         id: value.id,
         places: ids,
         capacities: capacities,
         pre: pre,
         post: post
       }}
    end
  end

  defp arcs(values, ids, at) do
    with :ok <- check(list?(values, 32), :InvalidNet, at),
         {:ok, pairs} <-
           map_checked(values, fn
             {id, weight}, _index ->
               with :ok <- check(id?(id) and id in ids, :InvalidNet, at),
                    :ok <- check(is_integer(weight) and weight in 1..255, :InvalidNet, at) do
                 {:ok, {id, weight}}
               end

             _, _index ->
               Error.error(:InvalidNet, at)
           end),
         :ok <- check(unique?(Enum.map(pairs, &elem(&1, 0))), :InvalidNet, at <> ".duplicates") do
      weights = Map.new(pairs)
      {:ok, Enum.map(ids, &Map.get(weights, &1, 0))}
    end
  end

  defp schema(ids, capacities, code) do
    with :ok <- check(list?(ids, 32) and ids != [], code, "places"),
         :ok <- check(Enum.all?(ids, &id?/1) and unique?(ids), code, "places"),
         :ok <- check(integer_vector?(capacities, length(ids), 0, 255), code, "capacities") do
      :ok
    end
  end

  def tokens(values, ids, capacities) do
    valid = integer_vector?(values, length(ids), 0, 255)

    with :ok <- check(valid, :InvalidMarking, "marking.tokens"),
         :ok <- check(within_capacities?(values, capacities), :InvalidMarking, "marking.tokens") do
      {:ok, %Marking{places: ids, capacities: capacities, tokens: values}}
    end
  end

  defp within_capacities?([], []), do: true

  defp within_capacities?([value | values], [capacity | capacities]) do
    value <= capacity and within_capacities?(values, capacities)
  end

  def marking(%Marking{} = marking) do
    with :ok <- schema(marking.places, marking.capacities, :InvalidMarking),
         {:ok, _} <- tokens(marking.tokens, marking.places, marking.capacities) do
      :ok
    end
  end

  def marking(_), do: Error.error(:InvalidMarking, "marking")

  def transition(%Transition{} = transition) do
    with :ok <- check(id?(transition.id), :InvalidTransition, "transition.id"),
         :ok <- schema(transition.places, transition.capacities, :InvalidTransition),
         :ok <-
           check(
             integer_vector?(transition.pre, length(transition.places), 0, 255),
             :InvalidTransition,
             "transition.pre"
           ),
         :ok <-
           check(
             integer_vector?(transition.post, length(transition.places), 0, 255),
             :InvalidTransition,
             "transition.post"
           ) do
      :ok
    end
  end

  def transition(_), do: Error.error(:InvalidTransition, "transition")

  def bind(%Marking{} = marking, compiled) do
    with :ok <- marking(marking),
         :ok <-
           check(
             marking.places == compiled.places and marking.capacities == compiled.capacities,
             :SchemaMismatch,
             "marking"
           ) do
      {:ok, marking}
    end
  end

  def bind(values, compiled), do: tokens(values, compiled.places, compiled.capacities)

  def limits(value) do
    with :ok <- check(object?(value, [], [:max_states, :max_firings]), :InvalidLimits, "limits"),
         states = Map.get(value, :max_states, 10_000),
         firings = Map.get(value, :max_firings, 100_000),
         :ok <-
           check(is_integer(states) and states in 1..10_000, :InvalidLimits, "limits.max_states"),
         :ok <-
           check(
             is_integer(firings) and firings in 0..100_000,
             :InvalidLimits,
             "limits.max_firings"
           ) do
      {:ok, %{max_states: states, max_firings: firings}}
    end
  end
end
