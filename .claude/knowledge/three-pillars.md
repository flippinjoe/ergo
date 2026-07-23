# The three product pillars

These are the product's identity as a power-user / agent-native Kubernetes
client. In the skeleton they exist as **clean module seams, not features** —
placeholders with the right shape so features land without re-architecting.

## 1. Relationships & time — `ownerReferences` + `Events`

Show how objects relate and what happened to them over time.

**Where in code:**
- `KubeCore/ObjectMeta.swift` → `OwnerReference` (the child→controller link),
  `ObjectReference`.
- `KubeCore/Resources.swift` → `EventRecord` (`involvedObject`, `reason`,
  `type`, `lastTimestamp`).
- Fixtures preserve `ownerReferences` and event `involvedObject`/timestamps so
  graph/timeline logic is testable now.
- **Future module:** `KubeGraph` (builds the owner/event graph). See the
  [add-feature-module](../skills/add-feature-module/SKILL.md) cheat-sheet.

## 2. Schema & AI — CRD → dynamic forms from OpenAPI

Read a CustomResourceDefinition's OpenAPI schema and generate a form; AI helps
fill/validate it.

**Where in code:**
- **Dynamic CRD listing is built** — `GroupVersionResource` + `DynamicResource`
  (KubeCore), `ClusterClient.listDynamic(_:namespace:)` (live via
  `/apis/{group}/{version}/{resource}`, with best-effort status derived from
  conditions / `status.health` / `status.phase`). The Certificates/Applications/
  ScaledObjects panes are generic dynamic lists (`ResourceKind.customResource`).
- `KubeCore/Resources.swift` → `CRDSummary` (CRD *definitions*, via `listCRDs`).
- `KubeClient/ClusterClient.swift` → `SchemaProviding` seam (`openAPISchema(for:)`),
  still unimplemented — the *form generation* step.
- **Next:** `KubeSchema` (OpenAPI node → dynamic form).

## 3. Auth & agents — managed-cloud auth + local MCP exposure

Authenticate to managed clusters, and expose Ergo's read operations to local
agents over MCP.

**Where in code:**
- **Cluster management is built** — adding & managing clusters, Azure sign-in
  discovery (mock now, live next). See
  [`clusters-and-auth.md`](clusters-and-auth.md): `ClusterConnection` /
  `ClusterSource` (KubeCore), `ClusterStore` + `AzureClusterService` (KubeClient),
  the add/manage UI (KubeUI/Clusters).
- `KubeClient/ClusterClient.swift` → `MCPExposing` protocol seam
  (`exposedToolNames`), deliberately unimplemented (agent exposure, later).
- The `ClusterClient` boundary is **read-only** — the safe surface an agent
  would drive.
- **Future modules:** `KubeAgents` (MCP exposure); a `KubeAuth` split if auth
  outgrows `KubeClient`.

## Why seams, not features

Each pillar has (a) a type or protocol already in the right module, and (b) a
named future module with a known dependency edge. That's enough to keep the
graph honest without building product before it's designed.
