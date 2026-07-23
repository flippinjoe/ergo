import KubeCore
import SwiftUI

/// The glowing status dot + label used everywhere health is shown (the `.st`
/// pattern from the design). Pillar 1 lives here: a `HealthStatus` becomes a
/// color, a dot, and a glow.
public struct StatusLabel: View {
    private let text: String
    private let health: HealthStatus

    public init(_ text: String, health: HealthStatus) {
        self.text = text
        self.health = health
    }

    /// Convenience: label text *is* the status string, health derived from it.
    public init(status: String) {
        self.init(status, health: HealthStatus(kubernetesStatus: status))
    }

    public var body: some View {
        HStack(spacing: Nocturne.Space.s2) {
            StatusDot(health: health)
            Text(text)
                .font(Nocturne.Font.bodyEmphasis)
                .foregroundStyle(Nocturne.color(for: health))
        }
    }
}

/// Just the dot — a filled circle with a soft same-color glow.
public struct StatusDot: View {
    private let health: HealthStatus
    private let size: CGFloat

    public init(health: HealthStatus, size: CGFloat = 7) {
        self.health = health
        self.size = size
    }

    public var body: some View {
        let color = Nocturne.color(for: health)
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.8), radius: 4)
    }
}
