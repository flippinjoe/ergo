import KubeCore
import SwiftUI

/// The **Nocturne** design system, expressed as SwiftUI tokens.
///
/// Nocturne is a quiet, compact dark interface: a near-neutral blue-grey
/// ground, medium-weight type, soft 8px radii, and a single blurple accent used
/// as a line and a glow rather than a flood. This enum is the source of truth
/// for color, spacing, radius, and type — views take values from here and never
/// hard-code a hex or a magic number (mirrors the web design system's rule).
public enum Nocturne {

    // MARK: Color — ground & text

    /// Window ground (`--color-bg`).
    public static let bg = Color(hex: 0x161826)
    /// Solid content surface — tables, forms, the graph (`--color-surface`).
    public static let surface = Color(hex: 0x191B27)
    /// A slightly raised solid surface (node cards, log dock rows).
    public static let surfaceRaised = Color(hex: 0x20222F)
    /// Primary text (`--color-text`).
    public static let text = Color(hex: 0xE9E9ED)

    // MARK: Color — accent (the product blurple)

    public static let accent = Color(hex: 0x9184D9)
    public static let accent100 = Color(hex: 0xF5F4FF)
    public static let accent200 = Color(hex: 0xE7E5FE)
    public static let accent300 = Color(hex: 0xD2CEFD)

    // MARK: Color — status (drive the glowing dot)

    public static let statusOK = Color(hex: 0x5FB489)
    public static let statusWarn = Color(hex: 0xE0B464)
    public static let statusError = Color(hex: 0xE08585)
    public static let statusInfo = accent200

    /// The color a `HealthStatus` maps to. `KubeCore` owns the meaning; this is
    /// where the meaning becomes a color.
    public static func color(for health: HealthStatus) -> Color {
        switch health {
        case .ok: statusOK
        case .warning: statusWarn
        case .error: statusError
        case .info: statusInfo
        case .unknown: text.opacity(0.5)
        }
    }

    // MARK: Color — lines

    /// Hairline divider/stroke (`--color-divider`, white @ 16%).
    public static let divider = Color.white.opacity(0.10)
    public static let strokeSoft = Color.white.opacity(0.06)

    /// Text at reduced emphasis. Nocturne builds hierarchy from value, so muted
    /// text is the base text at lower opacity rather than a different hue.
    public static func muted(_ opacity: Double = 0.6) -> Color { text.opacity(opacity) }

    // MARK: Spacing (density 0.7× — this system is dense on purpose)

    public enum Space {
        public static let s1: CGFloat = 3
        public static let s2: CGFloat = 6
        public static let s3: CGFloat = 8
        public static let s4: CGFloat = 11
        public static let s6: CGFloat = 17
        public static let s8: CGFloat = 22
    }

    // MARK: Radius

    public enum Radius {
        public static let sm: CGFloat = 4
        public static let md: CGFloat = 8
        public static let lg: CGFloat = 14
    }

    // MARK: Type — native SF (the app's answer to the web mock's Inter)

    public enum Font {
        /// Section header (h4).
        public static let heading = SwiftUI.Font.system(size: 20, weight: .medium)
        public static let body = SwiftUI.Font.system(size: 13)
        public static let bodyEmphasis = SwiftUI.Font.system(size: 13, weight: .medium)
        public static let small = SwiftUI.Font.system(size: 11)
        public static let mono = SwiftUI.Font.system(size: 12.5, design: .monospaced)
        /// Uppercase section caption, e.g. "WORKLOADS".
        public static let caption = SwiftUI.Font.system(size: 10, weight: .semibold)
    }
}

extension Color {
    /// Builds a color from a 24-bit RGB literal, e.g. `Color(hex: 0x9184D9)`.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
