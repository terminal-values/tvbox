import SwiftUI

struct InvitationStep: View {
    @Bindable var walk: WalkthroughController
    var body: some View {
        Why("tvhome isn't on the public internet. Your invitation lets the box (not your Mac) join TV's private network. It works only once, so keep it to yourself.")
        Text("In Signal, find Danny's message, select the whole line starting tvjoin:, and copy it. You don't paste it anywhere: the app picks it up from the clipboard, and clears the clipboard once you've joined.")
            .fixedSize(horizontal: false, vertical: true)
        // An older invitation, without the login in it (until 2026-11-08).
        if walk.needsLogin {
            Text("This invitation is an older kind, without your login in it. Type the login you agreed with Danny:")
                .fixedSize(horizontal: false, vertical: true)
            Form { TextField("Login name", text: $walk.login, prompt: Text("like sam")) }
            if !walk.login.isEmpty && !SetupStep.isGoodLogin(walk.login) {
                Text("A login is short and lowercase: letters, digits and dashes, starting with a letter.")
                    .font(.caption).foregroundStyle(.red)
            }
            ContinueButton(enabled: SetupStep.isGoodLogin(walk.login)) {
                Task { await walk.watchForInvitation() }
            }
        }
        HStack { Button("Back") { walk.go(.aboutYou) }; Spacer() }
            .task { await walk.watchForInvitation() }
    }
}
