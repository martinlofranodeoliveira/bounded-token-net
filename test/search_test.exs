defmodule BoundedTokenNet.SearchTest do
  use ExUnit.Case, async: true
  alias BoundedTokenNet, as: BTN
  alias BoundedTokenNet.Error
  alias BoundedTokenNet.TestSupport.DirectSimulator, as: Direct

  test "toggle graph, exact work accounting, and canonical witness" do
    net = BTN.Examples.toggle()
    assert {:ok, report} = BTN.explore(net, net.initial)
    assert report.complete
    assert report.reason == nil
    assert report.state_count == 2
    assert report.edge_count == 2
    assert report.examined_firings == 4
    assert report.unexpected_deadlock_count == 0
    assert report.order == [{1, 0}, {0, 1}]
    assert {:ok, ["go"]} == BTN.witness(report, {0, 1})
    assert report.states[{1, 0}].enabled == ["go"]
    assert report.states[{0, 1}].enabled == ["back"]
  end

  test "exact four-state synthetic resource graph and replayable deadlock" do
    net = BTN.Examples.two_resources()
    {:ok, report} = BTN.explore(net, net.initial)
    assert report.complete
    assert report.order == [{1, 1, 0, 0}, {0, 1, 1, 0}, {1, 0, 0, 1}, {0, 0, 1, 1}]
    assert report.state_count == 4
    assert report.unexpected_deadlock_count == 1
    assert report.deadlocks == [{0, 0, 1, 1}]
    assert report.edge_count == 4
    assert report.examined_firings == 8
    {:ok, path} = BTN.witness(report, hd(report.deadlocks))
    assert path == ["take1", "take2"]
    assert {:ok, [0, 0, 1, 1]} == Direct.replay(net, net.initial, path)

    reversed = %{net | transitions: Enum.reverse(net.transitions)}
    assert {:ok, ^report} = BTN.explore(reversed, reversed.initial)
  end

  test "terminal labels do not cut off reachability" do
    net = BTN.Examples.toggle()
    net = %{net | terminals: [[1, 0]]}
    {:ok, report} = BTN.explore(net, net.initial)
    assert report.complete and report.state_count == 2 and report.edge_count == 2
    assert report.terminal_count == 1
    assert report.states[{1, 0}].terminal
    refute report.states[{1, 0}].deadlock

    zero = %{places: [%{id: "p", capacity: 0}], initial: [0], transitions: [], terminals: [[0]]}
    {:ok, report} = BTN.explore(zero, [0], %{max_firings: 0})
    assert report.complete
    assert report.terminal_count == 1
    assert report.unexpected_deadlock_count == 0
    assert report.states[{0}].enabled == []
  end

  test "state-cap equality can complete; it stops only on a new successor" do
    net = BTN.Examples.toggle()
    {:ok, limited} = BTN.explore(net, net.initial, %{max_states: 1})
    refute limited.complete
    assert limited.reason == :state_limit
    assert limited.state_count == 1
    assert limited.examined_firings == 2
    assert limited.states[{1, 0}].enabled == nil
    assert limited.states[{1, 0}].deadlock == nil
    assert {:ok, []} = BTN.witness(limited, {1, 0})
    assert {:error, %Error{code: :UnknownMarking}} = BTN.witness(limited, {0, 1})

    {:ok, complete} = BTN.explore(net, net.initial, %{max_states: 2})
    assert complete.complete and complete.state_count == 2

    loop = %{
      places: [%{id: "p", capacity: 0}],
      initial: [0],
      transitions: [%{id: "idle", pre: [], post: []}]
    }

    {:ok, same} = BTN.explore(loop, [0], %{max_states: 1, max_firings: 1})
    assert same.complete and same.edge_count == 1
  end

  test "disabled transitions consume work; equality completes only if no attempts remain" do
    net = BTN.Examples.toggle()
    {:ok, short} = BTN.explore(net, net.initial, %{max_firings: 3})
    refute short.complete
    assert short.reason == :firing_limit
    assert short.examined_firings == 3
    assert short.state_count == 2
    assert short.states[{0, 1}].enabled == nil
    assert {:ok, ["go"]} = BTN.witness(short, {0, 1})
    {:ok, exact} = BTN.explore(net, net.initial, %{max_firings: 4})
    assert exact.complete and exact.examined_firings == 4

    disabled = %{
      places: [%{id: "p", capacity: 0}],
      initial: [0],
      transitions: [%{id: "need", pre: [{"p", 1}], post: []}]
    }

    {:ok, none} = BTN.explore(disabled, [0], %{max_firings: 0})
    refute none.complete
    assert none.reason == :firing_limit
    assert none.unexpected_deadlock_count == 0
    {:ok, one} = BTN.explore(disabled, [0], %{max_firings: 1})
    assert one.complete and one.unexpected_deadlock_count == 1
  end

  test "lexical shortest paths, including duplicate destinations" do
    net = %{
      places: [%{id: "p", capacity: 2}],
      initial: [0],
      transitions: [
        %{id: "z-direct", pre: [], post: [{"p", 2}]},
        %{id: "b-step", pre: [], post: [{"p", 1}]},
        %{id: "a-step", pre: [], post: [{"p", 1}]}
      ]
    }

    {:ok, report} = BTN.explore(net, [0])
    assert {:ok, ["a-step"]} = BTN.witness(report, {1})
    assert {:ok, ["z-direct"]} = BTN.witness(report, {2})
  end

  test "concurrent callers remain independent; malformed witness trees are bounded" do
    net = BTN.Examples.toggle()

    results =
      1..8 |> Task.async_stream(fn _ -> BTN.explore(net, net.initial) end) |> Enum.to_list()

    assert [{:ok, {:ok, first}} | _] = results
    assert Enum.all?(results, &(&1 == {:ok, {:ok, first}}))
    assert {:error, %Error{code: :InvalidReport}} = BTN.witness(nil, {0})
    cyclic = %{initial: {0}, states: %{{0} => %{parent: {0}, via: "x"}}}
    assert {:error, %Error{code: :InvalidReport}} = BTN.witness(cyclic, {0})
    assert {:error, %Error{code: :InvalidReport}} = BTN.witness(cyclic, {1})

    assert {:error, %Error{code: :InvalidReport}} =
             BTN.witness(%{initial: :map, states: MapSet.new([1])}, :map)

    non_root_cycle = %{
      initial: {0},
      states: %{
        {0} => %{parent: nil, via: nil},
        {1} => %{parent: {2}, via: "a"},
        {2} => %{parent: {1}, via: "b"}
      }
    }

    assert {:error, %Error{code: :InvalidReport, at: "parents"}} =
             BTN.witness(non_root_cycle, {1})
  end
end
