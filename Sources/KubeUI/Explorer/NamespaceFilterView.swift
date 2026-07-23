import SwiftUI

/// A Lens-style namespace filter: an "All namespaces" toggle plus a checkbox
/// per namespace (multi-select). An empty selection means all. Lives in a
/// popover so toggling several stays open.
struct NamespaceFilterView: View {
    let namespaces: [String]
    @Binding var selection: Set<String>
    @State private var search = ""

    private var filtered: [String] {
        search.isEmpty ? namespaces : namespaces.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if namespaces.count > 8 {
                TextField("Filter namespaces", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .padding(Nocturne.Space.s3)
            }

            row(title: "All namespaces", checked: selection.isEmpty) { selection = [] }
                .padding(.horizontal, Nocturne.Space.s3)
                .padding(.top, namespaces.count > 8 ? 0 : Nocturne.Space.s3)

            Divider().overlay(Nocturne.divider).padding(.vertical, Nocturne.Space.s2)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered, id: \.self) { namespace in
                        row(title: namespace, checked: selection.contains(namespace)) {
                            toggle(namespace)
                        }
                        .padding(.horizontal, Nocturne.Space.s3)
                    }
                }
            }
            .frame(maxHeight: 280)

            Divider().overlay(Nocturne.divider)
            HStack {
                Text(selection.isEmpty ? "All" : "\(selection.count) selected")
                    .font(Nocturne.Font.small).foregroundStyle(Nocturne.muted(0.55))
                Spacer()
                Button("Clear") { selection = [] }
                    .buttonStyle(.borderless)
                    .disabled(selection.isEmpty)
            }
            .controlSize(.small)
            .padding(Nocturne.Space.s3)
        }
        .frame(width: 260)
        .tint(Nocturne.accent)
    }

    private func toggle(_ namespace: String) {
        if selection.contains(namespace) {
            selection.remove(namespace)
        } else {
            selection.insert(namespace)
        }
    }

    private func row(title: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Nocturne.Space.s3) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(checked ? Nocturne.accent : Nocturne.muted(0.4))
                Text(title).font(Nocturne.Font.body).foregroundStyle(Nocturne.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, Nocturne.Space.s2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
