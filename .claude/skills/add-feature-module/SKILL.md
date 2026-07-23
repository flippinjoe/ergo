# Skill: add-feature-module

**Description:** Add a new SPM target/module that respects the three-pillar
seams, naming, and test conventions.

**Trigger:** "add a module", "new package target", starting a feature that
deserves its own layer (e.g. `KubeSchema`, `KubeAgents`).

## Decide where it belongs first

- Pure value types / domain logic → depends only on `KubeCore`.
- Anything doing I/O or hitting the API boundary → depends on `KubeClient`.
- SwiftUI surface → depends on `KubeUI` (+ the above).
- Keep the graph **acyclic and one-directional**: `KubeUI ▶ KubeClient ▶ KubeCore`.
  A new module slots in alongside, never creating a cycle.

Read [`../../knowledge/module-boundaries.md`](../../knowledge/module-boundaries.md)
before choosing.

## Steps

1. Create `Sources/<ModuleName>/` with at least one `.swift` file.
2. Add the target + product to `Package.swift`. Apply the shared
   `swiftSettings: .strict` so the language mode/concurrency match the graph.
   Add a matching `.testTarget` named `<ModuleName>Tests`.
3. If the module needs to appear in the app, add its product to the `Ergo`
   target's `dependencies` in `project.yml`, then `make generate`.
4. Add a test suite under `Tests/<ModuleName>Tests/` (Swift Testing).
5. Verify: `make build && make test && make lint`.

## Conventions

- Module names: `Kube<Area>` (PascalCase), e.g. `KubeSchema`, `KubeAgents`.
- Test target: `<ModuleName>Tests`; suites use `@Suite("<area> …")`.
- Public API gets `///` doc comments naming the pillar it serves when relevant.
- No module reaches around the `ClusterClient` boundary to do live I/O.

For a full worked example (files, manifest diffs, pillar mapping) see
[`reference.md`](reference.md) — load it only when actually scaffolding.
