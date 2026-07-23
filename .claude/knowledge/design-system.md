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

## Resource catalog (API discovery)

The sidebar is **not** hardcoded — it's built from the cluster's own API
discovery, so it shows everything that cluster serves at the versions it serves
(handles 1.26 vs 1.28 automatically):

- `ClusterClient.discoverAPIResources()` → `[APIResource]` (KubeCore). Live does
  classic discovery: `/api/v1` + `/apis` (groups) + each group's **preferred
  version** `/apis/{group}/{version}`, in parallel, keeping listable non-
  subresources.
- `ResourceCatalog.sections(from:)` groups **strictly by API group** (Core
  first, then well-known groups, then the rest alphabetical), the user's chosen
  grouping. `APIResource.displayName` humanizes+pluralizes the kind
  ("PersistentVolumeClaim" → "Persistent Volume Claims").
- Every resource is watched/listed/inspected **generically** by its
  `GroupVersionResource`. Pods keep the rich typed table; everything else renders
  via `DynamicResource` (best-effort status + a workload ready/desired detail).
  Adding coverage for a new kind needs no code — discovery finds it.

## Explorer behaviors

- **Sortable tables**: both `PodsTableView` and the generic `ResourceTableView`
  use SwiftUI `Table(sortOrder:)`. `TableSort`/`threeStateSort` add a
  three-state header cycle (ascending → descending → off) on top of the native
  two-state toggle. Columns sort on non-optional keys (e.g. Age sorts by the
  underlying `Date`, not the "3d" string).
- **Live updates (watch)**: `ExplorerModel` **watches** the selected kind via
  `ClusterClient.watch(_:namespace:)` — the Kubernetes list+watch protocol
  (`LiveKubernetesClient.runWatch`: LIST for the initial snapshot +
  resourceVersion, then a streaming `?watch=1` GET yielding ADDED/MODIFIED/
  DELETED/BOOKMARK events, reconnecting on close and re-listing on 410). Each
  snapshot is decoded (typed for pods/deployments/statefulsets, dynamic for
  CRDs) and sorted stably. The watch restarts on cluster/kind/namespace change
  and stops on `onDisappear`. The toolbar "Live" pill signals it.
- **Inspector (generic detail)**: selecting a row opens a glass `InspectorView`
  — the *same* detail for every kind. Metadata (namespace, age, UID, labels),
  **annotations**, **owner references**, recent **events**, and a **Manifest**
  disclosure (pretty-printed object). Built from the raw watch object's
  metadata + full JSON, so it works for any resource.
- **Collapsible sidebar**: each API-group section collapses; sections are
  collapsed by default (`ExplorerModel.expandedGroups`), and the section holding
  the current selection auto-expands. (Future: user-pinned/curated sections and
  per-cluster reordering.)
- **Schema descriptions**: list headers show the resource type's description
  from the cluster's **OpenAPI v3** schema
  (`ClusterClient.resourceDescriptions(group:version:)`, cached per
  group-version, fetched lazily on selection).
- **Toolbar**: the namespace filter is leading (near the content it scopes);
  the Live indicator, search, and Ask are trailing. Cluster identity lives in
  the sidebar switcher, not the toolbar.
- **Namespace filter (multi-select)**: a popover (`NamespaceFilterView`) with an
  "All namespaces" checkbox + a checkbox per namespace (Lens-style), backed by
  `ExplorerModel.selectedNamespaces: Set<String>` (empty = all). Filtering is
  **client-side** over the cluster-wide watch (`applyFilter` / the pure
  `matches(namespace:selection:)`), so toggling is instant with no stream
  restart.
- **Log streaming**: selecting a pod streams its logs into the dock via
  `ClusterClient.streamLogs` (live: `GET …/pods/{name}/log?follow=true` consumed
  line-by-line through `StreamingHTTPClient.streamLines` over the CA-pinned
  session). `ExplorerModel` owns the stream lifecycle (restart on pod change,
  cancel on leave); `LogLine` parses timestamp + severity; the dock auto-scrolls.

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
