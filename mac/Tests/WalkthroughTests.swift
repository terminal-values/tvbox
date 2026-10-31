import Foundation
import Testing
@testable import TerminalValues

@Suite struct WalkthroughTests {
    static func status(login: String = "sam", box: BoxState = .running, connected: Bool = true,
                       shared: Bool = true, needFiles: Int = 0) -> Status {
        Status(box: box, runtime: "container", runtimeRunning: true, login: login, name: "Sam",
               folder: "/tmp/tv", port: 8484, tailnet: box == .running ? .on : nil,
               sync: box == .running ? Sync(connected: connected, shared: shared, waitingForList: false,
                                            files: 11, needFiles: needFiles, needBytes: 0, sending: 0) : nil)
    }

    struct Row: Sendable, CustomStringConvertible {
        let check: CheckState, status: Status?, keySaved: Bool, caughtUp: Bool, welcomeSeen: Bool
        let expect: SetupStep
        var description: String { "\(check) → \(expect)" }
    }

    static let rows: [Row] = [
        Row(check: .noRuntime, status: nil, keySaved: false, caughtUp: false, welcomeSeen: false, expect: .welcome),
        Row(check: .noRuntime, status: nil, keySaved: false, caughtUp: false, welcomeSeen: true, expect: .runtime),
        Row(check: .runtimeStopped, status: nil, keySaved: false, caughtUp: false, welcomeSeen: true, expect: .runtime),
        Row(check: .notJoined, status: status(login: ""), keySaved: false, caughtUp: false, welcomeSeen: false, expect: .welcome),
        Row(check: .notJoined, status: status(login: ""), keySaved: false, caughtUp: false, welcomeSeen: true, expect: .aboutYou),
        Row(check: .running, status: status(), keySaved: false, caughtUp: false, welcomeSeen: true, expect: .saveKey),
        Row(check: .running, status: status(shared: false), keySaved: true, caughtUp: false, welcomeSeen: true, expect: .waiting),
        Row(check: .running, status: status(connected: false), keySaved: true, caughtUp: false, welcomeSeen: true, expect: .waiting),
        Row(check: .stopped, status: status(box: .stopped), keySaved: true, caughtUp: false, welcomeSeen: true, expect: .waiting),
        Row(check: .running, status: status(), keySaved: true, caughtUp: false, welcomeSeen: true, expect: .filling),
        Row(check: .running, status: status(needFiles: 4), keySaved: true, caughtUp: true, welcomeSeen: true, expect: .filling),
        Row(check: .running, status: status(), keySaved: true, caughtUp: true, welcomeSeen: true, expect: .done),
    ]

    @Test(arguments: rows) func resumeStepCoversEveryState(_ row: Row) {
        #expect(resumeStep(check: row.check, status: row.status, keySaved: row.keySaved,
                           firstCatchUpDone: row.caughtUp, welcomeSeen: row.welcomeSeen) == row.expect)
    }

    // Review Focus: quit halfway, reopen later: back where the computer really is.
    @Test func resumesAfterQuitMidJoin() {
        #expect(resumeStep(check: .running, status: Self.status(), keySaved: false,
                           firstCatchUpDone: false, welcomeSeen: true) == .saveKey)
        #expect(resumeStep(check: .running, status: Self.status(shared: false), keySaved: true,
                           firstCatchUpDone: false, welcomeSeen: true) == .waiting)
    }

    @Test func loginNamesAreCheckedAsTvChecksThem() {
        #expect(SetupStep.isGoodLogin("sam") && SetupStep.isGoodLogin("sam-2"))
        #expect(!SetupStep.isGoodLogin("Sam") && !SetupStep.isGoodLogin("2sam") && !SetupStep.isGoodLogin("sam smith")
                && !SetupStep.isGoodLogin(""))
    }
}

@Suite struct RuntimeInstallerTests {
    @Test func acceptsOnlyApplesSignedPackage() {
        let apple = """
        Package "container-installer-signed.pkg":
           Status: signed by a developer certificate issued by Apple for distribution
           Notarization: trusted by the Apple notary service
           Certificate Chain:
            1. Developer ID Installer: Apple Inc. (7QF6KYP6Z9)
        """
        #expect(RuntimeInstaller.isApplesPackage(pkgutilOutput: apple))
        let other = apple.replacingOccurrences(of: "Apple Inc. (7QF6KYP6Z9)", with: "Mallory Ltd (ABCDE12345)")
        #expect(!RuntimeInstaller.isApplesPackage(pkgutilOutput: other))
        #expect(!RuntimeInstaller.isApplesPackage(pkgutilOutput: "Package \"x.pkg\":\n   Status: no signature"))
    }

    @Test func rejectsANonApplePackage() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pkg-\(UUID().uuidString)")
        let root = dir.appendingPathComponent("root")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let pkg = dir.appendingPathComponent("fake.pkg")
        let build = Process()
        build.executableURL = URL(fileURLWithPath: "/usr/bin/pkgbuild")
        build.arguments = ["--root", root.path, "--identifier", "org.example.fake", "--version", "1", pkg.path]
        build.standardOutput = nil; build.standardError = nil
        try build.run(); build.waitUntilExit()
        #expect(throws: (any Error).self) { try RuntimeInstaller.verify(pkg) }
    }

    @Test func picksThePkgAmongReleaseAssets() throws {
        let json = """
        {"tag_name": "0.9.0", "assets": [{"name": "container-0.9.0.tar.gz", "browser_download_url": "https://x/a.tgz"},
                                        {"name": "container-0.9.0-installer-signed.pkg", "browser_download_url": "https://x/b.pkg"}]}
        """
        #expect(try RuntimeInstaller.installerURL(fromRelease: Data(json.utf8)) == URL(string: "https://x/b.pkg"))
    }
}

@MainActor @Suite struct WalkthroughControllerTests {
    static func scratchDefaults() -> UserDefaults {
        let name = "tv-tests-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    // A member who joined before the app existed never sees the walkthrough,
    // even though, for a moment at launch, the app doesn't know yet.
    @Test func aJoinedComputerNeverStartsTheWalkthrough() async throws {
        let fake = try FakeTV(answers: ["check": "running\n", "status": Fixture.statusRunning])
        let model = AppModel(tv: fake.tv)
        let walk = WalkthroughController(model: model, defaults: Self.scratchDefaults())
        #expect(!walk.shouldShow)  // nothing known yet: don't show it
        await walk.resume()
        #expect(!walk.shouldShow)
        await model.refresh()
        #expect(!walk.shouldShow)
    }

    @Test func aNewComputerGetsTheWalkthroughUntilItFinishes() async throws {
        let notJoined = Fixture.statusStopped.replacingOccurrences(of: "\"login\": \"sam\"", with: "\"login\": \"\"")
        let fake = try FakeTV(answers: ["check": "not-joined\n", "status": notJoined])
        let model = AppModel(tv: fake.tv)
        let walk = WalkthroughController(model: model, defaults: Self.scratchDefaults())
        await walk.resume()
        #expect(walk.shouldShow && walk.step == .welcome)
        walk.finish()
        // Joined now, and finished: the everyday window from here on.
        try Fixture.statusRunning.write(to: fake.dir.appendingPathComponent("status.out"), atomically: true, encoding: .utf8)
        await model.refresh()
        #expect(!walk.shouldShow)
    }
}
