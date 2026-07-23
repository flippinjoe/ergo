# Module boundaries

The dependency graph is **acyclic and one-directional**. Keeping it that way is
what makes the domain reusable by a future iOS/iPadOS companion and keeps tests
fast.

```
KubeUI  ──▶  KubeClient  ──▶  KubeCore
  ▲                              ▲
  └────────── App/Ergo ──────────┘   (app depends on all three)
```

## What each module may contain / depend on

| Module | Contains | May depend on | Must NOT |
|--------|----------|---------------|----------|
| `KubeCore` | Pure value types: `GroupVersionKind`, `ObjectMeta`, `OwnerReference`, `Pod`, `Deployment`, `EventRecord`, `CRDSummary`. | (nothing but Foundation) | No I/O, no networking, no SwiftUI, no platform APIs. |
| `KubeClient` | The `ClusterClient` boundary, `FakeClusterClient`, JSON `Fixtures/`, seam protocols (`SchemaProviding`, `MCPExposing`). | `KubeCore` | No SwiftUI. No live-cluster/mutating calls in the skeleton. |
| `KubeUI` | Shared SwiftUI views, driven by a `ClusterClient`. | `KubeClient`, `KubeCore` | No macOS-only API without an availability guard (keep it portable). |
| `App/Ergo` | `@main`, scenes, windows, macOS-shell wiring. | all three libraries | No domain logic that a companion app would also need — push that down. |

## Rules

- **One direction only.** Never introduce a back-edge (e.g. `KubeCore`
  importing `KubeClient`). If you feel the pull, the type belongs lower.
- **The boundary is sacred.** Everything above `KubeClient` talks to the cluster
  *only* through the `ClusterClient` protocol. That's what keeps tests hermetic
  and makes the live client a drop-in later.
- **New modules slot in, never cycle.** See the
  [`add-feature-module`](../skills/add-feature-module/SKILL.md) skill.
- **Strict settings are uniform.** Every target uses the `.strict` swiftSettings
  helper in `Package.swift` (Swift 6 mode + complete concurrency).
