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
  - `FakeAzureClusterService` — fixture-backed, hermetic; used by previews and
    the SwiftUI `#Preview` default.
  - `LiveAzureClusterService` (**implemented**, `Azure/`) — real interactive
    sign-in + ARM discovery. Every side effect is injected — `WebAuthenticator`
    (browser), `HTTPClient` (network), `TokenStore` (Keychain) — so the whole
    path is unit-tested with fakes (`AzureAuthTests`). Supporting pieces in
    `KubeClient/Azure/`: `PKCE`, `AzureOAuth` (config + authorize-URL builder +
    `AzureTokenClient`), `AzureARMClient`, `TokenStore` (+ `KeychainTokenStore`),
    `WebAuthenticator`.
  - `SystemWebAuthenticator` (App target) — the concrete browser step: opens the
    system browser and catches the redirect on a loopback listener (needs the
    `com.apple.security.network.server` entitlement).

## UI (KubeUI/Clusters)

- `ClustersModel` (`@MainActor @Observable`) — load/add/remove/select, persists
  via `ClusterStore`, seeds one sample connection on first run.
- `AddClusterModel` — the step machine: choose source → (Azure) sign in →
  subscription → clusters.
- `AddClusterSheet` (source chooser + Azure flow + kubeconfig `.fileImporter`),
  `ClustersManagerView` (list/select/remove). Entered from the sidebar's cluster
  switcher menu (`SidebarView`).

## The live Azure path (implemented)

Chosen approach: **built-in browser sign-in**, no app registration, nothing for
the user to configure — same as `az`/`kubelogin`. Wired at the app root in
`ErgoApp` (`LiveAzureClusterService(webAuthenticator: SystemWebAuthenticator(),
tokenStore: KeychainTokenStore())`). The per-cluster pod client is still the demo
`FakeClusterClient` — the live `ClusterClient` (and kubeconfig fetch via
`listClusterUserCredentials`) is the next step.

1. **[done]** System browser + loopback redirect, authorization-code + PKCE,
   against public client `04b07795-8ddb-461a-bbee-02f9e1bf7b46`. Tokens cached in
   the Keychain, auto-refreshed.
2. **[done]** ARM `GET /subscriptions?api-version=2022-12-01`.
3. **[done]** ARM `GET …/managedClusters?api-version=2024-05-01`.
4. **[done]** On select, `POST …/managedClusters/{name}/listClusterUserCredentials`
   for the kubeconfig — **user credentials only, never admin**. It's parsed
   (`Kubeconfig`, Yams); a `LiveKubernetesClient` is built with CA-pinned TLS
   (`KubernetesHTTPClient`) and a `ClusterTokenProvider` — for Entra/`kubelogin`
   configs an `AzureExecTokenProvider` mints an AKS-scoped token from the refresh
   token; embedded-token configs use it directly. `DefaultClusterClientFactory`
   wires this per selected connection.

**Not yet:** client-certificate kubeconfigs (clear error), live log streaming
(honest placeholder), and caching the kubeconfig (re-fetched per selection).

## Guardrail

The add flow only ever *reads* (discovers) and *saves* connection metadata +
credentials locally. Nothing here mutates or deletes anything in Azure or a
cluster.
