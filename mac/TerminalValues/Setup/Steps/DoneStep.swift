import SwiftUI

struct DoneStep: View {
    @Bindable var walk: WalkthroughController

    static let youreIn = "You're in. The box keeps your TVhome Folder in step with everyone else's while this app runs."
    static let next = "Next, to learn how it all works: drag TUTORIAL.md from your TVhome Folder into your agent (Code in the Claude app, or Codex), and ask it to teach you the Terminal Values setup."

    var body: some View {
        Text(Self.youreIn)
            .fixedSize(horizontal: false, vertical: true)
        Text(Self.next)
            .fixedSize(horizontal: false, vertical: true)
        HStack {
            Button("Open TVhome Folder") {
                if let f = walk.model.status?.folder { NSWorkspace.shared.open(URL(fileURLWithPath: f)) }
            }
            Spacer()
            Button("Finish") { walk.finish() }
                .keyboardShortcut(.defaultAction)
        }
    }
}
