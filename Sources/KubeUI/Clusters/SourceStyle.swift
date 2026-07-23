import KubeCore
import SwiftUI

extension ClusterSource.Kind {
    /// SF Symbol for this provider.
    var systemImage: String {
        switch self {
        case .azure: "cloud"
        case .kubeconfig: "doc.text"
        case .mock: "cube"
        }
    }
}

extension ClusterConnection {
    /// One-line subtitle for the manager / switcher.
    var subtitle: String {
        switch source {
        case .azure(let ref):
            [ref.resourceGroup, ref.location].compactMap { $0 }.joined(separator: " · ")
        case .kubeconfig(let ref):
            ref.contextName
        case .mock:
            "sample cluster"
        }
    }
}
