import KubeClient
import KubeCore
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

    /// For custom-resource kinds, the GroupVersionResource to list. `nil` for
    /// built-in kinds that have a typed client method.
    var customResource: GroupVersionResource? {
        switch self {
        case .certificates:
            GroupVersionResource(
                group: "cert-manager.io", version: "v1", resource: "certificates", namespaced: true)
        case .applications:
            GroupVersionResource(
                group: "argoproj.io", version: "v1alpha1", resource: "applications", namespaced: true)
        case .scaledObjects:
            GroupVersionResource(
                group: "keda.sh", version: "v1alpha1", resource: "scaledobjects", namespaced: true)
        case .pods, .deployments, .statefulSets:
            nil
        }
    }

    /// Title of the kind-specific detail column, if any.
    var detailColumnTitle: String? {
        switch self {
        case .deployments, .statefulSets: "Ready"
        default: nil
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
