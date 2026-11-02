import SwiftUI

struct InvitationStep: View {
    @Bindable var walk: WalkthroughController
    var body: some View {
        Why("tvhome isn't on the public internet. Your invitation lets the box (not your Mac) join TV's private network. It works only once, so keep it to yourself.")
        Text("In Signal, find Danny's message, select the whole line starting tvjoin:, and copy it. You don't paste it anywhere: the app picks it up from the clipboard, and clears the clipboard once you've joined.")
            .fixedSize(horizontal: false, vertical: true)
        HStack { Button("Back") { walk.go(.aboutYou) }; Spacer() }
            .task { await walk.watchForInvitation() }
    }
}
