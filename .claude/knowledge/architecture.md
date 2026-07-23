# Architecture overview

Ergo is a **Mac-first, agent-native Kubernetes client**. Only the macOS target
ships now; iOS/iPadOS are a future reduced/read-only companion. The structure
exists to make that future cheap.

## Shape

```
┌───────────────────────────────┐
│ App/Ergo  (macOS app target)  │  @main, window/scene, wiring only
│   depends on ▼                │
├───────────────────────────────┤
│ KubeUI    (SwiftUI, shared)   │  platform-agnostic views
│   depends on ▼                │
│ KubeClient (API boundary)     │  ClusterClient protocol + FakeClusterClient + Fixtures
│   depends on ▼                │
│ KubeCore  (pure value types)  │  models, no I/O, no platform deps
└───────────────────────────────┘
```

**Why the logic lives in SPM libraries, not the app target:** everything below
the app shell is platform-agnostic, so the future iOS/iPadOS companion imports
the same `KubeCore`/`KubeClient`/`KubeUI` unchanged. The app target holds only
what's genuinely macOS-shell-specific.

## Generator-driven project

The `.xcodeproj` is **generated** from [`project.yml`](../../project.yml) by
XcodeGen and is **gitignored**. The checked-in source of truth is YAML, so the
project is diffable and merge-friendly — no binary `pbxproj` churn.

- **Why XcodeGen over Tuist:** one declarative YAML manifest, no Swift DSL or
  daemon to learn, minimal moving parts for a skeleton.
- **Why vendored:** there's no Homebrew on the target machine, so XcodeGen is
  pinned in [`Tools/Package.swift`](../../Tools/Package.swift) and run via
  `swift run`. A clean checkout needs only the Xcode toolchain.

## Testing backend

`KubeClient` ships JSON fixtures as a resource and a `FakeClusterClient` that
decodes them. Tests and SwiftUI previews use it, so the whole suite is
**hermetic**: no network, no kubeconfig, no way to touch a real cluster.

## Toolchain (pinned)

- Swift 6.3 toolchain / Xcode 26, Swift **6 language mode**, strict concurrency
  **complete**.
- Deployment target **macOS 15.0** (built against the current SDK).
- `swift-format` (bundled with the toolchain) is the enforced formatter/linter.

See [SETUP.md](../../SETUP.md) for the full tooling rationale and versions.
