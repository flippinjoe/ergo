import Testing

@testable import KubeUI

@Suite("Namespace filter")
struct NamespaceFilterTests {
    @Test("Empty selection matches every namespace")
    func emptyMatchesAll() {
        #expect(ExplorerModel.matches(namespace: "prod", selection: []))
        #expect(ExplorerModel.matches(namespace: nil, selection: []))
    }

    @Test("A non-empty selection matches only members")
    func membership() {
        let selection: Set<String> = ["prod", "staging"]
        #expect(ExplorerModel.matches(namespace: "prod", selection: selection))
        #expect(ExplorerModel.matches(namespace: "staging", selection: selection))
        #expect(!ExplorerModel.matches(namespace: "dev", selection: selection))
        // A resource with no namespace is excluded when a filter is active.
        #expect(!ExplorerModel.matches(namespace: nil, selection: selection))
    }
}
