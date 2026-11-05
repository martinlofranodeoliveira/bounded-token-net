defmodule BoundedTokenNet.FiringTest do
  use ExUnit.Case, async: true
  alias BoundedTokenNet, as: BTN
  alias BoundedTokenNet.Error

  defp loop_fixture do
    net = %{
      places: [%{id: "p", capacity: 1}],
      initial: [1],
      transitions: [%{id: "loop", pre: [{"p", 1}], post: [{"p", 1}]}]
    }

    {:ok, m} = BTN.marking(net, net.initial)
    {:ok, t} = BTN.transition(net, "loop")
    {m, t}
  end

  test "sequential feedback succeeds; feedback cannot finance a batch" do
    {m, t} = loop_fixture()
    original = :erlang.term_to_binary(m)
    assert {:ok, true} == BTN.enabled(m, t)
    assert {:ok, once} = BTN.fire(m, t)
    assert {:ok, ^m} = BTN.fire(once, t)

    assert {:error, %Error{code: :InsufficientTokens, details: %{required: 2, available: 1}}} =
             BTN.fireBatch(m, [t, t])

    assert :erlang.term_to_binary(m) == original
    assert {:ok, ^m} = BTN.fire_batch(m, [])
  end

  test "capacity is checked after consumption and every failure leaves input identical" do
    net = %{
      places: [%{id: "p", capacity: 2}],
      initial: [2],
      transitions: [
        %{id: "grow", pre: [{"p", 1}], post: [{"p", 2}]},
        %{id: "swap", pre: [{"p", 2}], post: [{"p", 2}]}
      ]
    }

    {:ok, m} = BTN.marking(net, net.initial)
    {:ok, grow} = BTN.transition(net, "grow")
    {:ok, swap} = BTN.transition(net, "swap")
    before = :erlang.term_to_binary(m)

    assert {:error, %Error{code: :CapacityExceeded, details: %{result: 3, capacity: 2}}} =
             BTN.fire(m, grow)

    assert {:ok, false} = BTN.enabled(m, grow)
    assert {:ok, ^m} = BTN.fire(m, swap)
    assert before == :erlang.term_to_binary(m)
  end

  test "batch output cannot enable a different occurrence, regardless of order" do
    net = BTN.Examples.toggle()
    {:ok, m} = BTN.marking(net, net.initial)
    {:ok, go} = BTN.transition(net, "go")
    {:ok, back} = BTN.transition(net, "back")
    {:ok, next} = BTN.fire(m, go)
    assert {:ok, ^m} = BTN.fire(next, back)

    for batch <- [[go, back], [back, go]] do
      assert {:error, %Error{code: :InsufficientTokens}} = BTN.fire_batch(m, batch)
    end
  end

  test "the final aggregate capacity matters, not intermediate output order" do
    net = %{
      places: [%{id: "p", capacity: 1}],
      initial: [1],
      transitions: [
        %{id: "put", pre: [], post: [{"p", 1}]},
        %{id: "take", pre: [{"p", 1}], post: []}
      ]
    }

    {:ok, m} = BTN.marking(net, [1])
    {:ok, put} = BTN.transition(net, "put")
    {:ok, take} = BTN.transition(net, "take")
    assert {:ok, ^m} = BTN.fire_batch(m, [put, take])
    assert {:ok, ^m} = BTN.fire_batch(m, [take, put])
    assert {:error, %Error{code: :CapacityExceeded}} = BTN.fire_batch(m, [put])
  end

  test "validate the entire batch before resource checks and reject over-limit input" do
    {m, t} = loop_fixture()

    assert {:error, %Error{code: :InvalidTransition}} =
             BTN.fire_batch(m, [t, t, %{t | pre: [1.0]}])

    assert {:error, %Error{code: :InvalidBatch}} = BTN.fire_batch(m, List.duplicate(t, 257))
    assert {:error, %Error{code: :InvalidBatch}} = BTN.fire_batch(m, [t | :bad])
    assert {:error, %Error{code: :InvalidMarking}} = BTN.fire_batch(%{m | tokens: [2]}, [])
    assert {:error, %Error{code: :InvalidTransition}} = BTN.enabled(m, nil)
  end

  test "256 occurrences and maximum arc sums are exact integers" do
    net = %{
      places: [%{id: "p", capacity: 255}],
      initial: [255],
      transitions: [
        %{id: "big", pre: [{"p", 255}], post: [{"p", 255}]},
        %{id: "idle", pre: [], post: []}
      ]
    }

    {:ok, m} = BTN.marking(net, [255])
    {:ok, big} = BTN.transition(net, "big")
    {:ok, idle} = BTN.transition(net, "idle")
    assert {:ok, ^m} = BTN.fire_batch(m, List.duplicate(idle, 256))

    assert {:error, %Error{code: :InsufficientTokens, details: %{required: 65_280}}} =
             BTN.fire_batch(m, List.duplicate(big, 256))
  end
end
