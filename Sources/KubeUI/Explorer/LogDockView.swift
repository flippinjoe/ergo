import SwiftUI

/// The floating log dock from the design: a dark solid log surface with a
/// glass header bar carrying the followed pod + actions. Static sample lines —
/// streaming is a future feature; this establishes the pattern and the seam
/// (Exec / Explain sit where pillar-3 agent actions will live).
struct LogDockView: View {
    struct Line: Identifiable {
        let id = UUID()
        let time: String
        let level: Level
        let message: String
        enum Level { case info, warn, error }
    }

    /// The followed pod, or `nil` for a live cluster where streaming isn't built
    /// yet (shows an honest placeholder instead of fabricated lines).
    let followed: String?
    let lines: [Line]

    var body: some View {
        ZStack(alignment: .top) {
            // Solid log surface (content).
            VStack(alignment: .leading, spacing: 2) {
                Spacer().frame(height: 34)
                if followed == nil {
                    Text("Live log streaming is coming soon.")
                        .font(Nocturne.Font.small)
                        .foregroundStyle(Nocturne.muted(0.4))
                }
                ForEach(lines) { line in
                    logLine(line)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Nocturne.Space.s4)
            .padding(.bottom, Nocturne.Space.s3)
            .background(Color(hex: 0x090A10).opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: Nocturne.Radius.md, style: .continuous))

            // Glass header bar floating on the log.
            HStack(spacing: Nocturne.Space.s2) {
                StatusDot(health: followed == nil ? .unknown : .error, size: 6)
                Text(followed ?? "Logs").font(Nocturne.Font.small)
                    .foregroundStyle(followed == nil ? Nocturne.muted(0.6) : Nocturne.statusError)
                if followed != nil {
                    Text("· following").font(Nocturne.Font.small).foregroundStyle(Nocturne.muted(0.42))
                }
                Spacer()
                Button {
                } label: {
                    Label("Exec", systemImage: "terminal")
                }
                Button {
                } label: {
                    Label("Explain", systemImage: "sparkles")
                }
                .tint(Nocturne.accent)
            }
            .font(Nocturne.Font.small)
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.horizontal, Nocturne.Space.s3)
            .frame(height: 34)
            .glassPanel(cornerRadius: Nocturne.Radius.md)
            .padding(Nocturne.Space.s2)
        }
        .frame(height: 180)
    }

    @ViewBuilder private func logLine(_ line: Line) -> some View {
        (Text(line.time + "  ").foregroundStyle(Nocturne.muted(0.34))
            + Text(levelText(line.level) + " ").foregroundStyle(levelColor(line.level))
            + Text(line.message).foregroundStyle(Nocturne.muted(0.66)))
            .font(.system(size: 11.5, design: .monospaced))
            .lineLimit(1)
    }

    private func levelText(_ l: Line.Level) -> String {
        switch l {
        case .info: "INFO "
        case .warn: "WARN "
        case .error: "ERROR"
        }
    }

    private func levelColor(_ l: Line.Level) -> Color {
        switch l {
        case .info: Nocturne.accent200
        case .warn: Nocturne.statusWarn
        case .error: Nocturne.statusError
        }
    }
}
