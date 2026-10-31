import Foundation
import Testing
@testable import TerminalValues

/// The final review: a release's app compares with the box it pins, not with
/// main, which is nearly always ahead.
@MainActor @Suite struct PinTests {
    let pin = BoxImage(digest: "sha256:x", revision: "abc")

    @Test func aPinnedAppDoesntCheckMain() async throws {
        let fake = try FakeTV(answers: ["check": "running\n", "status": Fixture.statusRunning,
                                        "changes": Fixture.changes, "update": Fixture.updateCheck])
        let model = AppModel(tv: fake.tv)
        model.pinned = pin
        await model.refresh()
        await model.refreshSlow()
        #expect(!fake.calls.contains { $0.hasPrefix("update") })
        #expect(!model.updateAvailable)
    }

    @Test func theDoctorComparesWithThePin() async throws {
        let fake = try FakeTV(answers: ["doctor": Fixture.doctor])
        let model = AppModel(tv: fake.tv)
        model.pinned = pin
        await Doctor(model: model).run()
        #expect(fake.calls.contains("doctor --json [pinned abc]"))
    }

    @Test func joiningUsesTheReleasesBox() async throws {
        let fake = try FakeTV(answers: ["check": "running\n", "status": Fixture.statusRunning, "identity": Fixture.identity])
        let model = AppModel(tv: fake.tv)
        model.pinned = pin
        let walk = WalkthroughController(model: model, defaults: UserDefaults(suiteName: "tv-tests-\(UUID().uuidString)")!)
        walk.login = "sam"; walk.name = "Sam"; walk.email = "s@example.org"
        walk.go(.invitation)
        await walk.watchForInvitation()
        #expect(fake.calls.contains("join --from-clipboard --login sam --name Sam --email s@example.org --image sha256:x --revision abc"))
    }
}
