# Cluster management & auth (pillar 3)

How Ergo manages the *set* of clusters and adds new ones. This is distinct from
`ClusterClient`, which talks to *one* cluster's API — a future step turns a
selected `ClusterConnection` into a `ClusterClient`.

## Model (KubeCore)

- `ClusterConnection` — a saved cluster's metadata: id, display name, `source`,
  `addedAt`, optional server/context. **Never holds secrets** (tokens/kubeconfig
  bytes go to the Keychain).
- `ClusterSource` — enum of providers: `.azure(AzureClusterRef)`,
  `.kubeconfig(KubeconfigRef)`, `.mock`. `identityKey` dedupes the same target;
  `kind` drives the icon/label. **New providers (GKE, EKS…) add a case here.**
- Azure discovery types: `AzureAccount`, `AzureSubscription`,
  `AzureManagedCluster` (with `.health`, `.ref`, `.connection(addedAt:)`).

## Boundaries (KubeClient)

- `ClusterStore` — persists connections. `InMemoryClusterStore` (tests/preview),
  `FileClusterStore` (on-device JSON under Application Support — nothing leaves
  the Mac).
- `AzureClusterService` — the discovery boundary: `signIn()` →
  `listSubscriptions()` → `listClusters(inSubscription:)`.
  - `FakeAzureClusterService` — fixture-backed, hermetic; the whole add-cluster
    UX is built and tested against it.
  - `LiveAzureClusterService` — **the agreed next step**, currently throwing
    `.notImplemented`. Its doc comment spells out the real flow (see below).

## UI (KubeUI/Clusters)

- `ClustersModel` (`@MainActor @Observable`) — load/add/remove/select, persists
  via `ClusterStore`, seeds one sample connection on first run.
- `AddClusterModel` — the step machine: choose source → (Azure) sign in →
  subscription → clusters.
- `AddClusterSheet` (source chooser + Azure flow + kubeconfig `.fileImporter`),
  `ClustersManagerView` (list/select/remove). Entered from the sidebar's cluster
  switcher menu (`SidebarView`).

## The live Azure path (next step)

Chosen approach: **built-in browser sign-in**, no app registration, nothing for
the user to configure — same as `az`/`kubelogin`.

1. `ASWebAuthenticationSession`, authorization-code + PKCE, against Microsoft's
   public client `04b07795-8ddb-461a-bbee-02f9e1bf7b46`. Cache tokens in the
   Keychain.
2. ARM `GET /subscriptions?api-version=2022-12-01`.
3. ARM `GET …/providers/Microsoft.ContainerService/managedClusters?api-version=2024-05-01`.
4. On add, `POST …/managedClusters/{name}/listClusterUserCredentials` for the
   kubeconfig — **user credentials only, never admin**; store in the Keychain.

Swapping is a one-line change at the app's composition root (`ErgoApp`):
`azureService: LiveAzureClusterService()`.

## Guardrail

The add flow only ever *reads* (discovers) and *saves* connection metadata +
credentials locally. Nothing here mutates or deletes anything in Azure or a
cluster.
