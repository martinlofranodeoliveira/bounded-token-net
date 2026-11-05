defmodule BoundedTokenNet do
  @moduledoc """
  Pure, bounded place/transition token models. Development version 0.1.0.

  Nets are explicit maps; markings and transitions are schema-bound values.
  All public operations return tagged results, except `validate/1`, which
  returns `:ok` on success. See docs/contract.md for the exact input language,
  limits, error codes, search accounting and incomplete-result semantics.
  """

  alias BoundedTokenNet.{Error, Invariants, Search, Step, Validation}

  @spec validate(term()) :: :ok | {:error, Error.t()}
  def validate(net) do
    case Validation.compile(net) do
      {:ok, _compiled} -> :ok
      error -> error
    end
  end

  @doc "Binds a token vector to the validated net's ordered places and capacities."
  def marking(net, tokens) do
    with {:ok, compiled} <- Validation.compile(net) do
      Validation.bind(tokens, compiled)
    end
  end

  @doc "Obtains a validated, schema-bound transition by its binary ID."
  def transition(net, id) do
    with {:ok, compiled} <- Validation.compile(net),
         :ok <- Validation.check(Validation.id?(id), :InvalidTransition, "id") do
      case Enum.find(compiled.transitions, &(&1.id == id)) do
        nil -> Error.error(:UnknownTransition, "id")
        transition -> {:ok, transition}
      end
    end
  end

  @doc "Returns {:ok, boolean}; malformed values are errors, not disabled transitions."
  def enabled(marking, transition), do: Step.enabled(marking, transition)

  @doc "Fires one occurrence atomically, or returns an error without a new marking."
  def fire(marking, transition), do: Step.fire_batch(marking, [transition])

  @doc "Fires at most 256 occurrences against the original marking."
  def fire_batch(marking, occurrences), do: Step.fire_batch(marking, occurrences)

  @doc "Contract spelling of fire_batch/2."
  def fireBatch(marking, occurrences), do: fire_batch(marking, occurrences)

  @doc "Deterministic FIFO reachability; limits use :max_states and :max_firings."
  def explore(net, initial, limits \\ %{}) do
    with {:ok, compiled} <- Validation.compile(net),
         {:ok, marking} <- Validation.bind(initial, compiled),
         {:ok, checked_limits} <- Validation.limits(limits) do
      {:ok, Search.run(compiled, marking, checked_limits)}
    end
  end

  @doc "Reconstructs a shortest canonical witness from a report and a tuple key."
  def witness(report, key), do: Search.witness(report, key)

  @doc "Checks integer incidence conservation; value refers to the declared initial marking."
  def verify_invariant(net, weights), do: Invariants.verify(net, weights)
end
