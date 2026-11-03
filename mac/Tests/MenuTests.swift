import Testing
@testable import TerminalValues

/// The menu's grey status line, which also says which app and box this is.
@MainActor @Suite struct MenuTests {
    @Test func theVersionIsTheAppsAndTheBoxsCommit() {
        #expect(AppVersion(short: "0.1.16", build: 300, isDevelopment: false).tag(box: "ffedefr0123456789") == "v0.1.16/ffedefr")
    }

    // A development build always says 0.1.0, which would mislead.
    @Test func aDevelopmentBuildSaysDev() {
        #expect(AppVersion(short: "0.1.0", build: 1, isDevelopment: true).tag(box: "ffedefr0123") == "dev/ffedefr")
    }

    @Test func noBoxCommitYetLeavesItOff() {
        #expect(AppVersion(short: "0.1.16", build: 300, isDevelopment: false).tag(box: nil) == "v0.1.16")
    }

    @Test func theRunningLineEndsWithTheVersion() async throws {
        let fake = try FakeTV(answers: ["check": "running\n", "status": Fixture.statusRunning])
        let model = AppModel(tv: fake.tv)
        await model.refresh()
        model.boxRevision = "ffedefr0123"
        let line = MenuContent.statusLine(model, app: AppVersion(short: "0.1.16", build: 300, isDevelopment: false))
        #expect(line == "TV Box running · up to date · v0.1.16/ffedefr")
    }

    @Test func theFooterSaysTheSame() async throws {
        let fake = try FakeTV(answers: ["check": "running\n", "status": Fixture.statusRunning])
        let model = AppModel(tv: fake.tv)
        await model.refresh()
        model.boxRevision = "ffedefr0123"
        #expect(FooterView.tag(model, app: AppVersion(short: "0.1.16", build: 300, isDevelopment: false)) == "v0.1.16/ffedefr")
    }
}
