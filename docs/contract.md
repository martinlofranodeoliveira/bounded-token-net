# Development 0.1.0 contract

This document specifies the implemented finite, discrete subset. It makes no
Petri-net standards-compliance or implementation-correctness certification
claim. Public entry point: `BoundedTokenNet` (abbreviated `BTN`). All operations
are pure and immutable. No dynamic atom creation, file access, network access,
execution engine, process ownership or application service is involved.

## Input language and hard bounds

A raw net is a non-struct map with exactly these required atom keys:

* `places`: proper list of 1..32 maps, each exactly `%{id: binary, capacity: integer}`;
* `transitions`: proper list of 0..64 maps, each exactly
  `%{id: binary, pre: arcs, post: arcs}`;
* `initial`: token vector;
* optional `terminals`: proper list of 0..256 token vectors, default `[]`.

Unknown keys and string field names are rejected. IDs contain 1..64 bytes and
match ASCII `[A-Za-z0-9][A-Za-z0-9_.-]*` exactly. Places have unique IDs;
transitions have unique IDs. These are separate namespaces: a place and a
transition may share an ID. Binary IDs never become atoms. Place order is
significant; transition order is normalized to ascending binary ID order.

Capacity is an integer in 0..255. Each side's arcs are a proper list of at most
32 `{place_id, weight}` tuples, with known place IDs and integer weights 1..255.
Repeated places **within either side** are rejected, not summed. The same
place **may** occur in both pre and post. Empty arc lists are allowed, including
an entirely empty transition. An arc may exceed its place's capacity; such an
input can be permanently disabled. Zero-weight sparse arcs are invalid;
absence represents zero. Arc list order has no semantic effect.

Vectors are proper lists with exactly one integer per declared place. Tokens
are nonnegative and cannot exceed the corresponding capacities. Float and
boolean values are never integers for this contract. Initial and all terminal
vectors are checked even when a different initial vector is passed to search.
Duplicate terminal vectors are rejected. A terminal need not be reachable or
have no enabled transitions.

Input lists are checked with bounded prefix traversal before other enumeration.
Improper and overlong lists are errors. The library cannot prevent callers
from allocating oversized terms before calling it. Integer comparisons precede
arithmetic; BEAM integers are arbitrary precision, so arithmetic never wraps.

## Public results and schema-bound values

`validate(net)` returns `:ok` or `{:error, %BTN.Error{}}`.

`marking(net, tokens)` returns `{:ok, %BTN.Marking{places: ids,
capacities: capacities, tokens: vector}}` after validating the entire net.
It also accepts an already bound marking with an identical ordered schema.

`transition(net, id)` returns `{:ok, %BTN.Transition{id: id, places: ids,
capacities: capacities, pre: dense_vector, post: dense_vector}}`.
Dense vectors contain integers 0..255, including zeros for absent arcs.
The complete net is validated before lookup. A well-formed unknown ID returns
`UnknownTransition`. A malformed ID returns `InvalidTransition`.

Structs are not trusted credentials. Public firing revalidates their schema,
IDs, vector lengths and integer ranges. A dense transition can be constructed
by a caller if valid; it need not be found in some stored net. Marking and
transition must have identical ordered place IDs and capacities. This prevents
accidentally using equal-length vectors from differently ordered schemas.
The standalone step API takes bound markings, not bare token lists.

`enabled(marking, transition)` returns `{:ok, true}` iff firing succeeds;
insufficient inputs or excessive final capacity return `{:ok, false}`.
Malformed data is an error, never silently disabled.

`fire(marking, transition)` returns `{:ok, new_marking}` or an error. For every
place i, require `m[i] >= pre[i]`, then compute
`m'[i] = m[i] - pre[i] + post[i]`, then require `m'[i] <= capacity[i]`.
Consumption and production at the same place use the original input requirement.

`fireBatch(marking, occurrences)` and `fire_batch/2` are identical. Occurrences
are a proper list of at most 256 bound transitions; repetition means multiple
occurrences. All occurrences are validated before token arithmetic. Sum pre
and post independently. Require **all** `m[i] >= sumPre[i]` against the original
marking, then compute `m'[i] = m[i] - sumPre[i] + sumPost[i]` and check all final
capacities. Produced tokens cannot fund any batch input. There are no ordered
intermediate capacity checks. Empty batch returns the identical bound marking,
but still validates it. Single-place aggregate arc sums are at most 65,280.

A consume/reproduce loop with one available token fires twice sequentially but
two occurrences in one batch fail with `InsufficientTokens`. Failing steps
return no new or partially changed marking. Error priority is marking validity,
batch shape, occurrence validity/schema in input order, first insufficient
input in place order, then first excessive final capacity in place order.

## Search

`explore(net, initial, limits \\ %{})` accepts a valid raw net and either a bare
initial vector or a matching bound marking. Limits are a non-struct map with
only optional atom keys:

| Key | Default | Allowed integers |
| --- | ---: | ---: |
| `max_states` | 10000 | 1..10000 |
| `max_firings` | 100000 | 0..100000 |

These are hard ceilings, not suggestions. Invalid limits are errors rather than
clamped values. The conceptual names maxStates/maxFirings are spelled in Elixir
as `:max_states`/`:max_firings`; aliases are not accepted. Validation order is
net, supplied initial, limits. Limits do not control wall time.

