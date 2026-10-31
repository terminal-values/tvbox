import Foundation
import Testing
@testable import TerminalValues

@MainActor @Suite struct UpdatesTests {
    func status(revision: String) -> String {
        Fixture.statusRunning.replacingOccurrences(of: "\"port\": 8484,", with: "\"port\": 8484, \"revision\": \"\(revision)\",")
    }

    @Test func movesBoxToPinnedImageAfterUpdate() async throws {
        let fake = try FakeTV(answers: ["check": "running\n", "status": status(revision: "aaa")])
        let model = AppModel(tv: fake.tv)
        await model.refresh()
        let moved = await moveBoxIfNeeded(model: model, pinned: BoxImage(digest: "sha256:pinned", revision: "abc"))
        #expect(moved)
        #expect(fake.calls.contains("update --to sha256:pinned --revision abc"))
    }

    @Test func noMoveWhenAlreadyThere() async throws {
        let fake = try FakeTV(answers: ["check": "running\n", "status": status(revision: "abc")])
        let model = AppModel(tv: fake.tv)
        await model.refresh()
        #expect(await moveBoxIfNeeded(model: model, pinned: BoxImage(digest: "sha256:pinned", revision: "abc")) == false)
        #expect(!fake.calls.contains { $0.hasPrefix("update") })
    }

    @Test func noMoveForADevelopmentBuildOrBeforeSetup() async throws {
        let fake = try FakeTV(answers: ["check": "running\n", "status": status(revision: "aaa")])
        let model = AppModel(tv: fake.tv)
        await model.refresh()
        #expect(await moveBoxIfNeeded(model: model, pinned: nil) == false)
        let fresh = AppModel(tv: fake.tv)  // status not known yet
        #expect(await moveBoxIfNeeded(model: fresh, pinned: BoxImage(digest: "d", revision: "r")) == false)
    }

    @Test func readsThePinFromTheBundle() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bundle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plist = try PropertyListEncoder().encode(["Digest": "sha256:x", "Revision": "abc"])
        try plist.write(to: dir.appendingPathComponent("BoxImage.plist"))
        #expect(BoxImage.read(from: dir) == BoxImage(digest: "sha256:x", revision: "abc"))
        #expect(BoxImage.read(from: dir.appendingPathComponent("nowhere")) == nil)
    }
}
