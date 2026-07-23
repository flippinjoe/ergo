import SwiftUI

/// A small pill label tinted from the ramps (the `.tag` pattern). Two variants
/// cover the mock's usage: a neutral fill and an accent outline.
public struct Tag: View {
    public enum Style { case neutral, outline }

    private let title: String
    private let style: Style

    public init(_ title: String, style: Style = .neutral) {
        self.title = title
        self.style = style
    }

    public var body: some View {
        Text(title)
            .font(Nocturne.Font.small)
            .foregroundStyle(style == .outline ? Nocturne.accent300 : Nocturne.text.opacity(0.85))
            .padding(.horizontal, Nocturne.Space.s3)
            .padding(.vertical, 3)
            .background(background)
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Nocturne.Radius.sm + 2, style: .continuous)
        switch style {
        case .neutral:
            shape.fill(Color.white.opacity(0.10))
        case .outline:
            shape.strokeBorder(Nocturne.accent.opacity(0.7), lineWidth: 1)
        }
    }
}
