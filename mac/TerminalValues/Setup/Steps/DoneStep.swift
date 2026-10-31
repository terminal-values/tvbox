import SwiftUI

struct DoneStep: View {
    @Bindable var walk: WalkthroughController
    var body: some View {
        Text("You're in. Your TV folder is in your Documents, and the box keeps it in step with everyone else's while this app runs.")
            .fixedSize(horizontal: false, vertical: true)
        if TutorialProgress.enabled {
            Text("Next, a short tour: four things to try, a few minutes each.")
        }
        HStack {
            Button("Open TV Folder") {
                if let f = walk.model.status?.folder { NSWorkspace.shared.open(URL(fileURLWithPath: f)) }
            }
            Spacer()
            Button(TutorialProgress.enabled ? "Start the Tour" : "Finish") { walk.finish() }
                .keyboardShortcut(.defaultAction)
        }
    }
}
