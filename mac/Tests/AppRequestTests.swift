import Foundation
import Testing
@testable import TerminalValues

/// What a tvhome: URL asks the app for: tv update opens tvhome://update,
/// so typing it starts the app's own update; the rest are TVhome links.
@Suite struct AppRequestTests {
    @Test func updateAsksForAnUpdate() {
        #expect(AppRequest(URL(string: "tvhome://update")!) == .update)
        #expect(AppRequest(URL(string: "TVHOME://Update/")!) == .update)
    }

    @Test func folderLinksStayLinks() {
        let link = "tvhome://folder/doc/notes.md"
        #expect(AppRequest(URL(string: link)!) == .link(link))
        // A file called update is still a file.
        #expect(AppRequest(URL(string: "tvhome://folder/update")!) == .link("tvhome://folder/update"))
    }

    @Test func otherSchemesAreIgnored() {
        #expect(AppRequest(URL(string: "https://home.terminalvalues.org/#doc")!) == nil)
    }
}
