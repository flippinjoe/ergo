# Skill: add-cluster-provider

**Description:** Add a new cluster source (GKE, EKS, Rancher, raw endpoint…) to
the add/manage-clusters flow.

**Trigger:** "add support for <provider> clusters", extending the Add Cluster
sheet with a new source.

Background: [`../../knowledge/clusters-and-auth.md`](../../knowledge/clusters-and-auth.md).

## Steps

1. **Model (KubeCore).** Add a case to `ClusterSource`
   (`Sources/KubeCore/ClusterConnection.swift`) — e.g. `.gke(GKEClusterRef)` —
   with its `Ref` type, and extend `kind`, `identityKey`, and the `Kind` enum
   (title). Add discovery types if needed (mirror `Azure.swift`).
2. **Boundary + mock (KubeClient).** Define the provider's discovery protocol
   (mirror `AzureClusterService`), a `Fake<Provider>Service` backed by JSON
   fixtures in `Sources/KubeClient/Fixtures/`, and a `Live<Provider>Service`
   stub documenting the real flow. Add the fixture-decode + scoping tests
   (mirror `AzureServiceTests`).
3. **UI (KubeUI/Clusters).** Add a `SourceCard` in `AddClusterSheet` and the
   provider's steps in `AddClusterModel`; map the new `Kind` in
   `SourceStyle.swift` (icon + subtitle).
4. **Wire** the mock at the app composition root (`App/Ergo/ErgoApp.swift`),
   swap to live later.
5. Verify: `make build && make test && make lint`, then `make run` and walk the
   flow.

## Conventions

- Discovery is **read-only**; only connection metadata + credentials are saved,
  and credentials go to the Keychain, never into `ClusterConnection`.
- Keep everything hermetic in tests — no live provider calls.
- Prefer built-in browser sign-in (no app registration) where the provider
  supports it, matching the Azure approach.
