import Testing

@testable import KubeCore

/// Smoke tests: prove the module graph compiles, links, and that the core
/// value types behave. If these run, `KubeCore` is wired correctly.
@Suite("KubeCore smoke")
struct SmokeTests {
    @Test("GroupVersionKind renders apiVersion for grouped types")
    func groupedApiVersion() {
        let gvk = GroupVersionKind(group: "apps", version: "v1", kind: "Deployment")
        #expect(gvk.apiVersion == "apps/v1")
    }

    @Test("GroupVersionKind renders apiVersion for the core group")
    func coreApiVersion() {
        let gvk = GroupVersionKind(group: "", version: "v1", kind: "Pod")
        #expect(gvk.apiVersion == "v1")
    }

    @Test("apiVersion round-trips through the parsing initializer")
    func apiVersionRoundTrip() {
        let parsed = GroupVersionKind(apiVersion: "apps/v1", kind: "Deployment")
        #expect(parsed == GroupVersionKind(group: "apps", version: "v1", kind: "Deployment"))
    }
}
