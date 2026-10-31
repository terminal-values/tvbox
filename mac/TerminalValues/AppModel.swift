import Foundation
import Observation

enum QuitDecision: Equatable { case stopAndQuit, ask }

enum ApplyOutcome: Equatable {
    case applied
    /// tvhome has more since the changes were shown: show them again.
    case tvhomeMoved
    case clash(String)
    case failed(String)
}

/// What the app knows about this computer's box, and the things it does to
/// it. Every fact comes from tv; every action is a tv command.
@MainActor @Observable
final class AppModel {
    let tv: TV

    var check: CheckState?
    var status: Status?
    var stats: Stats?
    var changes: Changes?
    var pendingCodeChanges = 0
    var updateAvailable = false
    var keyNotSaved = false
    /// The commit the box was built from, as tv update --check reports it.
    var boxRevision: String?
    /// The box image this release of the app was built with (nil for a
    /// development build). With it, the box to have is that one, not main's.
    var pinned: BoxImage?
    var busy: String?
    /// Why the last refresh got nothing from tv, in words (nil when it worked).
    var statusProblem: String?
    /// Set to ask for the main window; the menu bar icon's view opens it,
    /// since only SwiftUI views can open a window scene.
    var wantsWindow = false
    /// The walkthrough has finished: time for the tutorial.
    var tutorialRequested = false
    /// Asked for from elsewhere (the Doctor): the review sheet, an update.
    var reviewRequested = false
    var updateRequested = false
    var lastError: String?

    /// Joined: tv knows a login for this computer.
    var isSetUp: Bool { !(status?.login.isEmpty ?? true) }
    var isRunning: Bool { status?.box == .running }
    var needsAttention: Bool { pendingCodeChanges > 0 || updateAvailable || keyNotSaved || !isSetUp }

    private var polling: Task<Void, Never>?
    private var gauges: Task<Void, Never>?
    /// How often the window's gauges refresh while it's showing.
    var statsInterval: Duration = .seconds(3)

    init(tv: TV) { self.tv = tv }

    /// Opening the app: once set up, the runtime and the box start without
    /// asking (a box already running, say from a terminal, is adopted).
    /// Before setup nothing starts; the walkthrough is in charge.
    func launch(atLogin: Bool) async {
        await refresh()
        guard isSetUp else { return }
        if check == .runtimeStopped {
            await perform("Starting the container runtime…") { try await self.tv.run(["runtime-start"], timeout: .seconds(300)) }
            await refresh()
        }
        if check == .stopped { await startBox() }
        await refreshSlow()
    }

    func startBox() async {
        await perform("Starting the box…") { try await self.tv.run(["start"], timeout: .seconds(300)) }
        await refresh()
    }

    func stopBox() async {
        await perform("Stopping the box…") { try await self.tv.run(["stop"], timeout: .seconds(120)) }
        await refresh()
    }

    /// The quick facts, every 30 seconds.
    func refresh() async {
        check = try? await tv.check()
        do {
            status = try await tv.json(Status.self, ["status", "--json"])
            statusProblem = nil
        } catch {
            statusProblem = "\(error)"
        }
    }

    /// The slower ones, every 15 minutes: code waiting on tvhome, a newer box.
    func refreshSlow() async {
        guard isRunning else { return }
        if let c = try? await tv.json(Changes.self, ["changes"], timeout: .seconds(60)) {
            changes = c
            pendingCodeChanges = c.code.incoming.count
        }
        // A release's updates come through Sparkle, with the box it pins.
        guard pinned == nil else { updateAvailable = false; return }
        if let u = try? await tv.json(UpdateCheck.self, ["update", "--check", "--json"], timeout: .seconds(60)) {
            updateAvailable = u.available
            boxRevision = u.current
        }
    }

    /// CPU and memory are read only while someone is looking.
    func menuOpened() async {
        guard isRunning || status == nil else { return }
        stats = try? await tv.json(Stats.self, ["stats", "--json", "--no-disk"], timeout: .seconds(15))
    }

    /// Applies exactly the changes that were shown, or nothing.
    func applyChanges(_ shown: Changes) async -> ApplyOutcome {
        var args = ["catch-up", "--yes", "--to", shown.code.to]
        if let s = shown.secrets.to { args += ["--secrets-to", s] }
        busy = "Catching up…"
        defer { busy = nil }
        guard let r = try? await tv.run(args, timeout: .seconds(300)) else {
            return .failed("tv catch-up didn't finish.")
        }
        let words = (r.stdout + "\n" + r.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        switch r.status {
        case 0:
            await refresh()
            await refreshSlow()
            return .applied
        case 4:
            await refreshSlow()
            if let c = try? await tv.json(Changes.self, ["changes"], timeout: .seconds(60)) {
                changes = c
                pendingCodeChanges = c.code.incoming.count
            }
            return .tvhomeMoved
        default:
            return words.contains("clash") ? .clash(words) : .failed(words)
        }
    }

    /// The window's gauges: CPU and memory every few seconds while it shows,
    /// disk (slower to measure) when it opens and once a minute.
    func windowVisible(_ visible: Bool) {
        gauges?.cancel()
        guard visible else { gauges = nil; return }
        gauges = Task { [weak self] in
            var n = 0
            while !Task.isCancelled {
                guard let self else { return }
                if self.isRunning {
                    let args = n % 20 == 0 ? ["stats", "--json"] : ["stats", "--json", "--no-disk"]
                    if let st = try? await self.tv.json(Stats.self, args, timeout: .seconds(20)) {
                        self.stats = Stats(cpuPercent: st.cpuPercent, memoryBytes: st.memoryBytes,
                                           diskBytes: st.diskBytes ?? self.stats?.diskBytes)
                    }
                }
                n += 1
                try? await Task.sleep(for: self.statsInterval)
            }
        }
    }

    func quitRequested(terminalBusy: Bool) -> QuitDecision { terminalBusy ? .ask : .stopAndQuit }

    /// Quitting stops the box, whoever started it.
    func prepareToQuit() async {
        polling?.cancel()
        if isRunning || status == nil { await stopBox() }
    }

    func startPolling() {
        polling?.cancel()
        polling = Task { [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                await self.refresh()
                ticks += 1
                if ticks % 30 == 0 { await self.refreshSlow() }
            }
        }
    }

    /// Runs one action, showing what's happening and any failure in words.
    private func perform(_ what: String, _ action: @escaping () async throws -> TVResult) async {
        busy = what
        defer { busy = nil }
        do {
            let r = try await action()
            lastError = r.status == 0 ? nil : (r.stderr.isEmpty ? r.stdout : r.stderr)
        } catch {
            lastError = "\(error)"
        }
    }
}
