import SwiftUI

struct WaitingStep: View {
    @Bindable var walk: WalkthroughController
    @State private var showLines = false
    var body: some View {
        Why("Danny lets you in: your login on tvhome, your box on its Syncthing, your key among the secrets' readers.")
        Text("You sent him your three lines. When he's let you in, this moves on by itself. You can close this window; the menu bar icon will tell you.")
            .fixedSize(horizontal: false, vertical: true)
        HStack { ProgressView().controlSize(.small); Text("Checking every minute…").foregroundStyle(.secondary) }
        HStack {
            Spacer()
            Button("Show My Three Lines Again") { Task { await walk.loadIdentity(); showLines = true } }
        }
        .popover(isPresented: $showLines) {
            Text(walk.threeLines).font(.system(.callout, design: .monospaced)).textSelection(.enabled).padding()
        }
        .task { await walk.waitForDanny() }
    }
}
