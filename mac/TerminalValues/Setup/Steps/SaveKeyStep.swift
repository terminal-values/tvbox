import AppKit
import SwiftUI

struct SaveKeyStep: View {
    @Bindable var walk: WalkthroughController
    var body: some View {
        Why("The box made you a secret key, which unlocks TV's shared passwords. If you lose every copy, you lose access until Danny adds a new key for you.")
        Text("Save a copy somewhere you'll still have in a year: your password manager is best. The file is readable only by you; once it's stored safely, delete it.")
            .fixedSize(horizontal: false, vertical: true)
        HStack {
            Button("Not Now") { walk.skipKey() }
            Spacer()
            Button("Save My Key…") { save() }.keyboardShortcut(.defaultAction)
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "tv-age-key.txt"
        panel.message = "Save a copy of your TV key"
        if panel.runModal() == .OK, let url = panel.url { Task { await walk.saveKey(to: url) } }
    }
}
