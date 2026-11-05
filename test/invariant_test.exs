defmodule BoundedTokenNet.InvariantTest do
  use ExUnit.Case, async: true
  alias BoundedTokenNet, as: BTN
  alias BoundedTokenNet.Error

  test "toggle conservation and canonical exact violation" do
    net = BTN.Examples.toggle()
    assert {:ok, %{conserved_value: 1}} = BTN.verify_invariant(net, [1, 1])
    # back sorts before go and violates [1,0] too. A go-first ID ordering is
    # supplied explicitly below; the checker must not pretend go sorts first.
    assert {:error, %Error{code: :InvariantViolation, details: %{transition: "back", delta: 1}}} =
             BTN.verify_invariant(net, [1, 0])

    go_first = %{
      net
      | transitions:
          Enum.map(net.transitions, fn
            %{id: "back"} = t -> %{t | id: "return"}
            t -> t
          end)
    }

    assert {:error,
            %Error{code: :InvariantViolation, at: "go", details: %{transition: "go", delta: -1}}} =
             BTN.verify_invariant(go_first, [1, 0])
  end

  test "negative and zero weights, unreachable transitions and integer exactness" do
    net = %{
      places: Enum.map(1..32, &%{id: "p#{&1}", capacity: 255}),
      initial: List.duplicate(0, 32),
      transitions: [%{id: "unreachable", pre: Enum.map(1..32, &{"p#{&1}", 255}), post: []}]
    }

    assert {:ok, %{conserved_value: 0}} = BTN.verify_invariant(net, List.duplicate(0, 32))

    assert {:error, %Error{details: %{delta: -8_160_000_000}}} =
             BTN.verify_invariant(net, List.duplicate(1_000_000, 32))

    assert {:error, %Error{details: %{delta: 8_160_000_000}}} =
             BTN.verify_invariant(net, List.duplicate(-1_000_000, 32))

    assert {:ok, %{conserved_value: -1}} = BTN.verify_invariant(BTN.Examples.toggle(), [-1, -1])
  end

  test "no floats, booleans, truncated vectors or oversized weights" do
    net = BTN.Examples.toggle()

    for weights <- [
          [],
          [1],
          [1, 1, 1],
          [1.0, 1],
          [true, 1],
          [1_000_001, 0],
          [-1_000_001, 0],
          [1 | :bad]
        ] do
      assert {:error, %Error{code: :InvalidInvariant}} = BTN.verify_invariant(net, weights)
    end
  end
end
