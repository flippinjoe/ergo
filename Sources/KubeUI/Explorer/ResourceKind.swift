import SwiftUI

/// The selectable resource kinds in the explorer sidebar. Grouped into the two
/// sections the design shows — Workloads and Custom Resources — the latter
/// standing in for pillar 2 (CRDs).
public enum ResourceKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case pods
    case deployments
    case statefulSets
    case certificates
    case applications
    case scaledObjects

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pods: "Pods"
        case .deployments: "Deployments"
        case .statefulSets: "StatefulSets"
        case .certificates: "Certificates"
        case .applications: "Applications"
        case .scaledObjects: "ScaledObjects"
        }
    }

    /// SF Symbol standing in for the mock's Phosphor icon.
    public var systemImage: String {
        switch self {
        case .pods: "shippingbox"
        case .deployments: "square.stack.3d.up"
        case .statefulSets: "cylinder.split.1x2"
        case .certificates: "checkmark.seal"
        case .applications: "arrow.triangle.branch"
        case .scaledObjects: "gauge.with.dots.needle.67percent"
        }
    }

    public enum Section: String, CaseIterable, Identifiable {
        case workloads = "Workloads"
        case customResources = "Custom Resources"

        public var id: String { rawValue }

        public var kinds: [ResourceKind] {
            switch self {
            case .workloads: [.pods, .deployments, .statefulSets]
            case .customResources: [.certificates, .applications, .scaledObjects]
            }
        }
    }
}
