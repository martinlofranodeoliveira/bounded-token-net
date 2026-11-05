defmodule BoundedTokenNet.ExhaustiveTest do
  use ExUnit.Case, async: true
  alias BoundedTokenNet, as: BTN
  alias BoundedTokenNet.TestSupport.DirectSimulator, as: Direct

  defp arcs(ids, values) do
    ids
    |> Enum.with_index()
    |> Enum.flat_map(fn {id, i} ->
      case Enum.at(values, i) do
        0 -> []
        weight -> [{id, weight}]
      end
    end)
  end

  defp transitions(ids, vectors) do
    for pre <- vectors, post <- vectors do
      %{id: "unset", pre: arcs(ids, pre), post: arcs(ids, post)}
    end
  end

  defp compare(net) do
    expected = Direct.paths(net)
    assert {:ok, report} = BTN.explore(net, net.initial)
    assert report.complete
    assert MapSet.new(report.order) == MapSet.new(Map.keys(expected))
    assert report.state_count == map_size(expected)

    assert report.edge_count ==
             Enum.sum(Enum.map(expected, fn {_key, row} -> length(row.enabled) end))

    assert report.examined_firings == map_size(expected) * length(net.transitions)
    assert report.terminal_count == Enum.count(expected, fn {_key, row} -> row.terminal end)

    expected_deadlocks =
      expected
      |> Enum.filter(fn {_key, row} -> row.enabled == [] and not row.terminal end)
      |> Enum.map(&elem(&1, 0))
      |> MapSet.new()

    assert MapSet.new(report.deadlocks) == expected_deadlocks

    for {key, reference} <- expected do
      row = Map.fetch!(report.states, key)
      assert row.marking == reference.tokens
      assert row.enabled == reference.enabled
      assert row.terminal == reference.terminal
      assert row.deadlock == (reference.enabled == [] and not reference.terminal)
      assert {:ok, witness} = BTN.witness(report, key)
      assert witness == reference.path
      assert {:ok, final} = Direct.replay(net, net.initial, witness)
      assert final == row.marking
      assert Direct.enabled(net, final) == row.enabled
      assert final in net.terminals == row.terminal
    end
  end

  @tag timeout: 120_000
  test "all binary two-place arc vectors, two transitions, capacities zero or one" do
    vectors = for a <- 0..1, b <- 0..1, do: [a, b]
    choices = transitions(["p", "q"], vectors)

    # 256 ordered transition pairs times 9 capacity/initial combinations:
    # 2,304 complete model explorations, not a sampled random generator.
    for first <- choices, second <- choices, cp <- 0..1, cq <- 0..1, p <- 0..cp, q <- 0..cq do
      net = %{
        places: [%{id: "p", capacity: cp}, %{id: "q", capacity: cq}],
        initial: [p, q],
        transitions: [%{second | id: "z"}, %{first | id: "a"}],
        terminals: if(rem(p + q + cp + cq, 2) == 0, do: [[0, 0]], else: [])
      }

      compare(net)
    end
  end

  @tag timeout: 120_000
  test "all one-place weights zero through two with capacities zero through two" do
    choices = transitions(["p"], [[0], [1], [2]])

    for first <- choices, second <- choices, capacity <- 0..2, initial <- 0..capacity do
      compare(%{
        places: [%{id: "p", capacity: capacity}],
        initial: [initial],
        transitions: [%{second | id: "z"}, %{first | id: "a"}],
        terminals: [[capacity]]
      })
    end
  end

  test "every truncated tiny search retains independently replayable discovered witnesses" do
    net = %{
      places: [%{id: "p", capacity: 2}],
      initial: [0],
      transitions: [
        %{id: "add", pre: [], post: [{"p", 1}]},
        %{id: "remove", pre: [{"p", 1}], post: []}
      ],
      terminals: [[2]]
    }

    for states <- 1..3, firings <- 0..6 do
      {:ok, report} = BTN.explore(net, [0], %{max_states: states, max_firings: firings})
      assert report.state_count <= states
      assert report.examined_firings <= firings

      for key <- report.order do
        {:ok, path} = BTN.witness(report, key)
        assert {:ok, Tuple.to_list(key)} == Direct.replay(net, [0], path)
        row = report.states[key]
        assert row.terminal == row.marking in net.terminals
        if row.enabled != nil, do: assert(row.enabled == Direct.enabled(net, row.marking))
      end
    end
  end
end
