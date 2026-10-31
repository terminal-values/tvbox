import Foundation
import Testing
@testable import TerminalValues

@Suite struct EngineTests {
    @Test func decodesStatusRunning() async throws {
        let fake = try FakeTV(answers: ["status": Fixture.statusRunning])
        let s = try await fake.tv.json(Status.self, ["status", "--json"])
        #expect(s.box == .running && s.tailnet == .on && s.port == 8484 && s.name == "Sam Smith")
        #expect(s.sync?.files == 11 && s.sync?.waitingForList == false)
    }

    @Test func decodesStatusStopped() async throws {
        let fake = try FakeTV(answers: ["status": Fixture.statusStopped])
        let s = try await fake.tv.json(Status.self, ["status", "--json"])
        #expect(s.box == .stopped && s.tailnet == nil && s.sync == nil)
    }

    @Test func decodesTheRest() async throws {
        let fake = try FakeTV(answers: ["stats": Fixture.stats, "changes": Fixture.changes,
                                        "identity": Fixture.identity, "update": Fixture.updateCheck,
                                        "doctor": Fixture.doctor])
        let stats = try await fake.tv.json(Stats.self, ["stats", "--json"])
        #expect(stats.cpuPercent == 3.0 && stats.memoryBytes == 408944640 && stats.diskBytes == nil)
        let ch = try await fake.tv.json(Changes.self, ["changes"])
        #expect(ch.code.to == "abc123" && ch.code.incoming.first?.author == "Alex Example" && ch.secrets.to == "def456")
        #expect(try await fake.tv.json(Identity.self, ["identity", "--json"]).age == "age1abc")
        #expect(try await fake.tv.json(UpdateCheck.self, ["update", "--check", "--json"]).commits.count == 2)
        let doc = try await fake.tv.json(DoctorReport.self, ["doctor", "--json"])
        #expect(doc.results.first?.fix == .startRuntime && doc.results.last?.status == .ok)
    }

    @Test func passesArgumentsAndStdin() async throws {
        let fake = try FakeTV()
        let r = try await fake.tv.run(["join", "--login", "sam smith"], stdin: Data("secret\n".utf8))
        #expect(r.status == 0)
        #expect(fake.calls == ["join --login sam smith"])
    }

    @Test func checkStateFromTvCheck() async throws {
        let fake = try FakeTV(answers: ["check": "not-joined\n"])
        #expect(try await fake.tv.check() == .notJoined)
    }

    // Review Focus: something that isn't JSON (an older tv, an error) is an
    // error the app can show, never a crash.
    @Test func junkOutputIsBadOutputNotCrash() async throws {
        let fake = try FakeTV(env: ["FAKETV_JUNK": "1"])
        await #expect(throws: TVError.self) { try await fake.tv.json(Status.self, ["status", "--json"]) }
        do { _ = try await fake.tv.json(Status.self, ["status", "--json"]) } catch let e as TVError {
            guard case .badOutput = e else { Issue.record("wrong error \(e)"); return }
        }
    }

    // Review Focus: a tv that hangs (tvhome down, a slow runtime) gives up in time.
    @Test func slowTvTimesOut() async throws {
        let fake = try FakeTV(env: ["FAKETV_SLEEP": "5"])
        let start = ContinuousClock.now
        do {
            _ = try await fake.tv.run(["status", "--json"], timeout: .seconds(1))
            Issue.record("didn't time out")
        } catch let e as TVError {
            guard case .timedOut = e else { Issue.record("wrong error \(e)"); return }
        }
        #expect(ContinuousClock.now - start < .seconds(3))
    }

    @Test func failureCarriesStatusAndStderr() async throws {
        let fake = try FakeTV(answers: ["start": ""], exits: ["start": 3])
        do { _ = try await fake.tv.json(Status.self, ["start"]); Issue.record("didn't throw") }
        catch let e as TVError { guard case .failed(let code, _) = e else { Issue.record("\(e)"); return }; #expect(code == 3) }
    }
}
