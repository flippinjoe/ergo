# Ergo

A **Mac-first, agent-native Kubernetes client** for power users.

> Status: **project skeleton**. Clean, buildable, testable structure + a Claude
> working harness. No product features yet — just the seams they'll grow from.

## Quick start

```bash
make bootstrap && make test      # green tests, no cluster, no Homebrew
make generate && make build      # generate + build the macOS app
make run                         # launch it
```

See **[SETUP.md](SETUP.md)** for the full layout, requirements, and the tooling
rationale.

## What's here

- **SPM libraries** with a clean, acyclic graph: `KubeUI ▶ KubeClient ▶ KubeCore`.
- A **macOS app target** (`App/Ergo`) generated into `Ergo.xcodeproj` from a
  diffable [`project.yml`](project.yml) via vendored XcodeGen.
- A **hermetic test harness**: a `ClusterClient` protocol boundary + a
  fixture-backed `FakeClusterClient`. Tests never touch a real cluster.
- A **Claude harness** under [`.claude/`](.claude/) with progressive disclosure
  — start at [CLAUDE.md](CLAUDE.md).

## Three product pillars (module seams, not features yet)

1. **Relationships & time** — `ownerReferences` + Events.
2. **Schema & AI** — CRD → dynamic forms from OpenAPI.
3. **Auth & agents** — managed-cloud auth + local MCP exposure.

Details: [`.claude/knowledge/three-pillars.md`](.claude/knowledge/three-pillars.md).

## Platform stance

macOS is the full product now. iOS/iPadOS are a future reduced/read-only
companion; shared logic is kept platform-agnostic in the SPM libraries so it can
be reused unchanged.
