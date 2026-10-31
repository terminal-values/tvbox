import ServiceManagement
import SwiftUI

/// The menu under the menu bar icon.
struct MenuContent: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Text(statusLine)
        if let line = statsLine { Text(line) }
        Divider()
        if model.isSetUp {
            if model.isRunning {
                Button("Stop the Box") { Task { await model.stopBox() } }
            } else {
                Button("Start the Box") { Task { await model.startBox() } }
            }
            Button("Open TV Folder") { openFolder() }.disabled(model.status == nil)
            Button("Open TV's Pages") { Task { _ = try? await model.tv.run(["pages"]) } }
                .disabled(!model.isRunning)
            if model.pendingCodeChanges > 0 {
                Button("Catch Up… (\(model.pendingCodeChanges) code change\(model.pendingCodeChanges == 1 ? "" : "s"))") {
                    showWindow()
                }
            }
            Divider()
        }
        Button(model.isSetUp ? "Open Terminal Values…" : "Set Up Terminal Values…") { showWindow() }
        Toggle("Open at Login", isOn: $openAtLogin)
            .onChange(of: openAtLogin) { _, on in
                do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                catch { openAtLogin = SMAppService.mainApp.status == .enabled }
            }
        Divider()
        Button("Quit Terminal Values") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusLine: String {
        if let busy = model.busy { return busy }
        guard let s = model.status else { return "Checking…" }
        if !model.isSetUp { return "Not set up yet" }
        guard s.box == .running else { return "The box is stopped" }
        switch (s.tailnet, s.sync) {
        case (.offline?, _): return "Box running · offline"
        case (_, let sync?) where !sync.connected: return "Box running · connecting…"
        case (_, let sync?) where sync.needFiles > 0: return "Box running · \(sync.needFiles) files to get"
        case (_, let sync?) where sync.sending > 0: return "Box running · sending \(sync.sending) files"
        default: return "Box running · up to date"
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
