defmodule BoundedTokenNet.Search do
  @moduledoc false
  alias BoundedTokenNet.{Error, Marking, Step, Validation}

  def run(net, initial, limits) do
    key = List.to_tuple(initial.tokens)
    row = row(initial.tokens, nil, nil, net)

    state = %{
      net: net,
      limits: limits,
      initial: key,
      queue: :queue.in(key, :queue.new()),
      states: %{key => row},
      order_rev: [key],
      deadlocks_rev: [],
      count: 1,
      terminal_count: if(row.terminal, do: 1, else: 0),
      examined: 0,
      edges: 0
    }

    loop(state)
  end

  defp row(tokens, parent, via, net) do
    %{
      marking: tokens,
      parent: parent,
      via: via,
      terminal: MapSet.member?(net.terminals, List.to_tuple(tokens)),
      enabled: nil,
      deadlock: nil
    }
  end

  defp loop(state) do
    case :queue.out(state.queue) do
      {:empty, _} ->
        report(state, nil)

      {{:value, key}, queue} ->
        current = Map.fetch!(state.states, key)
        state = %{state | queue: queue}

        case scan(state.net.transitions, key, current, state, []) do
          {:done, next} -> loop(next)
          {:stop, next, reason} -> report(next, reason)
        end
    end
  end

  defp scan([], key, current, state, enabled_rev) do
    enabled = Enum.reverse(enabled_rev)
    deadlock = enabled == [] and not current.terminal
    current = %{current | enabled: enabled, deadlock: deadlock}

    {:done,
     %{
       state
       | states: Map.put(state.states, key, current),
         deadlocks_rev: if(deadlock, do: [key | state.deadlocks_rev], else: state.deadlocks_rev)
     }}
  end

  defp scan([transition | rest], key, current, state, enabled_rev) do
    if state.examined == state.limits.max_firings do
      {:stop, state, :firing_limit}
    else
      state = %{state | examined: state.examined + 1}

      marking = %Marking{
        places: state.net.places,
        capacities: state.net.capacities,
        tokens: current.marking
      }

      case Step.apply_vectors(marking, transition.pre, transition.post) do
        {:error, _} ->
          scan(rest, key, current, state, enabled_rev)

        {:ok, next_marking} ->
          state = %{state | edges: state.edges + 1}

          case admit(state, next_marking.tokens, key, transition.id) do
            {:ok, next} -> scan(rest, key, current, next, [transition.id | enabled_rev])
            {:stop, next} -> {:stop, next, :state_limit}
          end
      end
    end
  end

  defp admit(state, tokens, parent, via) do
    key = List.to_tuple(tokens)

    cond do
      Map.has_key?(state.states, key) ->
        {:ok, state}

      state.count == state.limits.max_states ->
        {:stop, state}

      true ->
        current = row(tokens, parent, via, state.net)

        {:ok,
         %{
           state
           | states: Map.put(state.states, key, current),
             queue: :queue.in(key, state.queue),
             order_rev: [key | state.order_rev],
             count: state.count + 1,
             terminal_count: state.terminal_count + if(current.terminal, do: 1, else: 0)
         }}
    end
  end

  defp report(state, reason) do
    deadlocks = Enum.reverse(state.deadlocks_rev)

    %{
      complete: is_nil(reason),
      reason: reason,
      initial: state.initial,
      limits: state.limits,
      states: state.states,
      order: Enum.reverse(state.order_rev),
      state_count: state.count,
      terminal_count: state.terminal_count,
      unexpected_deadlock_count: length(deadlocks),
      deadlocks: deadlocks,
      examined_firings: state.examined,
      edge_count: state.edges
    }
  end

  def witness(report, key) do
    with true <- is_map(report) and not is_struct(report),
         %{states: states, initial: initial} <- report,
         true <- is_map(states) and not is_struct(states) and map_size(states) in 1..10_000,
         true <- is_tuple(initial) and tuple_size(initial) in 1..32,
         {:ok, %{parent: nil, via: nil} = root} when not is_struct(root) <-
           Map.fetch(states, initial) do
      if Map.has_key?(states, key) do
        trace(states, key, initial, [], map_size(states))
      else
        Error.error(:UnknownMarking, "key")
      end
    else
      _ -> Error.error(:InvalidReport, "report")
    end
  end

  defp trace(_states, _key, _initial, _acc, 0), do: Error.error(:InvalidReport, "parents")

  defp trace(states, key, initial, acc, remaining) do
    case Map.fetch(states, key) do
      {:ok, %{parent: nil, via: nil} = row} when not is_struct(row) and key == initial ->
        {:ok, acc}

      {:ok, %{parent: parent, via: via} = row}
      when not is_struct(row) and key != initial and is_tuple(parent) ->
        if Validation.id?(via) do
          trace(states, parent, initial, [via | acc], remaining - 1)
        else
          Error.error(:InvalidReport, "parents")
        end

      _ ->
        Error.error(:InvalidReport, "parents")
    end
  end
end
