# Skill: run-tests

**Description:** Run the test suite headless, run a single test, and interpret
Swift Testing output.

**Trigger:** "run the tests", "is it green", a failing CI test job, verifying a
change.

## Run everything (headless)

```
make test
```
Wraps `swift test --xunit-output TestResults/xunit.xml`. Exits non-zero on
failure. The xUnit XML is the machine-readable result CI consumes.

Plain `swift test` also works and is fastest for local iteration.

## Run a single test or suite

Swift Testing filters by name with `--filter` (matches suite or test names):

```
swift test --filter FixtureDecodingTests           # one suite
swift test --filter "Namespace filtering"          # one test (display name)
swift test --filter KubeCoreTests                  # one target's suites
```

## Reading the output

- `✔ Test "…" passed` / `✘ Test "…" failed` per test; a final
  `Test run with N tests … passed/failed` summary line.
- On failure Swift Testing prints the failing `#expect(...)` with the actual
  values and a `file:line`. Jump straight there.
- `#require(...)` throws and stops that test when its value is nil/false — use
  it for preconditions; `#expect` for assertions that should keep going.

## Conventions

- Framework is **Swift Testing** (`import Testing`, `@Suite`, `@Test`), not
  XCTest. Use XCTest only if a dependency forces it.
- Tests are **hermetic**: no network, no kubeconfig. Data comes from fixtures
  through `FakeClusterClient`. See the [`k8s-fixtures`](../k8s-fixtures/SKILL.md)
  skill to add data.
- Put new suites under `Tests/<ModuleName>Tests/`.
