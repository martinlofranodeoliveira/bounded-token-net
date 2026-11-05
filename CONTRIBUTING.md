# Contributing

Bounded Token Net is original MIT software by Lofrano Tecnologia. Development
version 0.1.0 has a deliberately small contract. Please discuss a behavioral
change with a minimal synthetic model and its expected result before expanding
the input language or adding dependencies.

## Local checks

Use Elixir 1.18 or compatible later 1.x with Erlang/OTP. CI targets official
Elixir 1.18 and 1.20.5 images and records their resolved digests. No Hex setup,
external service or dependency preparation is required.

```sh
mix compile --warnings-as-errors
mix test --seed 0
mix run demo/assert_demo.exs
mix run demo/assert_demo.exs --json
mix format
```

The default demo must print exactly:

```text
DEMO_OK states=4 deadlocks=1 witness=take1,take2
```

Do not commit generated build output. Test support belongs in `test_support/`
and is explicitly required from `test/test_helper.exs`; it is not a hidden Mix
source-discovery convention. Keep the independent simulator independent: do
not make it call production validators, firing predicates, batch functions or
search. Add a regression for malformed input as well as the intended behavior.
Retain exhaustive tiny-net witness replay, capacity tests, terminal classification
and both budget-equality cases when refactoring.

## Review expectations

* Preserve proper-list bounds, integer checks, schema checks and no dynamic atoms.
* Reject malformed values before returning any changed marking.
* Do not turn incomplete searches into negative reachability or safety claims.
* Update the precise contract and both language summaries for semantic changes.
* Use synthetic fixtures only; never include personal information, credentials,
  private client code, invented users, benchmarks or certification claims.
* Keep operations pure: no executing services, telemetry, persistence or implicit I/O.
* Explain the worst-case resource effect of a new feature.

Issue reports should include the runtime version, smallest synthetic net,
operation and expected/actual tagged result. For official-image runs include
the actual image digest printed by `docker image inspect`, not just its tag.
Do not include secrets. Security issues follow [SECURITY.md](SECURITY.md),
not a public issue with exploit details. General contact is through the
[official homepage](https://lofranotecnologia.com.br).

Contributions must be original or have clearly compatible licensing and may
not include copied private client material. The project uses the MIT license;
organization metadata contains no invented personal contact details.
