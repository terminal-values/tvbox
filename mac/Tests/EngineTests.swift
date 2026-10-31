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

@Suite struct EngineCancellationTests {
    // The final review: cancelling a task waiting on tv (closing a window,
    // Quit) crashed the app within a few tries ("task still running").
    @Test func cancellingAWaitingTaskNeverCrashes() async throws {
        let fake = try FakeTV(env: ["FAKETV_SLEEP": "0.2"])
        let runs = 40
        for i in 0..<runs {
            let t = Task { try await fake.tv.run(["status", "--json"]) }
            try await Task.sleep(for: .milliseconds(10 + (i % 5) * 20))
            t.cancel()
            let r = try await t.value  // ran to the end; the caller can ignore it
            #expect(r.status == 0)
        }
        // tv was never killed: every run finished.
        let finished = (try? String(contentsOf: fake.dir.appendingPathComponent("finished.log"), encoding: .utf8)) ?? ""
        #expect(finished.split(separator: "\n").count == runs)
    }

    // Many at once don't starve each other: every one finishes, and a
    // timeout still fires, however many reads are waiting.
    @Test func manyAtOnceAllFinishAndTimeoutsStillFire() async throws {
        let slow = try FakeTV(env: ["FAKETV_SLEEP": "3"])
        let quick = try FakeTV(answers: ["status": Fixture.statusRunning])
        let start = ContinuousClock.now
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<24 { group.addTask { _ = try? await slow.tv.run(["x"], timeout: .seconds(1)) } }
            for _ in 0..<8 { group.addTask { _ = try await quick.tv.json(Status.self, ["status", "--json"]) } }
            try await group.waitForAll()
        }
        #expect(ContinuousClock.now - start < .seconds(3))
    }
}

@Suite struct WaitForExitTests {
    func sleeper(_ seconds: String) throws -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = [seconds]
        return p
    }

    @Test func aCancelledWaitStillWaitsForTheRealExit() async throws {
        let p = try sleeper("0.3")
        let t = Task { () -> Bool in
            try? p.run()
            withUnsafeCurrentTask { $0?.cancel() }  // cancelled while waiting
            return await waitForExit(p, timeout: .seconds(5))
        }
        #expect(await t.value == true)
        #expect(!p.isRunning)
        #expect(p.terminationStatus == 0)  // readable: it has really exited
    }

    @Test func aTimeoutKillsAndWaitsForTheExit() async throws {
        let p = try sleeper("5")
        try p.run()
        let start = ContinuousClock.now
        #expect(await waitForExit(p, timeout: .milliseconds(300)) == false)
        #expect(!p.isRunning && ContinuousClock.now - start < .seconds(2))
    }
}
