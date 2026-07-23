import SwiftUI

/// Nocturne's material layer. Follows the design's one hard HIG rule:
/// **glass lives on the navigation layer only — content (tables, lists, the
/// graph) stays solid for readability.**
///
/// On macOS 26+ the system chrome (`NavigationSplitView` sidebar, `.toolbar`)
/// adopts Liquid Glass automatically. These helpers give the *custom* panels
/// (log dock, inspectors, floating bars) the same translucent-glass treatment
/// with a graceful material fallback on macOS 15.
extension View {

    /// A translucent "glass" panel for navigation-layer surfaces: an ultra-thin
    /// material, a hairline edge, and a top inner highlight so it reads as a
    /// lit pane of glass.
    public func glassPanel(cornerRadius: CGFloat = Nocturne.Radius.lg) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius))
    }

    /// A solid content surface. Content never sits on glass.
    public func contentSurface(cornerRadius: CGFloat = Nocturne.Radius.lg) -> some View {
        background(Nocturne.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Nocturne.strokeSoft, lineWidth: 1)
            )
    }
}

private struct GlassPanel: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return
            content
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Nocturne.divider, lineWidth: 1))
            .overlay(alignment: .top) {
                // Inner top highlight — the lit edge of the glass.
                shape
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    .mask(
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
    }
}

/// The refractive desktop the glass bends light from — a dark blurple wash.
/// Sits at the very back of the window so translucent chrome has something to
/// pick up.
public struct WallBackground: View {
    public init() {}

    public var body: some View {
        Nocturne.bg
            .overlay(
                RadialGradient(
                    colors: [Color(hex: 0x9184D9, opacity: 0.34), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 620
                )
            )
            .overlay(
                RadialGradient(
                    colors: [Color(hex: 0x4A56B2, opacity: 0.30), .clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: 720
                )
            )
            .ignoresSafeArea()
    }
}
