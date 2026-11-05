defmodule BoundedTokenNet.ValidationTest do
  use ExUnit.Case, async: true
  alias BoundedTokenNet, as: BTN
  alias BoundedTokenNet.Error

  defp invalid(result), do: assert(match?({:error, %Error{}}, result))

  test "bounded IDs, unique namespaces, exact objects, capacities and proper lists" do
    net = BTN.Examples.toggle()
    assert :ok == BTN.validate(net)

    for bad <- [
          nil,
          [],
          true,
          %{net | places: []},
          Map.put(net, :unknown, 1),
          %{net | places: [%{id: "a", capacity: 1}, %{id: "a", capacity: 2}]},
          %{net | places: [%{id: "a", capacity: -1}]},
          %{net | places: [%{id: "a", capacity: 256}]},
          %{net | places: [%{id: "a", capacity: 1.0}]},
          %{net | places: [%{id: "a", capacity: true}]},
          %{net | transitions: [hd(net.transitions), hd(net.transitions)]},
          %{net | places: [hd(net.places) | :improper]},
          %{net | transitions: [hd(net.transitions) | :improper]}
        ] do
      invalid(BTN.validate(bad))
    end

    for id <- ["", " a", "a\n", "á", "a/b", String.duplicate("x", 65), :a, 7, <<255>>] do
      bad = %{places: [%{id: id, capacity: 0}], transitions: [], initial: [0]}
      invalid(BTN.validate(bad))
    end

    assert :ok ==
             BTN.validate(%{
               places: [%{id: String.duplicate("x", 64), capacity: 255}],
               transitions: [],
               initial: [255]
             })
  end

  test "duplicate arcs rejected within each side; same place on both sides allowed" do
    net = %{places: [%{id: "p", capacity: 1}], initial: [1], transitions: []}
    loop = %{id: "p", pre: [{"p", 1}], post: [{"p", 1}]}
    assert :ok == BTN.validate(%{net | transitions: [loop]})

    for transition <- [
          %{loop | pre: [{"p", 1}, {"p", 1}]},
          %{loop | post: [{"p", 1}, {"p", 1}]},
          %{loop | pre: [{"missing", 1}]},
          %{loop | pre: [{"p", 0}]},
          %{loop | pre: [{"p", 256}]},
          %{loop | pre: [{"p", 1.0}]},
          %{loop | pre: [{"p", true}]},
          %{loop | pre: [["p", 1]]},
          %{loop | pre: [{"p", 1} | :bad]}
        ] do
      invalid(BTN.validate(%{net | transitions: [transition]}))
    end
  end

  test "marking arity and terminal states are fully validated" do
    net = BTN.Examples.toggle()

    for tokens <- [[], [1], [1, 0, 0], [2, 0], [-1, 0], [1.0, 0], [true, 0], [1 | :bad]] do
      invalid(BTN.validate(%{net | initial: tokens}))
      invalid(BTN.marking(net, tokens))
      invalid(BTN.explore(net, tokens))
      invalid(BTN.validate(%{net | terminals: [tokens]}))
    end

    invalid(BTN.validate(%{net | terminals: [[1, 0], [1, 0]]}))
    invalid(BTN.validate(%{net | terminals: List.duplicate([1, 0], 257)}))
    invalid(BTN.validate(%{net | terminals: [[1, 0] | :bad]}))
    assert :ok == BTN.validate(%{net | terminals: [[1, 0], [0, 1]]})
  end

  test "hard structural bounds and integer limits cannot be bypassed" do
    net = BTN.Examples.toggle()
    invalid(BTN.validate(%{net | places: List.duplicate(hd(net.places), 33)}))
    invalid(BTN.validate(%{net | transitions: List.duplicate(hd(net.transitions), 65)}))
    invalid(BTN.validate(%{net | initial: List.duplicate(0, 100_000)}))

    for limits <- [
          nil,
          [],
          %{maxStates: 1},
          %{extra: 0},
          %{max_states: 0},
          %{max_states: 10_001},
          %{max_states: 1.0},
          %{max_states: true},
          %{max_firings: -1},
          %{max_firings: 100_001},
          %{max_firings: false}
        ] do
      assert {:error, %Error{code: :InvalidLimits}} = BTN.explore(net, net.initial, limits)
    end

    assert {:error, %Error{code: :UnknownTransition}} = BTN.transition(net, "missing")
    invalid(BTN.transition(net, :go))
  end

  test "schema-bound values are revalidated, including forged structs" do
    net = BTN.Examples.toggle()
    {:ok, m} = BTN.marking(net, [1, 0])
    {:ok, t} = BTN.transition(net, "go")
    invalid(BTN.fire(%{m | tokens: [1]}, t))
    invalid(BTN.fire(m, %{t | pre: [0]}))
    invalid(BTN.fire(m, %{t | post: [0, 256]}))
    invalid(BTN.fire(m, %{t | places: ["a", "a"]}))
    invalid(BTN.fire(%{m | capacities: [1 | :bad]}, t))
    invalid(BTN.fire(m, %{t | pre: [true, 0]}))
    assert {:error, %Error{code: :SchemaMismatch}} = BTN.fire(m, %{t | places: ["x", "y"]})
    assert {:error, %Error{code: :SchemaMismatch}} = BTN.explore(net, %{m | places: ["x", "y"]})
  end
end
