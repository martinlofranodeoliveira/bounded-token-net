# Bounded Token Net

Development version **0.1.0**, by [Lofrano Tecnologia](https://lofranotecnologia.com.br).
MIT licensed. [Português](README.pt-BR.md).

A dependency-free Elixir library for small, explicit, finite resource models.
It fires weighted transitions atomically, explores reachable token vectors,
and exposes replayable shortest deadlock witnesses. No workflow is executed.
There are no processes to start, clocks, persistence, telemetry, model APIs,
Hex packages, NIFs or external services.

## Install, test and demonstrate

Use Elixir 1.18 or a compatible later 1.x runtime with Erlang/OTP. The CI matrix
targets Elixir 1.18 and 1.20.5 using official images; these are targets, not a
claim that a particular run has passed. From the project directory:

```sh
mix compile --warnings-as-errors
mix test --seed 0
mix run demo/assert_demo.exs
mix run demo/assert_demo.exs --json
```

No dependency preparation is necessary. The `run` alias first compiles quietly,
so a successful fresh demo also has exactly this stdout:

```text
DEMO_OK states=4 deadlocks=1 witness=take1,take2
```

The optional machine-readable mode prints one JSON line instead:

```json
{"complete":true,"states":4,"deadlocks":1,"witness":["take1","take2"]}
```

For an official-image alternative, resolve and record the image rather than
assuming a tag is an immutable runtime identifier:

```sh
docker pull elixir:1.18
docker image inspect elixir:1.18 --format '{{index .RepoDigests 0}}'
docker run --rm --network none --user "$(id -u):$(id -g)" -e HOME=/tmp -e ERL_FLAGS="+S 2:2 +SDcpu 1 +SDio 1" -v "$PWD:/project" -w /project elixir:1.18 mix test --seed 0
```

Keep the printed digest with your test record; CI records its actual resolved
digest in the job summary. No digest or execution result is invented here.
To use this library from a neighboring Mix project, add
`{:bounded_token_net, path: "../bounded-token-net"}` to that project's `deps`.
This is a local source dependency, not a package-publication claim.

## Small example

```elixir
alias BoundedTokenNet, as: BTN
net = BTN.Examples.toggle()
:ok = BTN.validate(net)
{:ok, initial} = BTN.marking(net, [1, 0])
{:ok, go} = BTN.transition(net, "go")
{:ok, true} = BTN.enabled(initial, go)
{:ok, next} = BTN.fire(initial, go)
next.tokens # [0, 1]
{:ok, report} = BTN.explore(net, initial)
{report.complete, report.state_count, report.edge_count} # {true, 2, 2}
{:ok, ["go"]} = BTN.witness(report, {0, 1})
{:ok, %{conserved_value: 1}} = BTN.verify_invariant(net, [1, 1])
```

Nets use atom field names and binary IDs; no ID becomes an atom. Place order is
vector order. Transition input order is irrelevant: lexical binary ID order
breaks ties. A bound marking carries its vector plus place IDs and capacities,
so standalone firing can enforce capacity and schema constraints.

```elixir
net = %{
  places: [%{id: "slot", capacity: 1}],
  initial: [1],
  transitions: [%{id: "reuse", pre: [{"slot", 1}], post: [{"slot", 1}]}],
  terminals: []
}
{:ok, m} = BTN.marking(net, [1])
{:ok, reuse} = BTN.transition(net, "reuse")
{:ok, m} = BTN.fire(m, reuse)
{:ok, m} = BTN.fire(m, reuse)
{:error, %{code: :InsufficientTokens}} = BTN.fireBatch(m, [reuse, reuse])
```

A batch consumes against the **original** vector; its outputs cannot finance
other occurrences. `fire_batch/2` is the idiomatic alias of `fireBatch/2`.

## Search results are conditional evidence

```elixir
net = BTN.Examples.toggle()
{:ok, partial} = BTN.explore(net, net.initial, %{max_states: 1})
{partial.complete, partial.reason} # {false, :state_limit}
{:ok, []} = BTN.witness(partial, partial.initial)
```

Limits are hard bounded: 32 places, 64 transitions, capacities and arc weights
at most 255; searches default to 10,000 discovered states and 100,000 examined
transition attempts. Every attempt counts, including disabled transitions.
An incomplete report retains discovered witness parent links, but proves no
unreachability, absence of deadlocks, safety or liveness. `nil` enabled/deadlock
fields mean expansion was not finished, not that nothing is enabled.

Declared terminals are classification labels, never an exploration cutoff.
Unexpected deadlocks are reachable **nonterminal** states with no enabled
transition, including capacity-disabled transitions.

## Why this shape?

The API separates net parsing, atomic vector arithmetic and deterministic BFS.
Compact predecessor links avoid quadratic storage of every full witness.
Integer place invariants use exact incidence arithmetic on every transition,
including unreachable transitions. This is a useful structural check, not
formal certification. Independent sparse-arc simulation and exhaustive tiny
models test the dense production implementation.

The demo is a **one-shot synthetic finite resource model**: four capacity-one
places `r1,r2,h1,h2`, initial `[1,1,0,0]`, `take1: r1 → h1`,
`take2: r2 → h2`, no releases and no terminals. Its four states are
`[1,1,0,0]`, `[0,1,1,0]`, `[1,0,0,1]`, `[0,0,1,1]`.
The final both-held state is a model deadlock with witness `take1,take2`.
This does **not** demonstrate real circular wait in an operating system.

## Boundaries and documentation

Models and capacities are caller assumptions. Even complete exploration only
describes that finite model, not an implementation. There is no unbounded-net
proof, timed/stochastic semantics, PNML/XML parser, authorization, workflow
execution, or industrial standards-compliance claim. Input terms must already
fit in the caller's memory; the library bounds its own traversal and output,
not the allocation of terms before a call.

* [Exact development contract](docs/contract.md)
* [Design, complexity and sources](docs/design.md)
* [Semântica e limitações em português](docs/semantics.pt-BR.md)
* [Contributing](CONTRIBUTING.md), [security reporting](SECURITY.md)

General contact: [official homepage](https://lofranotecnologia.com.br).
Repository: https://github.com/martinlofranodeoliveira/bounded-token-net
