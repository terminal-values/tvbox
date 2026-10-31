import Foundation
import Testing
@testable import TerminalValues

/// The final review: failures were dropped without a word.
@MainActor @Suite struct FailureWordsTests {
    @Test func aRefreshThatFailsSaysSo() async throws {
        let fake = try FakeTV(answers: ["check": "running\n"], env: ["FAKETV_JUNK": "1"])
        let model = AppModel(tv: fake.tv)
        await model.refresh()
        #expect(model.statusProblem != nil)
    }

    @Test func aRefreshThatWorksClearsIt() async throws {
        let fake = try FakeTV(answers: ["check": "running\n", "status": Fixture.statusRunning])
        let model = AppModel(tv: fake.tv)
        model.statusProblem = "earlier"
        await model.refresh()
        #expect(model.statusProblem == nil)
    }

    @Test func aDoctorThatCantRunSaysSo() async throws {
        let fake = try FakeTV(env: ["FAKETV_JUNK": "1"])
        let doctor = Doctor(model: AppModel(tv: fake.tv))
        await doctor.run()
        #expect(doctor.report == nil && doctor.problem != nil)
    }
}
