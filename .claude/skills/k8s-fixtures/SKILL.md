# Skill: k8s-fixtures

**Description:** Add or refresh the fake-cluster JSON fixtures that back
hermetic tests and SwiftUI previews.

**Trigger:** "add a fixture", "the tests need a StatefulSet", refreshing sample
data, reproducing a decode bug from a real payload.

## Where fixtures live

`Sources/KubeClient/Fixtures/*.json`. They're declared as a resource in
`Package.swift` (`resources: [.process("Fixtures")]`) and loaded at runtime via
`Bundle.module`. Shipping them in `KubeClient` (not the test target) means both
tests **and** SwiftUI previews use the same hermetic data.

Each file is a Kubernetes list response: `{ "items": [ ... ] }`.

## Add or refresh a fixture

1. **Get a realistic payload — safely.** Never point Ergo at a real cluster.
   Capture with `kubectl` *outside* this repo and scrub it:
   ```
   kubectl get pods -o json > /tmp/raw.json   # in YOUR terminal, not from Ergo
   ```
   Then hand-trim to the fields the models decode and **redact** names, UIDs,
   images, IPs, and annotations. Keep it small (2–4 items).

2. **Match the model.** Fields must line up with the types in
   `Sources/KubeCore/` (`Pod`, `Deployment`, `EventRecord`, `CRDSummary`).
   Timestamps are RFC 3339 (`2026-07-22T18:04:11Z`) — the decoder uses
   `.iso8601`.

3. **Wire a loader** if it's a new resource kind: add a `list…` method on
   `FakeClusterClient` (and the `ClusterClient` protocol) that decodes
   `ItemList<YourType>` from the new file.

4. **Add a decode test** in `Tests/KubeClientTests/` asserting counts and a few
   fields — see `FixtureDecodingTests.swift` for the pattern.

5. Verify: `make test`.

## Rules

- **Fixtures only touch fixtures.** No live-cluster access from tests or the
  skeleton, ever.
- Keep payloads minimal and redacted — they're committed to git.
- Preserve `ownerReferences` when you want to exercise pillar-1 relationship
  graphs; preserve `involvedObject` + timestamps for events.
