import Foundation
import Testing
@testable import TerminalValues

@MainActor @Suite struct DoctorTests {
    @Test func fixButtonsMatchFixIds() {
        let titles = [DoctorFix.startRuntime, .startBox, .catchUp, .update].map(Doctor.fixTitle)
        #expect(titles == ["Start the Runtime", "Start the Box", "Review & Catch Up…", "Update…"])
    }

    @Test func runsTheCheckUpAndActsOnAFix() async throws {
        let fake = try FakeTV(answers: ["doctor": Fixture.doctor, "check": "running\n", "status": Fixture.statusRunning])
        let model = AppModel(tv: fake.tv)
        let doctor = Doctor(model: model)
        await doctor.run()
        #expect(doctor.report?.results.first?.fix == .startRuntime)
        await doctor.fix(.startRuntime)
        #expect(fake.calls.contains("runtime-start"))
        #expect(fake.calls.filter { $0 == "doctor --json" }.count == 2)  // and checks again
    }

    @Test func reportIsTheTextForm() async throws {
        let words = "problem  runtime       container isn't running.  (fix: tv runtime-start)\n"
        let fake = try FakeTV(answers: ["doctor.1": Fixture.doctor, "doctor.2": words])
        let doctor = Doctor(model: AppModel(tv: fake.tv))
        await doctor.run()
        #expect(await doctor.reportText() == words)
        #expect(fake.calls == ["doctor --json", "doctor"])
    }
}
