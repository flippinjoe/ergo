import SwiftUI

/// The floating log dock: a dark solid log surface with a glass header bar
/// carrying the followed pod + actions. Streams a selected pod's logs live
/// (`Exec`/`Explain` are pillar-3 agent-action seams).
struct LogDockView: View {
    /// The pod being followed, or `nil` when nothing is selected.
    let followed: String?
    let lines: [LogLine]
    /// Dismisses the dock.
    var onClose: () -> Void = {}

    var body: some View {
        ZStack(alignment: .top) {
            logSurface
            header
        }
        .frame(height: 180)
    }

    private var logSurface: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    Spacer().frame(height: 34)
                    if followed == nil {
                        Text("Select a pod to stream its logs.")
                            .font(Nocturne.Font.small)
                            .foregroundStyle(Nocturne.muted(0.4))
                    } else if lines.isEmpty {
                        Text("Waiting for output…")
                            .font(Nocturne.Font.small)
                            .foregroundStyle(Nocturne.muted(0.4))
                    }
                    ForEach(lines) { line in
                        logLine(line).id(line.id)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Nocturne.Space.s4)
                .padding(.bottom, Nocturne.Space.s3)
            }
            .background(Color(hex: 0x090A10).opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: Nocturne.Radius.md, style: .continuous))
            .onChange(of: lines.count) {
                withAnimation { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: Nocturne.Space.s2) {
            StatusDot(health: followed == nil ? .unknown : .info, size: 6)
            Text(followed ?? "Logs")
                .font(Nocturne.Font.small)
                .foregroundStyle(followed == nil ? Nocturne.muted(0.6) : Nocturne.accent200)
            if followed != nil {
                Text("· following").font(Nocturne.Font.small).foregroundStyle(Nocturne.muted(0.42))
            }
            Spacer()
            Button {
            } label: {
                Label("Exec", systemImage: "terminal")
            }
            .disabled(followed == nil)
            Button {
            } label: {
                Label("Explain", systemImage: "sparkles")
            }
            .tint(Nocturne.accent)
            .disabled(followed == nil)
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .help("Hide logs")
        }
        .font(Nocturne.Font.small)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, Nocturne.Space.s3)
        .frame(height: 34)
        .glassPanel(cornerRadius: Nocturne.Radius.md)
        .padding(Nocturne.Space.s2)
    }

    private static let bottomID = "log-bottom"

    @ViewBuilder private func logLine(_ line: LogLine) -> some View {
        (Text(line.time.map { $0 + "  " } ?? "").foregroundStyle(Nocturne.muted(0.34))
            + Text(levelText(line.level) + " ").foregroundStyle(levelColor(line.level))
            + Text(line.message).foregroundStyle(Nocturne.muted(0.72)))
            .font(.system(size: 11.5, design: .monospaced))
            .textSelection(.enabled)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private func levelText(_ level: LogLine.Level) -> String {
        switch level {
        case .info: "INFO "
        case .warn: "WARN "
        case .error: "ERROR"
        }
    }

    private func levelColor(_ level: LogLine.Level) -> Color {
        switch level {
        case .info: Nocturne.accent200
        case .warn: Nocturne.statusWarn
        case .error: Nocturne.statusError
        }
    }
}
