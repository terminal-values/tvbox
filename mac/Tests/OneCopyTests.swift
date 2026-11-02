import Testing
@testable import TerminalValues

/// Which copy stays when a second copy of the app opens.
@Suite struct OneCopyTests {
    func release(_ v: String, build: Int = 100) -> AppVersion { AppVersion(short: v, build: build, isDevelopment: false) }
    let dev = AppVersion(short: "0.1.0", build: 1, isDevelopment: true)

    @Test func aNewerReleaseTakesOver() {
        #expect(arrival(newcomer: release("0.1.7"), running: release("0.1.6")) == .takeOver)
    }

    @Test func anOlderReleaseStepsAside() {
        #expect(arrival(newcomer: release("0.1.6"), running: release("0.1.7")) == .stepAside)
    }

    @Test func theSameReleaseStepsAside() {
        #expect(arrival(newcomer: release("0.1.7"), running: release("0.1.7")) == .stepAside)
    }

    @Test func versionsCompareAsNumbersNotText() {
        #expect(arrival(newcomer: release("0.1.10"), running: release("0.1.9")) == .takeOver)
        #expect(arrival(newcomer: release("0.2"), running: release("0.1.9")) == .takeOver)
    }

    @Test func theBuildNumberBreaksATie() {
        #expect(arrival(newcomer: release("0.1.7", build: 101), running: release("0.1.7", build: 100)) == .takeOver)
    }

    // A development build always wins as the newcomer, and loses to any
    // copy opened after it.
    @Test func aDevelopmentBuildTakesOverFromARelease() {
        #expect(arrival(newcomer: dev, running: release("9.9.9")) == .takeOver)
    }

    @Test func aReleaseTakesOverFromADevelopmentBuild() {
        #expect(arrival(newcomer: release("0.0.1"), running: dev) == .takeOver)
    }

    @Test func aDevelopmentBuildTakesOverFromAnother() {
        #expect(arrival(newcomer: dev, running: dev) == .takeOver)
    }

    @Test func versionsAreReadFromTheBundle() {
        let v = AppVersion(info: ["CFBundleShortVersionString": "0.1.7", "CFBundleVersion": "212",
                                  "SUPublicEDKey": "abc"])
        #expect(v == release("0.1.7", build: 212))
        let d = AppVersion(info: ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1",
                                  "SUPublicEDKey": ""])
        #expect(d.isDevelopment)
    }
}
