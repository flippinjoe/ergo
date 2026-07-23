# Setup & layout

Ergo is a **Mac-first, agent-native Kubernetes client**. This document gets a
new contributor (human or agent) to a green build and explains the tooling
choices.

## Get to green

```bash
git clone git@github.com:flippinjoe/ergo.git
cd ergo
make bootstrap && make test      # green tests, no cluster, no Homebrew
make generate && make build      # generate + build the macOS app
make run                         # launch it
```

`make bootstrap` verifies the toolchain and builds the vendored project
generator; it **fails loudly** if `swift`/`xcodebuild` are missing or too old.

## Requirements

- **Xcode 26 / Swift 6.3 toolchain** (Swift 6 language mode, strict concurrency
  complete). `swift-format` ships with this toolchain — nothing to install.
- macOS deployment target **15.0**.
- **No Homebrew required.** The one external build tool (XcodeGen) is vendored.

## Layout

```
Package.swift            SPM libraries: KubeCore ◀ KubeClient ◀ KubeUI
Sources/
  KubeCore/              Pure value types (pillars 1 & 2). No I/O, no platform deps.
  KubeClient/            ClusterClient boundary + FakeClusterClient
    Fixtures/            Committed JSON fixtures (hermetic test/preview data)
  KubeUI/                Shared SwiftUI, platform-agnostic.
App/Ergo/                macOS app target — thin shell, @main lives here.
Tests/
  KubeCoreTests/         Swift Testing smoke suite
  KubeClientTests/       Fixture-decode suite (hermetic)
project.yml              XcodeGen manifest — source of truth for the app project.
Tools/                   Vendored, pinned XcodeGen (built via `swift run`).
Makefile                 One command surface for humans + agents.
.claude/                 Progressive-disclosure harness (skills + knowledge).
.github/workflows/ci.yml generate → build → test → lint on macOS.
```

The generated `Ergo.xcodeproj` is **gitignored**; regenerate with
`make generate`. Never hand-edit it — change `project.yml`.

## Make targets

| Target | Does |
|--------|------|
| `make bootstrap` | Verify toolchain, build vendored XcodeGen (fails loudly if missing). |
| `make generate` | Generate `Ergo.xcodeproj` from `project.yml`. |
| `make build` | `swift build` the package + `xcodebuild` the app. |
| `make test` | Headless `swift test` with xUnit output to `TestResults/`. |
| `make lint` | `swift format lint --strict` (enforced); SwiftLint if installed. |
| `make format` | Auto-format in place. |
| `make run` | Build + launch the app. |
| `make ci` | bootstrap → generate → build → test → lint. |
| `make clean` | Remove build artifacts + the generated project. |

## Tooling choices (and why)

- **XcodeGen over Tuist** — one diffable YAML manifest (`project.yml`), no Swift
  DSL or background daemon. Right weight for a skeleton, and the checked-in
  source of truth is text, not a binary `pbxproj`.
- **XcodeGen vendored via SPM** (`Tools/Package.swift`, pinned `exact: 2.46.0`)
  — the target machine has no Homebrew, so `make bootstrap` builds it with
  `swift build` and it runs via `swift run`. `Tools/Package.resolved` is
  committed to lock the whole tool dependency graph. A clean checkout needs only
  the Xcode toolchain.
- **Swift Testing** (bundled) as the primary framework — no dependency added.
  `swift test` is the headless, machine-readable, green source of truth.
- **swift-format** (bundled) is the enforced formatter/linter. **SwiftLint** is
  supported via `.swiftlint.yml` but optional: it has no Homebrew-free install
  path here, so `make lint` runs it only if the binary is present and never
  fails the build over its absence.
- **No `.xcworkspace`** — a single app project referencing one local SPM package
  doesn't benefit from one. Add a workspace only if a second project appears.

## Guardrails

- **Nothing in this repo touches a real cluster.** No kubeconfig access; the
  `ClusterClient` boundary is read-only; all test/preview data comes from
  committed fixtures. See [`.claude/knowledge/coding-conventions.md`](.claude/knowledge/coding-conventions.md).

## Working with Claude

Start at [`CLAUDE.md`](CLAUDE.md); it explains the progressive-disclosure tiers
and links to `.claude/skills/` (workflows) and `.claude/knowledge/` (reference).
