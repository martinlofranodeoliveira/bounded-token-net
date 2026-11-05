# Security policy

Bounded Token Net development version 0.1.0 is a pure in-memory modeling library,
not a sandbox, workflow executor or assurance system. Only the development
contract in `docs/contract.md` is in scope; no supported-release timeline or
response-time SLA is promised.

## Reporting

If GitHub private vulnerability reporting is enabled for the repository,
submit a private report at:

https://github.com/martinlofranodeoliveira/bounded-token-net/security/advisories/new

If that facility is unavailable, use the general contact route on the
[official Lofrano Tecnologia homepage](https://lofranotecnologia.com.br) to ask
for a private reporting channel. Do not post vulnerability details, credentials
or personal data in a public issue. No email address or alternate private
channel is asserted here.

Useful reports include a minimal synthetic input, Elixir/OTP versions, operation,
expected bound or contract behavior, and observed failure. For image-based
reproduction include the actually resolved image digest. Avoid private models,
client code, secrets and real personal data.

## Boundaries

Input list lengths, IDs, capacities, arc weights, batches, terminal lists,
invariant weights and search budgets are bounded and checked. Structs are
revalidated at public step boundaries. No parser creates atoms from IDs.
There are no runtime network calls, filesystem operations, external services,
Hex/NIF dependencies, telemetry or credentials.

These bounds do not limit input allocation before the call, the host VM,
caller concurrency, or callers retaining many reports and materialized paths.
A model is not a proof of its implementation. An incomplete search establishes
no unreachability, safety, liveness or absence of deadlocks. Complete results
are still conditional on the exact finite model and supplied capacities.
