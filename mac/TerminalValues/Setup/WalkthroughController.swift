import AppKit
import Foundation
import Observation

/// Runs the walkthrough: which step, what the member typed, and the tv
/// commands behind each step. What only the app knows is kept in
/// UserDefaults, so quitting halfway resumes in the right place.
@MainActor @Observable
final class WalkthroughController {
    let model: AppModel
    var step: SetupStep = .welcome
    var login = ""
    var name = ""
    var email = ""
    var identity: Identity?
    var message: String?
    var working: String?
    /// The first catch-up failed: the Filling step offers Try Again.
    var fillFailed = false
    private let defaults: UserDefaults

    init(model: AppModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
    }

    private func flag(_ key: String) -> Bool { defaults.bool(forKey: key) }
    private func set(_ key: String, _ on: Bool = true) { defaults.set(on, forKey: key) }
    var welcomeSeen: Bool { flag("welcomeSeen") }
    var keySaved: Bool { flag("keySaved") }
    var firstCatchUpDone: Bool { flag("firstCatchUpDone") }

    /// The walkthrough shows for a computer that hasn't joined, or one that
    /// started it and hasn't finished; members who joined before the app
    /// never see it.
    /// Until tv has said where things stand, it doesn't show.
    var shouldShow: Bool {
        guard model.status != nil else { return false }
        return !model.isSetUp || (flag("walkthroughStarted") && !flag("walkthroughFinished"))
    }

    func resume() async {
        await model.refresh()
        if model.status != nil && !model.isSetUp {
            set("walkthroughStarted")
            // A computer that has left (tv uninstall, a new join) starts afresh:
            // its new key is a new key to save.
            for k in ["keySaved", "firstCatchUpDone", "walkthroughFinished", "keySkipped"] { set(k, false) }
        }
        model.keyNotSaved = flag("keySkipped") && !keySaved
        step = resumeStep(check: model.check ?? .noRuntime, status: model.status, keySaved: keySaved,
                          firstCatchUpDone: firstCatchUpDone, welcomeSeen: welcomeSeen)
        if step == .tellDanny || step == .saveKey { await loadIdentity() }
    }

    func go(_ next: SetupStep) { message = nil; step = next }

    // 1. Welcome
    func welcomeDone() { set("welcomeSeen"); Task { await resume() } }

    // 2. The runtime
    func installRuntime() async {
        working = "Fetching Apple's installer…"
        defer { working = nil }
        do {
            let pkg = try await RuntimeInstaller.latestInstaller()
            try RuntimeInstaller.verify(pkg)
            RuntimeInstaller.open(pkg)
            working = "Waiting for the installer to finish…"
            for _ in 0..<300 {  // up to ten minutes
                try await Task.sleep(for: .seconds(2))
                if let c = try? await model.tv.check(), c != .noRuntime { break }
            }
            await startRuntime()
        } catch {
            message = "\(error)"
        }
    }

    func startRuntime() async {
        working = "Starting the runtime (the first time, it fetches a small Linux kernel)…"
        defer { working = nil }
        if let r = try? await model.tv.run(["runtime-start"], timeout: .seconds(600)), r.status != 0 {
            message = r.stderr.isEmpty ? r.stdout : r.stderr
        }
        await resume()
    }

    // 3. About you
    var aboutYouReady: Bool { SetupStep.isGoodLogin(login) && !name.isEmpty && email.contains("@") }

    // 4. The invitation: tv watches the clipboard (a minute at a time, since
    // it has no terminal here) until the member copies it.
    func watchForInvitation() async {
        working = "Watching the clipboard…"
        defer { working = nil }
        while step == .invitation && !Task.isCancelled {
            let r: TVResult
            do {
                r = try await model.tv.run(
                    ["join", "--from-clipboard", "--login", login, "--name", name, "--email", email],
                    timeout: .seconds(600))
            } catch {
                message = "\(error)"  // stop here, rather than try again at once
                return
            }
            if r.status == 0 {
                await model.refresh()
                await loadIdentity()
                go(.tellDanny)
                return
            }
            if !r.stderr.contains("no invitation on the clipboard") {
                message = r.stderr.isEmpty ? r.stdout : r.stderr
                return
            }
        }
    }

    // 5. Tell Danny
    func loadIdentity() async {
        identity = try? await model.tv.json(Identity.self, ["identity", "--json"])
    }

    var threeLines: String {
        guard let i = identity else { return "" }
        return "login: \(i.login)\nsyncthing: \(i.syncthing)\nage: \(i.age)"
    }

    func copyThreeLines() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(threeLines, forType: .string)
    }

    // 6. Save the key
    func saveKey(to file: URL) async {
        try? FileManager.default.removeItem(at: file)  // the save panel asked about replacing it
        guard let r = try? await model.tv.run(["export-key", file.path]), r.status == 0 else {
            message = "The key couldn't be saved there."
            return
        }
        set("keySaved")
        set("keySkipped", false)
        model.keyNotSaved = false
        await resume()
    }

    func skipKey() {
        set("keySkipped")
        model.keyNotSaved = true
        go(.waiting)
        Task { await waitForDanny() }
    }

    // 7. Waiting for Danny
    func waitForDanny() async {
        while step == .waiting && !Task.isCancelled {
            await model.refresh()
            if let s = model.status?.sync, s.connected, s.shared { go(.filling); await fill(); return }
            try? await Task.sleep(for: .seconds(60))
        }
    }

    // 8. Filling the folder. The first catch-up has nothing to review: it
    // takes what's on tvhome, as the first one always has.
    func fill() async {
        fillFailed = false
        if !firstCatchUpDone {
            working = "Fetching TV's code and documents…"
            defer { working = nil }
            do {
                let r = try await model.tv.run(["catch-up", "--yes"], timeout: .seconds(600))
                guard r.status == 0 else {
                    message = r.stderr.isEmpty ? r.stdout : r.stderr
                    fillFailed = true
                    return
                }
                set("firstCatchUpDone")
                message = nil
            } catch {
                message = "\(error)"
                fillFailed = true
                return
            }
        }
        while step == .filling && !Task.isCancelled {
            await model.refresh()
            if let s = model.status?.sync, s.needFiles == 0, !s.waitingForList { go(.done); return }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    // 9. Done
    func finish() {
        set("walkthroughFinished")
        model.tutorialRequested = true
    }
}
