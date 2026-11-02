import Testing
@testable import TerminalValues

@Suite struct DoneStepTests {
    // The app's tour is gone (2026-11-02): learning the setup is TUTORIAL.md's
    // job, run by the member's own agent, so the last page points there.
    @Test func theLastPagePointsAtTheTutorial() {
        #expect(DoneStep.next.contains("TUTORIAL.md"))
        #expect(DoneStep.next.contains("agent"))
        #expect(!DoneStep.next.lowercased().contains("tour"))
    }

    // Not every TV folder is in Documents: on a Mac whose Documents iCloud
    // syncs, tv puts it in the home folder.
    @Test func theLastPageDoesntSayWhereTheFolderIs() {
        #expect(!DoneStep.youreIn.contains("Documents"))
    }
}
