import AppKit

/// Only one copy of the app runs at a time: two would share one box, and
/// quitting either would stop it. When a second copy opens, the newer one
/// stays.

/// A copy's version, as its Info.plist gives it.
struct AppVersion: Equatable {
    var short: String
    var build: Int
    /// A development build: no Sparkle key, and always "0.1.0".
    var isDevelopment: Bool

    init(short: String, build: Int, isDevelopment: Bool) {
        self.short = short
        self.build = build
        self.isDevelopment = isDevelopment
    }

    init(info: [String: Any]) {
        short = info["CFBundleShortVersionString"] as? String ?? "0"
        build = Int(info["CFBundleVersion"] as? String ?? "") ?? 0
        isDevelopment = (info["SUPublicEDKey"] as? String ?? "").isEmpty
    }

    /// The version as numbers, then the build: 0.1.10 comes after 0.1.9.
    fileprivate var parts: [Int] {
        var numbers = short.split(separator: ".").map { Int($0) ?? 0 }
        while numbers.count < 3 { numbers.append(0) }
        return numbers + [build]
    }
}

enum Arrival: Equatable {
    /// The newcomer quits, leaving the running copy.
    case stepAside
    /// The running copy quits, leaving the newcomer.
    case takeOver
}

/// What a newly opened copy does about one already running. A development
/// build on either side means the newcomer stays, so a build being tried
/// out replaces the installed app, and opening the installed app puts it
/// back. Otherwise the newcomer stays only if it's newer.
func arrival(newcomer: AppVersion, running: AppVersion) -> Arrival {
    if newcomer.isDevelopment || running.isDevelopment { return .takeOver }
    return newcomer.parts.lexicographicallyPrecedes(running.parts) || newcomer.parts == running.parts
        ? .stepAside : .takeOver
}

/// The notice a newcomer sends to the copies it replaces. A copy that gets
/// it quits at once, leaving the box running for the newcomer.
let stepAsideNotice = Notification.Name("org.terminalvalues.TerminalValues.stepAside")

/// Other copies of this app running now.
@MainActor
func otherCopies() -> [NSRunningApplication] {
    guard let id = Bundle.main.bundleIdentifier else { return [] }
    return NSRunningApplication.runningApplications(withBundleIdentifier: id)
        .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
}

@MainActor
func version(of copy: NSRunningApplication) -> AppVersion {
    guard let url = copy.bundleURL, let info = NSDictionary(contentsOf: url.appending(path: "Contents/Info.plist"))
    else { return AppVersion(short: "0", build: 0, isDevelopment: false) }
    return AppVersion(info: info as? [String: Any] ?? [:])
}

/// The running copy this one should give way to, if any.
@MainActor
func copyToStepAsideFor(among others: [NSRunningApplication]) -> NSRunningApplication? {
    let mine = AppVersion(info: Bundle.main.infoDictionary ?? [:])
    return others.first { arrival(newcomer: mine, running: version(of: $0)) == .stepAside }
}

/// Asks the other copies to quit, and makes them if they don't within a few
/// seconds (copies from before the notice existed don't know it). Either
/// way the box keeps running, for this copy to take over.
@MainActor
func takeOver(from others: [NSRunningApplication]) async {
    guard !others.isEmpty else { return }
    DistributedNotificationCenter.default().postNotificationName(
        stepAsideNotice, object: nil,
        userInfo: ["pid": Int(ProcessInfo.processInfo.processIdentifier)], deliverImmediately: true)
    if await waitForQuit(others, seconds: 5) { return }
    for copy in others where !copy.isTerminated { copy.forceTerminate() }
    _ = await waitForQuit(others, seconds: 5)
}

@MainActor
private func waitForQuit(_ copies: [NSRunningApplication], seconds: Int) async -> Bool {
    for _ in 0..<(seconds * 10) {
        if copies.allSatisfy(\.isTerminated) { return true }
        try? await Task.sleep(for: .milliseconds(100))
    }
    return copies.allSatisfy(\.isTerminated)
}
