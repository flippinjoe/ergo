# Coding conventions

## Language & concurrency

- **Swift 6 language mode**, strict concurrency **complete**, everywhere. Set
  once via the `.strict` helper in `Package.swift` and the `strict` setting
  group in `project.yml` — don't override per file.
- Prefer `async`/`await` and structured concurrency. Types crossing concurrency
  boundaries are `Sendable`; value types here are `Sendable` by default.
- `ExistentialAny` upcoming feature is on: write `any ClusterClient`, not bare
  `ClusterClient`, for existentials.

## Naming

- Modules: `Kube<Area>` (PascalCase) — `KubeCore`, `KubeClient`, `KubeUI`.
- Test targets: `<ModuleName>Tests`. Test files: `<Thing>Tests.swift`.
- Types PascalCase, members lowerCamelCase (enforced by swift-format).
- Model fields mirror the Kubernetes JSON keys so `Codable` needs no custom
  `CodingKeys` where avoidable.

## Formatting & linting

- `swift-format` (bundled) is the **enforced** authority. Config: `.swift-format`
  (line length 110, 4-space indent, ordered imports). Run `make format` before
  committing; `make lint` (`swift format lint --strict`) gates CI.
- `.swiftlint.yml` is provided for teams with SwiftLint installed; it's optional
  and runs only if the binary is present.

## Testing

- **Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`, `#require`).
  Use XCTest only if a dependency forces it.
- Tests are **hermetic**: data via fixtures through `FakeClusterClient`. No
  network, no kubeconfig, no real cluster — this is a hard guardrail, not a
  preference.
- Name suites and tests in plain language (`@Test("Namespace filtering is
  applied to fixtures")`) so `--filter` and failure output read well.

## Documentation

- Public API gets `///` doc comments. When a type/protocol serves one of the
  three pillars, name the pillar in the comment (see existing `KubeCore` and
  `KubeClient` sources for the style).
- Keep comments about *why*, not *what the code plainly says*.

## Safety

- Nothing in this repo may read a real kubeconfig or mutate a real cluster. The
  `ClusterClient` boundary is read-only in the skeleton by design.
