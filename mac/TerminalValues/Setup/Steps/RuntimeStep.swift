import SwiftUI

struct RuntimeStep: View {
    @Bindable var walk: WalkthroughController
    var body: some View {
        Why("The box is a container, and containers need a runtime to run in: Apple's own, called container. It's the one thing this installs for the whole Mac, so Apple's installer asks for your password.")
        if walk.model.check == .noRuntime {
            Button("Install Apple's container…") { Task { await walk.installRuntime() } }
                .disabled(walk.working != nil)
        } else {
            Text("It's installed, but not running.")
            Button("Start It") { Task { await walk.startRuntime() } }.disabled(walk.working != nil)
        }
    }
}
