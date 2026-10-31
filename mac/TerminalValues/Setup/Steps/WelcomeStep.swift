import SwiftUI

struct WelcomeStep: View {
    @Bindable var walk: WalkthroughController
    var body: some View {
        Why("Terminal Values keeps its documents on members' computers and on tvhome, TV's own machine in Danny's house, not on Google Drive or Dropbox.")
        Text("This sets your Mac up to join in: a TV folder in your Documents, and the box, a small Linux machine in a container that holds everything else TV needs (a private connection to tvhome, the syncing, git, and TV's shared passwords). None of it is installed on the Mac itself; remove the box and your Mac is as it was.")
            .fixedSize(horizontal: false, vertical: true)
        Text("You'll need the login name you picked and the invitation Danny sent you in TV Signal.")
        ContinueButton { walk.welcomeDone() }
    }
}
