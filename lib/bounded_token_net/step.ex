defmodule BoundedTokenNet.Step do
  @moduledoc false
  alias BoundedTokenNet.{Error, Validation}

  def enabled(marking, transition) do
    case fire_batch(marking, [transition]) do
      {:ok, _} ->
        {:ok, true}

      {:error, %Error{code: code}} when code in [:InsufficientTokens, :CapacityExceeded] ->
        {:ok, false}

      error ->
        error
    end
  end

  def fire_batch(marking, occurrences) do
    with :ok <- Validation.marking(marking),
         :ok <-
           Validation.check(Validation.list?(occurrences, 256), :InvalidBatch, "occurrences"),
         {:ok, _} <-
           Validation.map_checked(occurrences, fn transition, _index ->
             with :ok <- Validation.transition(transition),
                  :ok <-
                    Validation.check(
                      transition.places == marking.places and
                        transition.capacities == marking.capacities,
                      :SchemaMismatch,
                      "occurrences"
                    ) do
               {:ok, transition}
             end
           end) do
      if occurrences == [] do
        {:ok, marking}
      else
        zero = Enum.map(marking.tokens, fn _ -> 0 end)

        {pre, post} =
          Enum.reduce(occurrences, {zero, zero}, fn transition, {pre, post} ->
            {add(pre, transition.pre), add(post, transition.post)}
          end)

        apply_vectors(marking, pre, post)
      end
    end
  end

  defp add([], []), do: []
  defp add([a | as], [b | bs]), do: [a + b | add(as, bs)]

  # Internal fast path: the caller has already validated equal-length schemas.
  # No output is constructed until every original input requirement passes.
  def apply_vectors(marking, pre, post) do
    case insufficient(marking.tokens, pre, 0) do
      nil ->
        result = produce(marking.tokens, pre, post)

        case excess(result, marking.capacities, 0) do
          nil ->
            {:ok, %{marking | tokens: result}}

          {index, value, capacity} ->
            Error.error(:CapacityExceeded, "tokens[#{index}]", %{
              place: Enum.at(marking.places, index),
              result: value,
              capacity: capacity
            })
        end

      {index, required, available} ->
        Error.error(:InsufficientTokens, "tokens[#{index}]", %{
          place: Enum.at(marking.places, index),
          required: required,
          available: available
        })
    end
  end

  defp insufficient([], [], _index), do: nil

  defp insufficient([available | tokens], [required | pre], index) do
    if available < required,
      do: {index, required, available},
      else: insufficient(tokens, pre, index + 1)
  end

  defp produce([], [], []), do: []

  defp produce([token | tokens], [input | pre], [output | post]) do
    [token - input + output | produce(tokens, pre, post)]
  end

  defp excess([], [], _index), do: nil

  defp excess([value | values], [capacity | capacities], index) do
    if value > capacity,
      do: {index, value, capacity},
      else: excess(values, capacities, index + 1)
  end
end
