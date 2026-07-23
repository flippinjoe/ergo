import Foundation

/// A resource type the cluster serves, from API discovery. This is what makes
/// the sidebar reflect *this* cluster's actual API surface — including its
/// version choices (1.26 vs 1.28) and any CRDs.
public struct APIResource: Sendable, Hashable, Identifiable, Codable {
    public var group: String  // "" for the core group
    public var version: String
    /// Plural, lowercase name (e.g. `persistentvolumeclaims`).
    public var resource: String
    public var kind: String
    public var namespaced: Bool
    public var shortNames: [String]

    public init(
        group: String, version: String, resource: String, kind: String, namespaced: Bool,
        shortNames: [String] = []
    ) {
        self.group = group
        self.version = version
        self.resource = resource
        self.kind = kind
        self.namespaced = namespaced
        self.shortNames = shortNames
    }

    /// Stable identity (group/version/resource).
    public var id: String {
        group.isEmpty ? "\(version)/\(resource)" : "\(group)/\(version)/\(resource)"
    }

    public var gvr: GroupVersionResource {
        GroupVersionResource(group: group, version: version, resource: resource, namespaced: namespaced)
    }

    /// The core `v1` group's display name.
    public var groupTitle: String { group.isEmpty ? "Core" : group }

    /// A friendly, pluralized display name derived from the kind
    /// (e.g. `PersistentVolumeClaim` → "Persistent Volume Claims").
    public var displayName: String {
        let words = Self.humanize(kind)
        guard let last = words.last else { return kind }
        // Some kinds are already plural (e.g. `Endpoints`, whose resource is
        // `endpoints`); don't double-pluralize those.
        let alreadyPlural = resource == kind.lowercased()
        let lastWord = alreadyPlural ? last : Self.pluralize(last)
        return (words.dropLast() + [lastWord]).joined(separator: " ")
    }

    /// Splits a PascalCase kind into words, keeping acronym runs together
    /// ("HTTPRoute" → ["HTTP", "Route"]).
    static func humanize(_ kind: String) -> [String] {
        var words: [String] = []
        var current = ""
        let chars = Array(kind)
        for (index, char) in chars.enumerated() {
            let prev = index > 0 ? chars[index - 1] : nil
            let next = index + 1 < chars.count ? chars[index + 1] : nil
            let boundary =
                char.isUppercase
                && ((prev?.isLowercase ?? false)
                    || (prev?.isUppercase == true && (next?.isLowercase ?? false)))
            if boundary, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(char)
        }
        if !current.isEmpty { words.append(current) }
        return words.isEmpty ? [kind] : words
    }

    static func pluralize(_ word: String) -> String {
        let lower = word.lowercased()
        if lower.hasSuffix("y"), let secondLast = word.dropLast().last,
            !"aeiou".contains(secondLast.lowercased())
        {
            return word.dropLast() + "ies"
        }
        if lower.hasSuffix("s") || lower.hasSuffix("x") || lower.hasSuffix("z")
            || lower.hasSuffix("ch") || lower.hasSuffix("sh")
        {
            return word + "es"
        }
        return word + "s"
    }
}
