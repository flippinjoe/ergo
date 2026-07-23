# add-feature-module — worked example (Tier 2 reference)

Load this only when you're actually scaffolding a module. It walks through
adding a `KubeSchema` module for **pillar 2 (schema & AI)**.

## 1. Source

`Sources/KubeSchema/SchemaForm.swift`:

```swift
import KubeCore

/// Pillar 2 (schema & AI): turns an OpenAPI schema node into a description a
/// dynamic form can render. Pure transform — no I/O.
public struct SchemaForm: Sendable {
    public let fields: [Field]
    public struct Field: Sendable, Hashable {
        public let name: String
        public let type: String
        public let required: Bool
    }
    public init(fields: [Field]) { self.fields = fields }
}
```

## 2. `Package.swift` — add target, product, and test target

```swift
// products:
.library(name: "KubeSchema", targets: ["KubeSchema"]),

// targets:
.target(
    name: "KubeSchema",
    dependencies: ["KubeCore"],
    swiftSettings: .strict
),
.testTarget(
    name: "KubeSchemaTests",
    dependencies: ["KubeSchema"],
    swiftSettings: .strict
),
```

The `.strict` helper at the bottom of `Package.swift` applies Swift 6 mode +
complete concurrency. Reuse it; don't redefine settings inline.

## 3. `project.yml` — only if the app must link it

```yaml
dependencies:
  - package: Ergo
    product: KubeSchema
```

Then `make generate`.

## 4. Test

`Tests/KubeSchemaTests/SchemaFormTests.swift`:

```swift
import Testing
@testable import KubeSchema

@Suite("schema form")
struct SchemaFormTests {
    @Test("holds its fields")
    func fields() {
        let form = SchemaForm(fields: [.init(name: "replicas", type: "integer", required: true)])
        #expect(form.fields.count == 1)
    }
}
```

## 5. Verify

```
make build && make test && make lint
```

## Pillar → module cheat-sheet

| Pillar | Likely module | Depends on |
|--------|---------------|-----------|
| 1 relationships & time | `KubeGraph` (owner/event graph building) | `KubeCore` |
| 2 schema & AI | `KubeSchema` (OpenAPI → form model) | `KubeCore` |
| 3 auth & agents | `KubeAgents` (MCP exposure), `KubeAuth` | `KubeClient` |
