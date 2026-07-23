import KubeClient
import KubeCore
import SwiftUI
import UniformTypeIdentifiers

/// The "Add Cluster" flow. Pick a source, then (for Azure) sign in → choose a
/// subscription → choose clusters. Calls `onAdd` with the connections to save.
struct AddClusterSheet: View {
    let azure: any AzureClusterService
    let onAdd: ([ClusterConnection]) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model: AddClusterModel
    @State private var showingFileImporter = false

    init(azure: any AzureClusterService, onAdd: @escaping ([ClusterConnection]) async -> Void) {
        self.azure = azure
        self.onAdd = onAdd
        _model = State(initialValue: AddClusterModel(azure: azure))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Nocturne.divider)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(Nocturne.Space.s6)
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(Nocturne.Font.small)
                    .foregroundStyle(Nocturne.statusError)
                    .padding(.horizontal, Nocturne.Space.s6)
                    .padding(.bottom, Nocturne.Space.s3)
            }
        }
        .frame(width: 520, height: 460)
        .background(Nocturne.surface)
        .tint(Nocturne.accent)
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { model.loadKubeconfig(url: url) }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Nocturne.Space.s3) {
            if model.canGoBack {
                Button {
                    model.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
            }
            Text(title).font(Nocturne.Font.heading)
            Spacer()
            if model.isBusy { ProgressView().controlSize(.small) }
            Button("Cancel") { dismiss() }.buttonStyle(.borderless)
        }
        .padding(Nocturne.Space.s4)
    }

    private var title: String {
        switch model.step {
        case .chooseSource: "Add Cluster"
        case .azureSignIn: "Sign in to Azure"
        case .azureSubscriptions: "Choose a subscription"
        case .azureClusters: "Choose clusters"
        case .kubeconfigContexts: "Choose contexts"
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch model.step {
        case .chooseSource: chooseSource
        case .azureSignIn: azureSignIn
        case .azureSubscriptions: subscriptionList
        case .azureClusters: clusterList
        case .kubeconfigContexts: contextList
        }
    }

    private var chooseSource: some View {
        VStack(alignment: .leading, spacing: Nocturne.Space.s4) {
            Text("Where is your cluster?")
                .font(Nocturne.Font.bodyEmphasis)
                .foregroundStyle(Nocturne.muted(0.8))
            SourceCard(
                kind: .azure,
                title: "Azure (AKS)",
                subtitle: "Sign in to Microsoft and pick clusters from your subscriptions."
            ) { model.chooseAzure() }
            SourceCard(
                kind: .kubeconfig,
                title: "Kubeconfig file",
                subtitle: "Pick a kubeconfig (e.g. ~/.kube/config) and choose which contexts to add."
            ) { showingFileImporter = true }
        }
    }

    private var azureSignIn: some View {
        VStack(alignment: .leading, spacing: Nocturne.Space.s6) {
            VStack(alignment: .leading, spacing: Nocturne.Space.s3) {
                Image(systemName: "cloud").font(.system(size: 34)).foregroundStyle(Nocturne.accent200)
                Text(
                    "Ergo opens Microsoft sign-in in a secure window. Your password never touches Ergo, and your kubeconfig stays on this Mac."
                )
                .font(Nocturne.Font.body)
                .foregroundStyle(Nocturne.muted(0.75))
                .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                Task { await model.signIn() }
            } label: {
                Label("Sign in to Microsoft", systemImage: "person.badge.key")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isBusy)
        }
    }

    private var subscriptionList: some View {
        List {
            if let account = model.account {
                Text("Signed in as \(account.username)")
                    .font(Nocturne.Font.small)
                    .foregroundStyle(Nocturne.muted(0.6))
            }
            ForEach(model.subscriptions) { sub in
                Button {
                    Task { await model.pick(sub) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(sub.displayName).font(Nocturne.Font.body)
                            Text(sub.subscriptionID).font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Nocturne.muted(0.5))
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Nocturne.muted(0.4))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.plain)
    }

    private var clusterList: some View {
        VStack(spacing: 0) {
            List {
                ForEach(model.clusters) { cluster in
                    Button {
                        model.toggle(cluster)
                    } label: {
                        HStack(spacing: Nocturne.Space.s3) {
                            Image(
                                systemName: model.selectedClusterIDs.contains(cluster.id)
                                    ? "checkmark.circle.fill" : "circle"
                            )
                            .foregroundStyle(
                                model.selectedClusterIDs.contains(cluster.id)
                                    ? Nocturne.accent : Nocturne.muted(0.4))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(cluster.name).font(Nocturne.Font.body)
                                Text(
                                    "\(cluster.resourceGroup) · \(cluster.location) · v\(cluster.kubernetesVersion)"
                                )
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Nocturne.muted(0.5))
                            }
                            Spacer()
                            StatusDot(health: cluster.health)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)

            HStack {
                Spacer()
                Button {
                    Task {
                        await onAdd(model.selectedConnections(now: Date()))
                        dismiss()
                    }
                } label: {
                    Text(
                        model.selectedClusterIDs.isEmpty
                            ? "Select clusters to add"
                            : "Add \(model.selectedClusterIDs.count) cluster\(model.selectedClusterIDs.count == 1 ? "" : "s")"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedClusterIDs.isEmpty)
            }
            .padding(.top, Nocturne.Space.s3)
        }
    }

    private var contextList: some View {
        VStack(spacing: 0) {
            List {
                ForEach(model.kubeContexts) { context in
                    Button {
                        model.toggleContext(context.name)
                    } label: {
                        HStack(spacing: Nocturne.Space.s3) {
                            Image(
                                systemName: model.selectedContextNames.contains(context.name)
                                    ? "checkmark.circle.fill" : "circle"
                            )
                            .foregroundStyle(
                                model.selectedContextNames.contains(context.name)
                                    ? Nocturne.accent : Nocturne.muted(0.4))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(context.name).font(Nocturne.Font.body)
                                if !context.server.isEmpty {
                                    Text(context.server)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Nocturne.muted(0.5))
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)

            HStack {
                Spacer()
                Button {
                    Task {
                        await onAdd(model.selectedKubeconfigConnections(now: Date()))
                        dismiss()
                    }
                } label: {
                    Text(
                        model.selectedContextNames.isEmpty
                            ? "Select contexts to add"
                            : "Add \(model.selectedContextNames.count) context\(model.selectedContextNames.count == 1 ? "" : "s")"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedContextNames.isEmpty)
            }
            .padding(.top, Nocturne.Space.s3)
        }
    }
}

/// A big tappable card for a source in the chooser.
private struct SourceCard: View {
    let kind: ClusterSource.Kind
    let title: String
    let subtitle: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Nocturne.Space.s4) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 22))
                    .foregroundStyle(Nocturne.accent200)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Nocturne.Font.bodyEmphasis)
                    Text(subtitle).font(Nocturne.Font.small).foregroundStyle(Nocturne.muted(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Nocturne.muted(0.4))
            }
            .padding(Nocturne.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Nocturne.Radius.md, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.08 : 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: Nocturne.Radius.md, style: .continuous)
                            .strokeBorder(Nocturne.divider, lineWidth: 1))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
