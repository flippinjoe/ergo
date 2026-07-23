# Ergo — project map for Claude

Ergo is a **Mac-first, agent-native Kubernetes client**. Read this file first,
then follow the read order below. Keep context small: pull in the next tier
**only when a task needs it**.

## Progressive disclosure — how this repo feeds context

This repo is organized in three disclosure tiers so a session ramps fast and
cheap. **Do not read everything.** Walk the chain only as far as the task needs:

1. **Tier 0 — this file (`CLAUDE.md`).** The map: stance, commands, layout.
2. **Tier 1 — indexes.** [`.claude/skills/README.md`](.claude/skills/README.md)
   (workflows) and [`.claude/knowledge/README.md`](.claude/knowledge/README.md)
   (stable reference). Scan these to find the one doc you need.
3. **Tier 2 — the specific skill or knowledge doc.** A `SKILL.md` gives steps;
   its heavier reference files load only when the steps say so.
4. **Tier 3 — the source.** Read code last, once you know where to look.

This note is itself part of the pattern: keep it terse, link out, never inline
what a Tier-1/2 doc already holds — so it survives context resets.

## Platform stance (decided — do not relitigate)

- **Mac-first.** macOS is the full product. iOS/iPadOS are a *future*,
  reduced/read-only companion. Only the macOS target ships now.
- Shared logic stays **platform-agnostic** in the SPM libraries so the future
  companion reuses it unchanged. UI-shell code lives in the app target.
- Swift 6 language mode, **strict concurrency = complete**, SwiftUI, current
  macOS SDK. Deployment target **macOS 15.0**.

## Three product pillars (module seams, not features yet)

1. **Relationships & time** — `ownerReferences` + `Events`.
2. **Schema & AI** — CRD → dynamic forms from OpenAPI.
3. **Auth & agents** — managed-cloud auth + local MCP exposure.

See [`.claude/knowledge/three-pillars.md`](.claude/knowledge/three-pillars.md)
for where each lives in code.

## Commands (one interface for humans and agents — see `Makefile`)

| Task | Command |
|------|---------|
| Verify toolchain + build vendored tools | `make bootstrap` |
| Generate `Ergo.xcodeproj` from `project.yml` | `make generate` |
| Build package + macOS app | `make build` |
| Run headless tests (xUnit output) | `make test` |
| Lint (swift-format, enforced) | `make lint` |
| Auto-format | `make format` |
| Build + launch the app | `make run` |
| Full pipeline | `make ci` |

Clean checkout to green: **`make bootstrap && make test`**.

## Layout

```
Package.swift            SPM libraries: KubeCore ◀ KubeClient ◀ KubeUI
Sources/KubeCore/        Pure value types (pillars 1 & 2). No I/O.
Sources/KubeClient/      ClusterClient boundary + FakeClusterClient + Fixtures/
Sources/KubeUI/          Shared SwiftUI: Nocturne theme, components, Explorer (concept 1a).
App/Ergo/                macOS app target (thin shell; @main lives here).
design/nocturne/         Vendored design system + concept mockups (visual source of truth).
Tests/                   Swift Testing suites (hermetic; no live cluster).
project.yml              XcodeGen manifest (source of truth; .xcodeproj is generated + gitignored).
Tools/                   Vendored, pinned XcodeGen (no Homebrew needed).
.claude/                 This harness (skills + knowledge).
```

## Workflow

- **Commit and push to `main` directly.** This repo does **not** use feature
  branches — do not create one unless the user explicitly asks. Push work to
  `main` as it lands.

## Guardrails

- **Never touch a real cluster.** No kubeconfig access in this repo. Tests and
  scaffolding use fixtures only. The `ClusterClient` boundary is read-only.
- Tooling is chosen for a **brew-free clean checkout**: XcodeGen is vendored via
  SPM; `swift-format` ships with the toolchain. See
  [SETUP.md](SETUP.md) for the full rationale.
