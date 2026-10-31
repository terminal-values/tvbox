import Foundation
import Observation

enum QuitDecision: Equatable { case stopAndQuit, ask }

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
    var busy: String?
    var lastError: String?

    /// Joined: tv knows a login for this computer.
    var isSetUp: Bool { !(status?.login.isEmpty ?? true) }
    var isRunning: Bool { status?.box == .running }
    var needsAttention: Bool { pendingCodeChanges > 0 || updateAvailable || keyNotSaved || !isSetUp }

    private var polling: Task<Void, Never>?

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
        if let s = try? await tv.json(Status.self, ["status", "--json"]) { status = s }
    }

    /// The slower ones, every 15 minutes: code waiting on tvhome, a newer box.
    func refreshSlow() async {
        guard isRunning else { return }
        if let c = try? await tv.json(Changes.self, ["changes"], timeout: .seconds(60)) {
            changes = c
            pendingCodeChanges = c.code.incoming.count
        }
        if let u = try? await tv.json(UpdateCheck.self, ["update", "--check", "--json"], timeout: .seconds(60)) {
            updateAvailable = u.available
        }
    }

    /// CPU and memory are read only while someone is looking.
    func menuOpened() async {
        guard isRunning || status == nil else { return }
        stats = try? await tv.json(Stats.self, ["stats", "--json", "--no-disk"], timeout: .seconds(15))
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
