import SwiftUI

struct AboutYouStep: View {
    @Bindable var walk: WalkthroughController
    var body: some View {
        Why("Your login is your name on tvhome. Your name and email go on every change you make to TV's code.")
        Form {
            TextField("Login name", text: $walk.login, prompt: Text("like sam"))
            TextField("Your name", text: $walk.name)
            TextField("Email", text: $walk.email)
        }
        if !walk.login.isEmpty && !SetupStep.isGoodLogin(walk.login) {
            Text("A login is short and lowercase: letters, digits and dashes, starting with a letter.")
                .font(.caption).foregroundStyle(.red)
        }
        ContinueButton(enabled: walk.aboutYouReady) { walk.go(.invitation) }
    }
}
