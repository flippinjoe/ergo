import Foundation

/// A coarse health bucket shared across the app. Value types map their
/// Kubernetes-specific status strings into this so the UI has one thing to
/// switch on for color (status dot, badges) and future logic can reason about
/// health without re-parsing strings.
///
/// This is intentionally domain-level, not UI-level: `KubeCore` owns the
/// meaning; `KubeUI` owns the color it maps to.
public enum HealthStatus: String, Sendable, Codable, CaseIterable {
    case ok
    case warning
    case error
    case info
    case unknown

    /// Maps common Kubernetes phases, conditions, and container waiting reasons
    /// into a bucket. Unknown strings fall through to `.unknown` rather than
    /// guessing.
    public init(kubernetesStatus status: String) {
        switch status {
        case "Running", "Succeeded", "Active", "Ready", "Available",
            "Approved", "Synced", "Healthy", "Bound", "Completed":
            self = .ok
        case "Pending", "ContainerCreating", "PodInitializing", "Progressing",
            "NotReady", "Not ready", "Terminating", "Unknown":
            self = .warning
        case "Failed", "Error", "CrashLoopBackOff", "ImagePullBackOff",
            "ErrImagePull", "Failing", "OOMKilled", "Evicted", "BackOff":
            self = .error
        default:
            self = .unknown
        }
    }
}
