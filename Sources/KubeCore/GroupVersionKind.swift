import Foundation

/// Identifies a Kubernetes API type: its group, version, and kind.
///
/// Example: `apps/v1` `Deployment` → `GroupVersionKind(group: "apps",
/// version: "v1", kind: "Deployment")`. Core-group types have an empty group.
public struct GroupVersionKind: Hashable, Sendable, Codable {
    public var group: String
    public var version: String
    public var kind: String

    public init(group: String, version: String, kind: String) {
        self.group = group
        self.version = version
        self.kind = kind
    }

    /// The `apiVersion` string as it appears on a manifest (`group/version`,
    /// or just `version` for the core group).
    public var apiVersion: String {
        group.isEmpty ? version : "\(group)/\(version)"
    }

    /// Parses an `apiVersion` + `kind` pair back into a `GroupVersionKind`.
    public init(apiVersion: String, kind: String) {
        let parts = apiVersion.split(separator: "/", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            self.init(group: parts[0], version: parts[1], kind: kind)
        } else {
            self.init(group: "", version: apiVersion, kind: kind)
        }
    }
}
