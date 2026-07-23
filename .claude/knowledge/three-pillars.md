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
- `KubeCore/Resources.swift` → `CRDSummary` (thin descriptor).
- `KubeClient/ClusterClient.swift` → `SchemaProviding` protocol seam
  (`openAPISchema(for:)`), deliberately unimplemented.
- **Future module:** `KubeSchema` (OpenAPI node → form model).

## 3. Auth & agents — managed-cloud auth + local MCP exposure

Authenticate to managed clusters, and expose Ergo's read operations to local
agents over MCP.

**Where in code:**
- `KubeClient/ClusterClient.swift` → `MCPExposing` protocol seam
  (`exposedToolNames`), deliberately unimplemented.
- The `ClusterClient` boundary is **read-only** in the skeleton — the safe
  surface an agent would drive.
- **Future modules:** `KubeAuth`, `KubeAgents`.

## Why seams, not features

Each pillar has (a) a type or protocol already in the right module, and (b) a
named future module with a known dependency edge. That's enough to keep the
graph honest without building product before it's designed.
