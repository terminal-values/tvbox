import ServiceManagement
import SwiftUI

/// The menu under the menu bar icon: TVhome's pages and folder first, then
/// this Mac's box, then Quit.
struct MenuContent: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var startAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        if model.isSetUp {
            Button("Open TVhome Pages") { Task { _ = try? await model.tv.run(["pages"]) } }
                .disabled(!model.isRunning)
            Button("Open TVhome Folder") { openFolder() }.disabled(model.status == nil)
            if model.pendingCodeChanges > 0 {
                Button("Catch Up… (\(model.pendingCodeChanges) code change\(model.pendingCodeChanges == 1 ? "" : "s"))") {
                    showWindow()
                    model.reviewRequested = true
                }
            }
            Divider()
        }
        Text(statusLine)
        if let line = statsLine { Text(line) }
        if model.isSetUp {
            if model.isRunning {
                Button("Stop TV Box") { Task { await model.stopBox() } }
            } else {
                Button("Start TV Box") { Task { await model.startBox() } }
            }
        }
        Toggle("Start at Login", isOn: $startAtLogin)
            .onChange(of: startAtLogin) { _, on in
                do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                catch { startAtLogin = SMAppService.mainApp.status == .enabled }
            }
        Button(model.isSetUp ? "Open TV Box Status…" : "Set Up Terminal Values…") { showWindow() }
        Divider()
        Button("Quit Terminal Values") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusLine: String {
        if let busy = model.busy { return busy }
        guard let s = model.status else { return model.statusProblem == nil ? "Checking…" : "tv isn't answering" }
        if !model.isSetUp { return "Not set up yet" }
        guard s.box == .running else { return "TV Box stopped" }
        switch (s.tailnet, s.sync) {
        case (.offline?, _): return "TV Box running · offline"
        case (_, let sync?) where !sync.connected: return "TV Box running · connecting…"
        case (_, let sync?) where sync.needFiles > 0: return "TV Box running · \(sync.needFiles) files to get"
        case (_, let sync?) where sync.sending > 0: return "TV Box running · sending \(sync.sending) files"
        default: return "TV Box running · up to date"
        }
    }

    private var statsLine: String? {
        guard model.isRunning, let st = model.stats else { return nil }
        let files = model.status?.sync.map { " · \($0.files) files" } ?? ""
        return String(format: "CPU %.0f%% · Memory %d MB", st.cpuPercent, st.memoryBytes / 1_048_576) + files
    }

    private func openFolder() {
        guard let folder = model.status?.folder else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: folder))
    }

    private func showWindow() {
        openWindow(id: "main")
        NSApplication.shared.activate()
    }
}
