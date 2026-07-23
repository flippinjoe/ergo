# Design system — Nocturne

Ergo's UI follows **Nocturne**: a quiet, compact dark interface — near-neutral
blue-grey ground, medium-weight SF type, soft 8px radii, a single blurple accent
(`#9184D9`) used as a line and a glow, never a flood. The original web design
system and the four concept mockups are vendored under
[`design/nocturne/`](../../design/nocturne/) (`DESIGN-SYSTEM.md`, `styles.css`,
`concepts.html`, `concepts-preview.png`) — treat those as the visual source of
truth.

## Tokens — always go through `Nocturne`

`Sources/KubeUI/Theme/NocturneTheme.swift` is the single source of truth for
color, spacing, radius, and type. **Never hard-code a hex or a magic number in a
view** — take it from `Nocturne.*` (mirrors the web system's rule).

- Color: `Nocturne.bg / surface / surfaceRaised / text / accent / accent100…300`,
  status `statusOK / statusWarn / statusError / statusInfo`, `divider`,
  `muted(_:)`.
- `Nocturne.color(for: HealthStatus)` — the one place a domain `HealthStatus`
  becomes a color. `KubeCore` owns the meaning; `KubeUI` owns the color.
- Spacing `Nocturne.Space.s1…s8` (density 0.7×), radius `Nocturne.Radius.sm/md/lg`,
  type `Nocturne.Font.heading/body/mono/caption/…`.

## The one hard rule — glass vs. content

**Glass lives on the navigation layer only; content stays solid for
readability** (Apple HIG, and the mockups' stated rule).

- Navigation surfaces (sidebar, toolbars, log-dock header, future inspectors)
  use `.glassPanel()` (`Theme/Materials.swift`) — an ultra-thin material + hairline
  edge + lit top highlight. On macOS 26 the *native* `NavigationSplitView`
  sidebar and `.toolbar` already adopt Liquid Glass; `.glassPanel()` gives custom
  panels the same look with a material fallback on macOS 15.
- Content surfaces (tables, forms, the graph) use `.contentSurface()` or a solid
  fill — never glass.
- `WallBackground` is the dark blurple wash behind everything so translucent
  chrome has something to refract.

## Component patterns (reuse these; don't reinvent)

| Pattern | Where | Notes |
|---------|-------|-------|
| `StatusLabel` / `StatusDot` | `Components/StatusIndicator.swift` | Glowing dot + label; the pillar-1 health surface. |
| `Tag` | `Components/Tag.swift` | Neutral pill / accent outline. |
| `SidebarRow` + `SidebarView` | `Explorer/SidebarView.swift` | Icon + label + trailing count/status; accent-tinted selection. |
| `.glassPanel()` / `.contentSurface()` / `WallBackground` | `Theme/Materials.swift` | The material layer. |
| Data table | `Explorer/PodsTableView.swift` | Native `Table`; columns map to model fields. |

## Explorer behaviors

- **Sortable tables**: both `PodsTableView` and the generic `ResourceTableView`
  use SwiftUI `Table(sortOrder:)`. `TableSort`/`threeStateSort` add a
  three-state header cycle (ascending → descending → off) on top of the native
  two-state toggle. Columns sort on non-optional keys (e.g. Age sorts by the
  underlying `Date`, not the "3d" string).
- **Live updates**: `ExplorerModel` polls the current view every
  `pollInterval` (5s) via `load(showSpinner: false)` — silent, keeps selection,
  and keeps last-known data on a transient error. The poll restarts on
  cluster/kind/namespace change and stops on `onDisappear`. This is a seam for a
  future Kubernetes **watch** stream (HTTP/2 streaming GET `?watch=1`), which
  would replace polling behind the same `load`/rows update path. The toolbar
  "Live" pill signals it.
- **Toolbar**: namespace filter is leading (near the content it scopes); the
  Live indicator, search, and Ask are trailing. Cluster identity lives in the
  sidebar switcher, not the toolbar.

## Screen architecture

`ClusterExplorerView` (concept **1a**) is the main window: a `NavigationSplitView`
with the glass `SidebarView`, a unified `.toolbar`, and a detail pane that
switches on `ResourceKind`. The Pods pane is the table + `LogDockView`; other
kinds show a `ComingSoonPane` so navigation stays whole while features land.

State flows through `ExplorerModel` (`@MainActor @Observable`), which only ever
talks to the injected `ClusterClient` — so previews and the app are equally
hermetic.

## The four concepts → where they'll live

The mockups show four concepts; only 1a is built. The others map to the pillars
(see [`three-pillars.md`](three-pillars.md)) and get their own views later:

- **1a Cluster explorer** — built (`Explorer/`).
- **1b Pipeline / relationship graph + inspector** — pillar 1; future `KubeGraph` view.
- **1c CRD → dynamic form + live YAML** — pillar 2; future `KubeSchema` view.
- **1d Time machine (revision diff + scrubber)** — pillar 1 (time); future view.

## Icons

Mockups use Phosphor; the native app uses the SF Symbol equivalent (see
`ResourceKind.systemImage`). Keep that mapping when adding kinds.
