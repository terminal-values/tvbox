import SwiftUI

struct FillingStep: View {
    @Bindable var walk: WalkthroughController
    var body: some View {
        Why("Syncthing brings TV's documents into your folder and keeps them the same as everyone else's; git brings TV's code and the instructions agents follow.")
        if let s = walk.model.status?.sync {
            Text(s.needFiles > 0 ? "\(s.needFiles) files to go" : "\(s.files) files so far")
                .monospacedDigit()
        }
        Text("The first time can take a few minutes.").foregroundStyle(.secondary)
            .task { await walk.fill() }
        if walk.fillFailed {
            HStack { Spacer(); Button("Try Again") { Task { await walk.fill() } } }
        }
    }
}
