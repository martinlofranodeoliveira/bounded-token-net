alias BoundedTokenNet, as: BTN

args = System.argv()

unless args in [[], ["--json"]] do
  IO.puts(:stderr, "usage: mix run demo/assert_demo.exs [--json]")
  System.halt(2)
end

net = BTN.Examples.two_resources()
{:ok, report} = BTN.explore(net, net.initial)

unless report.complete and report.state_count == 4 and
         report.unexpected_deadlock_count == 1 and report.edge_count == 4 do
  raise "synthetic model regression"
end

[key] = report.deadlocks
{:ok, witness} = BTN.witness(report, key)

unless witness == ["take1", "take2"] and key == {0, 0, 1, 1} do
  raise "canonical witness regression"
end

{:ok, initial} = BTN.marking(net, net.initial)

final =
  Enum.reduce(witness, initial, fn id, marking ->
    {:ok, transition} = BTN.transition(net, id)
    {:ok, next} = BTN.fire(marking, transition)
    next
  end)

unless List.to_tuple(final.tokens) == key, do: raise("witness replay regression")

case args do
  [] ->
    IO.puts(
      "DEMO_OK states=#{report.state_count} deadlocks=#{report.unexpected_deadlock_count} witness=#{Enum.join(witness, ",")}"
    )

  ["--json"] ->
    ids = Enum.map_join(witness, ",", fn id -> "\"" <> id <> "\"" end)

    IO.puts(
      "{\"complete\":true,\"states\":#{report.state_count},\"deadlocks\":#{report.unexpected_deadlock_count},\"witness\":[#{ids}]}"
    )
end
