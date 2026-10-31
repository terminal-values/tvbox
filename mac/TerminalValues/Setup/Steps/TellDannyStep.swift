import SwiftUI

struct TellDannyStep: View {
    @Bindable var walk: WalkthroughController
    var body: some View {
        Why("Some things only Danny can do: make your login on tvhome, let your box sync with it, and add your key to TV's secrets.")
        Text("Send him these three lines in TV Signal. They're safe to send: the age line is the public half of your key.")
        Text(walk.threeLines).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
            .padding(8).background(.background.secondary, in: .rect(cornerRadius: 6))
        HStack {
            Button("Copy the Three Lines") { walk.copyThreeLines() }
            Spacer()
            Button("Continue") { walk.go(.saveKey) }.keyboardShortcut(.defaultAction)
        }
    }
}