The engine uses a FIFO queue, lexical transition IDs, immutable tuple token keys,
and first-discovery predecessor links. The root counts as one discovered state.
It examines every transition at each expanded state, including terminals.
**Every examined attempt counts**, including disabled transitions and attempts
whose successor is already visited. An enabled attempt increments `edge_count`.
For a complete report this counts all reachable labeled firing edges, including
self-loops and distinct transitions with the same destination.

At state-cap equality, search continues for known successors. Only an attempt
that discovers a genuinely new state beyond the cap stops with `state_limit`;
the rejected successor is not retained, but that attempt and edge are counted.
Work-cap equality stops with `firing_limit` only if another transition attempt
is needed. Finishing the last expansion at exact equality can be complete.
With zero transitions, zero work can complete. If the final permitted attempt
would violate the state cap, `state_limit` is the immediate reason.

Success returns `{:ok, report}` with:

* `complete`: boolean; `reason`: `nil`, `:state_limit` or `:firing_limit`;
* `initial`: root tuple key; `limits`: resolved limits;
* `states`: map from tuple keys to rows; `order`: keys in discovery order;
* `state_count`: number retained, including root;
* `terminal_count`: number of retained states labeled terminal;
* `unexpected_deadlock_count`: number of fully established nonterminal deadlocks;
* `deadlocks`: their keys in expansion order;
* `examined_firings`: attempted transitions, enabled or disabled;
* `edge_count`: successful attempted firings, including a state-cap-rejected edge.

Each row has `marking` (bare vector), `parent` (tuple key or root `nil`), `via`
(transition ID or root `nil`), `terminal` (boolean), `enabled` and `deadlock`.
After full expansion, `enabled` is the sorted list of enabled IDs and `deadlock`
is a boolean. Before full expansion, **both are nil**, even if some attempts
have already been counted. No partially known enabled set is presented as full.
An unexpected deadlock means nonterminal and no enabled transition; a terminal
with no enabled transitions is not an unexpected deadlock. Terminal labels do
not suppress exploration.

`witness(report, tuple_key)` returns `{:ok, [transition_ids]}` for a retained
state. Parent links are the compact returned witness representation; paths are
materialized only on request. The root witness is `[]`. All discovered witnesses
are shortest; among equally short paths, ascending lexical ID sequences win.
These properties also hold for retained states of incomplete reports. Keys not
retained return `UnknownMarking`, which is **not an unreachability statement**.
The accessor detects missing/cyclic/malformed parent chains with bounded work;
it does not authenticate caller-edited reports. Do not edit reports if you
intend to rely on their witnesses.

Incomplete counts and classified deadlocks are observations only. Unknown rows
remain unknown. Incompleteness proves no absence of deadlocks, unreachability,
safety or liveness. Completeness exhausts only the supplied finite model.

## Place invariants

`verify_invariant(net, weights)` accepts a proper vector of exactly one integer
per place, each between -1,000,000 and 1,000,000 inclusive. For each transition
in canonical ID order, compute the exact integer
`delta = sum(weights[i] * (post[i] - pre[i]))`.
The first nonzero delta returns
`{:error, %BTN.Error{code: :InvariantViolation, at: id,
details: %{transition: id, delta: integer}}}`.
On success return `{:ok, %{conserved_value: dot(weights, net.initial)}}`.
The value refers to the net's declared initial, not a separately explored root.
All transitions are checked, even unreachable ones. Signed and zero weights are
allowed. Incidence arithmetic is not formal certification of a system.

For the toggle with IDs `go` and `return`, weights `[1,1]` conserve value 1;
`[1,0]` fail first on `go` with delta -1. Lexical order matters: a reverse
transition named `back` would instead fail first on `back` with delta +1.

## Diagnostics

Errors are `{:error, %BTN.Error{code: atom, at: bounded_string, details: map}}`.
Codes are `InvalidNet`, `InvalidMarking`, `InvalidTransition`, `InvalidBatch`,
`InvalidLimits`, `SchemaMismatch`, `UnknownTransition`, `InsufficientTokens`,
`CapacityExceeded`, `InvalidInvariant`, `InvariantViolation`, `UnknownMarking`
and `InvalidReport`. In Elixir, for example, `:InsufficientTokens` is an atom.
These are not raised exceptions for ordinary malformed input. Internal module
functions marked `@moduledoc false` are not public API. As with other BEAM code,
VM termination and memory exhaustion outside these input bounds cannot be
converted into ordinary validation errors.

`at` identifies a field or transition; vector indices in diagnostics are
zero-based. Text and optional detail keys are explanatory, except the invariant
`transition`/`delta` and resource-error numeric detail keys shown in tests.
Do not branch on diagnostic prose. Inputs are not copied wholesale into errors.

## Exact demonstration model

Ordered places `r1,r2,h1,h2`, all capacity 1; initial `[1,1,0,0]`.
`take1` consumes one r1 and produces one h1; `take2` consumes one r2 and produces
one h2. No other arcs, releases or terminals. BFS order:

1. `[1,1,0,0]`, witness `[]`;
2. `[0,1,1,0]`, witness `[take1]`;
3. `[1,0,0,1]`, witness `[take2]`;
4. `[0,0,1,1]`, witness `[take1,take2]`, unexpected deadlock.

This one-shot synthetic finite resource model has four edges, eight examined
attempts, four states and one deadlock. It is not evidence of real circular wait.
Successful default demo stdout is exactly one line:
`DEMO_OK states=4 deadlocks=1 witness=take1,take2` followed by LF.
