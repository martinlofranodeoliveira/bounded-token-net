# Design of development 0.1.0

## Intent and separation

Bounded Token Net supports teaching and reviewing explicit resource assumptions.
It does not schedule tasks or implement the protocol being modeled. Markings
are finite bounded integer vectors, transitions have weighted pre/post arcs,
and firing is a discrete atomic step. No duration or external effect exists.

The source has four layers:

1. `Validation` checks bounded proper lists and exact raw map shapes, resolves
   sparse arcs into dense vectors, and binds schemas. Public steps recheck
   structs because Elixir structs can be manually constructed or modified.
2. `Step` aggregates batch requirements, checks the original inputs, computes
   final tokens and checks capacity. The search uses its validated internal
   arithmetic fast path, not repeated raw-net parsing.
3. `Search` performs FIFO BFS with `:queue`, lexical IDs and tuple keys. Each
   transition attempt consumes one work unit. It retains first predecessors,
   not every path prefix or the full edge list.
4. `Invariants` checks signed integer incidence deltas, independently of
   reachability. This deliberately also rejects nonconservation on unreachable
   transitions.

The public net remains an explicit raw map rather than an opaque server handle.
`validate/1` returns `:ok`; `marking/2` and `transition/2` provide bound values.
Repeated lookup reparses a small bounded net. This favors a small, auditable API
over caching and lifecycle management. There is no GenServer, ETS, NIF, database,
atom conversion, or mutable shared state. Independent concurrent callers need
no locks. Concurrent callers can still exhaust a host's total resources; the
library does not impose a global concurrency policy.

## Determinism and observations

Place order determines vector coordinates. ASCII binary transition IDs sort
lexically, with no locale or caller order dependence. For any path length,
FIFO parent order and sorted outgoing transitions enumerate candidate shortest
paths lexically; the first discovery is therefore the canonical shortest path.
Visited tuple keys collapse alternate paths without losing reachability.

Terminal labels classify, rather than prune. A fully expanded nonterminal with
no enabled transition is a deadlock. Capacity-disabled transitions count as
not enabled. Incomplete expansion leaves enabled/deadlock fields unknown.
Returned predecessor links always describe actually fired transitions, even
when a later budget prevents completion. Known deadlock counts in incomplete
reports must never be described as exhaustive.

At the state ceiling, processing a visited successor is still useful; a cycle
can finish at exact capacity. At the work ceiling, finishing the last pending
attempt is sufficient; equality itself is not exhaustion. These distinctions
are regression tested independently from ordinary reachability tests.

## Bounds and costs

Let P <= 32, T <= 64, S <= 10,000, A <= 100,000 and B <= 256. Parsing traverses
bounded lists, up to 256 terminal vectors, and at most 32 arcs per side. Each
firing attempt costs O(P); search arithmetic costs O(A P), plus persistent-map
and queue operations. Rows store O(S(P + T)) vector/schema-independent data in
the worst case; they do not retain an O(A) edge list. Struct schemas are shared
immutable terms. Tuple keys duplicate token coordinates, a deliberate simplicity
tradeoff at these limits. Report maps and queue structures have BEAM overhead;
these are finite ceilings, not measured memory benchmarks.

A predecessor tree uses O(S) links rather than O(S²) full path lists. A witness
request costs O(path length) and allocates only that path. Callers materializing
all long witnesses can themselves create quadratic total output. Batch totals
are bounded by 256 * 255 per place. Invariant arithmetic may exceed 32-bit
ranges and uses exact BEAM integers. No overflow wraparound is accepted.

Bounded traversal rejects an improper or overlong list without visiting its
whole tail. The library cannot reclaim or limit a giant term the caller already
allocated, control the BEAM scheduler, or provide a wall-time SLA. Limits are
integer work/state bounds, not elapsed-time promises.

## Independent tests

`test_support/direct_simulator.ex` reads sparse arc lists and computes direct
indexed-vector results without any production fire/enabled/batch code. Its tiny
reference search enumerates complete path layers up to the finite universe size
minus one, rather than reusing the production visited queue. Shortest paths are
simple, so this depth suffices. The helper rejects universes larger than nine
states to keep the deliberately redundant oracle bounded.

Exhaustive tests cover all 2,304 ordered two-transition models on two places
with binary arc weights, capacities zero or one, and all valid initial vectors.
Another 486 models cover one place, weights zero through two and capacities
zero through two. Every reported witness is independently replayed; final
vectors, enabled sets, shortest canonical paths, terminal labels and deadlock
classification are compared. Terminal configurations are varied deterministically;
this is not exhaustive enumeration of all possible terminal subsets.

Named regressions cover batch feedback, aggregate final capacity, malformed
structs, duplicate arcs, exact integer deltas, disabled-attempt charging, limit
equality, partial observations and concurrent independent calls. These tests
provide evidence for the documented subset, not an implementation proof.

## Runtime reproducibility

No dependency lockfile is needed because there are no dependencies. Mix output
is generated locally and is not committed. CI uses read-only repository
permissions, a timeout and a pinned checkout action. It resolves official
Elixir 1.18 and 1.20.5 image tags, records the actual digest, then runs compilation,
tests and demos with container networking disabled and without elevated
container privileges. Image retrieval is preparation, not a runtime service.
Tags can move; retain the printed digest when comparing executions. No digest
is asserted without resolution. The `run` alias compiles quietly to preserve
the demo's exact stdout even on a fresh build.

## Conceptual references

Original implementation and tests were written for this project; no tutorial
code is incorporated. Conceptual references for places, markings, weighted arcs,
firing and invariants:

* [Hamburg Petri-net introduction index](https://www.informatik.uni-hamburg.de/TGI/PetriNets/introductions/)
* [Author tutorial hosted by Hamburg](https://www.informatik.uni-hamburg.de/TGI/PetriNets/introductions/aalst/)
* [Elixir Map documentation](https://hexdocs.pm/elixir/Map.html)
* [ExUnit documentation](https://hexdocs.pm/ex_unit/ExUnit.html)

The capacity rule, batch rule, input limits and report schema are explicitly
this project's contract. No broad formal-methods or industrial-standard
compliance is claimed.
