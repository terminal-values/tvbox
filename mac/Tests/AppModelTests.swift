import Foundation
import Testing
@testable import TerminalValues

@MainActor @Suite struct AppModelTests {
    let joinedStopped = Fixture.statusStopped
    let joinedRunning = Fixture.statusRunning

    @Test func launchStartsAStoppedBox() async throws {
        let fake = try FakeTV(answers: ["check": "stopped\n", "status": joinedStopped])
        let model = AppModel(tv: fake.tv)
        await model.launch(atLogin: false)
        #expect(fake.calls.contains("start"))
        #expect(!fake.calls.contains("runtime-start"))
    }

    @Test func launchStartsTheRuntimeFirstWhenItIsStopped() async throws {
        // Stopped at first; once runtime-start has run, tv check says the box is stopped.
        let fake = try FakeTV(answers: ["check.1": "runtime-stopped\n", "check": "stopped\n",
                                        "status": joinedStopped])
        let model = AppModel(tv: fake.tv)
        await model.launch(atLogin: true)
        let calls = fake.calls
        let rs = try #require(calls.firstIndex(of: "runtime-start"))
        let st = try #require(calls.firstIndex(of: "start"))
        #expect(rs < st)
    }

    // Review Focus: a box started from a terminal before the app opened is
    // adopted, not restarted or recreated.
    @Test func launchAdoptsARunningBox() async throws {
        let fake = try FakeTV(answers: ["check": "running\n", "status": joinedRunning])
        let model = AppModel(tv: fake.tv)
        await model.launch(atLogin: false)
        // No start, and nothing that remakes the box (a routine update check is fine).
        #expect(!fake.calls.contains("start"))
        #expect(!fake.calls.contains(where: { $0.hasPrefix("update --to") || $0.hasPrefix("update --yes") }))
        #expect(model.status?.box == .running)
    }

    @Test func quitStopsAnAdoptedBox() async throws {
        let fake = try FakeTV(answers: ["check": "running\n", "status": joinedRunning])
        let model = AppModel(tv: fake.tv)
        await model.launch(atLogin: false)
        let before = fake.calls.count
        await model.prepareToQuit()
        #expect(fake.calls.dropFirst(before).contains("stop"))
    }

    @Test func launchDoesNothingBeforeSetup() async throws {
        let notJoined = Fixture.statusStopped.replacingOccurrences(of: "\"login\": \"sam\"", with: "\"login\": \"\"")
        let fake = try FakeTV(answers: ["check": "not-joined\n", "status": notJoined])
        let model = AppModel(tv: fake.tv)
        await model.launch(atLogin: false)
        #expect(!fake.calls.contains("start") && !fake.calls.contains("runtime-start"))
        #expect(model.isSetUp == false)
    }

    @Test func quitAsksWhenTerminalBusy() async throws {
        let fake = try FakeTV()
        let model = AppModel(tv: fake.tv)
        #expect(model.quitRequested(terminalBusy: true) == .ask)
        #expect(model.quitRequested(terminalBusy: false) == .stopAndQuit)
    }

    @Test func statsReadOnlyWhenMenuOpens() async throws {
        let fake = try FakeTV(answers: ["check": "running\n", "status": joinedRunning, "stats": Fixture.stats])
        let model = AppModel(tv: fake.tv)
        await model.refresh()
        #expect(!fake.calls.contains(where: { $0.hasPrefix("stats") }))
        await model.menuOpened()
        #expect(fake.calls.contains("stats --json --no-disk"))
        #expect(model.stats?.memoryBytes == 408944640)
    }

    @Test func slowRefreshCountsCodeChangesAndUpdates() async throws {
        let fake = try FakeTV(answers: ["check": "running\n", "status": joinedRunning,
                                        "changes": Fixture.changes, "update": Fixture.updateCheck])
        let model = AppModel(tv: fake.tv)
        await model.refresh()
        await model.refreshSlow()
        #expect(model.pendingCodeChanges == 1 && model.updateAvailable)
        #expect(model.needsAttention)
    }

    @Test func aFailedStartIsShownNotThrown() async throws {
        let fake = try FakeTV(answers: ["check": "stopped\n", "status": joinedStopped], exits: ["start": 1])
        let model = AppModel(tv: fake.tv)
        await model.startBox()
        #expect(model.lastError != nil)
    }
}
