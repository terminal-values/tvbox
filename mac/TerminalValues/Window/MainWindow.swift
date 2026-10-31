import SwiftUI

/// The everyday window: tall, standard macOS, TV's colours only in the
/// gauges and the accent.
struct MainWindow: View {
    @Bindable var model: AppModel
    let terminal: TerminalSession
    @Bindable var walk: WalkthroughController
    @State private var reviewing = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if walk.shouldShow {
                WalkthroughView(walk: walk)
            } else {
                everyday
            }
        }
        .task { if model.status == nil { await walk.resume() } }
    }

    private var everyday: some View {
        VStack(spacing: 0) {
            header
            Form {
                StatusSection(model: model)
                GaugesSection(model: model)
                Section {
                    if model.pendingCodeChanges > 0 {
                        LabeledContent("\(model.pendingCodeChanges) code change\(model.pendingCodeChanges == 1 ? "" : "s") on tvhome") {
                            Button("Review & Catch Up…") { reviewing = true }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    HStack {
                        Button("Open Folder") { openFolder() }.disabled(model.status == nil)
                        Spacer()
                        Button("Open Pages") { Task { _ = try? await model.tv.run(["pages"]) } }
                            .disabled(!model.isRunning)
                        Spacer()
                        Button("Tutorial") { openWindow(id: "tutorial") }
                    }
                }
                Section("Terminal") {
                    TerminalSection(session: terminal, folder: model.status.map { URL(fileURLWithPath: $0.folder) })
                        .frame(height: 170)
                }
                RecentSection(model: model)
            }
            .formStyle(.grouped)
            FooterView(model: model, openDoctor: { openWindow(id: "doctor") })
        }
        .frame(width: 400)
        .frame(minHeight: 720)
        .onAppear { model.windowVisible(true) }
        .onDisappear { model.windowVisible(false) }
        .sheet(isPresented: $reviewing) { ChangesSheet(model: model) }
        .onChange(of: model.reviewRequested) {
            if model.reviewRequested { model.reviewRequested = false; reviewing = true }
        }
        .alert("Something went wrong", isPresented: .constant(model.lastError != nil)) {
            Button("OK") { model.lastError = nil }
        } message: { Text(model.lastError ?? "") }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().frame(width: 40, height: 40)
            VStack(alignment: .leading) {
                Text("Terminal Values").font(.headline)
                if let login = model.status?.login, !login.isEmpty {
                    Text("\(login) on \(Host.current().localizedName ?? "this Mac")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 14)
    }

    private func openFolder() {
        guard let folder = model.status?.folder else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: folder))
    }
}
