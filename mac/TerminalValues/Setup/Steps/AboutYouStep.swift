import SwiftUI

struct AboutYouStep: View {
    @Bindable var walk: WalkthroughController
    var body: some View {
        Why("Your name and email go on every change you make to TV's code.")
        Form {
            TextField("Your name", text: $walk.name)
            TextField("Email", text: $walk.email)
        }
        ContinueButton(enabled: walk.aboutYouReady) { walk.go(.invitation) }
    }
}
