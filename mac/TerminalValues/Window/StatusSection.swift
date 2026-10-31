import SwiftUI

struct StatusSection: View {
    @Bindable var model: AppModel

    var body: some View {
        Section {
            LabeledContent {
                if model.isRunning {
                    Button("Stop") { Task { await model.stopBox() } }
                } else {
                    Button("Start") { Task { await model.startBox() } }.disabled(!model.isSetUp)
                }
            } label: {
                Label(boxLine, systemImage: model.isRunning ? "circle.fill" : "circle")
                    .foregroundStyle(model.isRunning ? .green : .secondary)
                    .labelStyle(.titleAndIcon)
            }
            LabeledContent("TV's network", value: networkLine)
            LabeledContent("Documents", value: documentsLine)
            if let folder = model.status?.folder {
                LabeledContent("Folder", value: (folder as NSString).abbreviatingWithTildeInPath)
            }
        }
    }

    private var boxLine: String {
        if let busy = model.busy { return busy }
        return model.isRunning ? "The box is running" : "The box is stopped"
    }

    private var networkLine: String {
        guard model.isRunning else { return "—" }
        switch model.status?.tailnet {
        case .on?: return "Connected"
        case .offline?: return "Offline"
        case .notJoined?: return "Not joined"
        default: return "Connecting…"
        }
    }

    private var documentsLine: String {
        guard model.isRunning, let sync = model.status?.sync else { return "Not syncing" }
        if !sync.connected { return "Connecting to tvhome…" }
        if !sync.shared { return "Waiting for Danny" }
        if sync.waitingForList { return "Waiting for tvhome's list" }
        if sync.needFiles > 0 { return "\(sync.needFiles) to get" }
        if sync.sending > 0 { return "Sending \(sync.sending)" }
        return "Up to date · \(sync.files) files"
    }
}
