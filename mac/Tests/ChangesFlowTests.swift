import Foundation
import Testing
@testable import TerminalValues

@MainActor @Suite struct ChangesFlowTests {
    func shown() throws -> Changes {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Changes.self, from: Data(Fixture.changes.utf8))
    }

    @Test func applyPassesThePinnedCommits() async throws {
        let fake = try FakeTV(answers: ["check": "running\n", "status": Fixture.statusRunning,
                                        "changes": Fixture.changes])
        let model = AppModel(tv: fake.tv)
        let outcome = await model.applyChanges(try shown())
        #expect(outcome == .applied)
        #expect(fake.calls.contains("catch-up --yes --to abc123 --secrets-to def456"))
    }

    // Review Focus: tvhome gains a commit between showing and Apply: nothing
    // unseen is applied, and the app fetches and shows the new state.
    @Test func tvhomeMovedReshows() async throws {
        let fake = try FakeTV(answers: ["check": "running\n", "status": Fixture.statusRunning,
                                        "changes": Fixture.changes, "catch-up": "tvhome has changed since you looked; review again.\n"],
                              exits: ["catch-up": 4])
        let model = AppModel(tv: fake.tv)
        let before = fake.calls.count
        let outcome = await model.applyChanges(try shown())
        #expect(outcome == .tvhomeMoved)
        #expect(fake.calls.dropFirst(before).contains("changes"))
    }

    @Test func aClashIsReportedInWords() async throws {
        let fake = try FakeTV(answers: ["catch-up": "Your commits clash with tvhome's in: bin/tool \n"],
                              exits: ["catch-up": 1])
        let model = AppModel(tv: fake.tv)
        guard case .clash(let words) = await model.applyChanges(try shown()) else {
            Issue.record("not a clash"); return
        }
        #expect(words.contains("bin/tool"))
    }

    @Test func gaugesStopWhenWindowHidden() async throws {
        let fake = try FakeTV(answers: ["check": "running\n", "status": Fixture.statusRunning, "stats": Fixture.stats])
        let model = AppModel(tv: fake.tv)
        model.statsInterval = .milliseconds(100)
        await model.refresh()
        model.windowVisible(true)
        try await Task.sleep(for: .milliseconds(450))
        model.windowVisible(false)
        // A call already under way may still finish; nothing new starts after.
        try await Task.sleep(for: .milliseconds(250))
        let seen = fake.calls.filter { $0.hasPrefix("stats") }.count
        #expect(seen >= 2)
        try await Task.sleep(for: .milliseconds(400))
        #expect(fake.calls.filter { $0.hasPrefix("stats") }.count == seen)
    }
}
