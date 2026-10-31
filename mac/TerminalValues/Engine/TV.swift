import Foundation

/// What a run of tv gave back.
struct TVResult: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String
}

enum TVError: Error, Sendable, CustomStringConvertible {
    case timedOut([String])
    case failed(Int32, String)
    case badOutput([String], String)

    var description: String {
        switch self {
        case .timedOut(let args): "tv \(args.first ?? "") took too long."
        case .failed(_, let stderr): stderr.isEmpty ? "tv didn't manage it." : stderr
        case .badOutput(let args, _): "tv \(args.first ?? "") answered with something the app didn't understand."
        }
    }
}

/// The app's one way to do anything: run tv. Everything else in the app is a
/// face on what this returns. Input (an invitation, say) goes on stdin, never
/// in the arguments, and is never logged.
actor TV {
    let executable: URL
    let environment: [String: String]

    /// Where runtimes live; GUI apps start with a bare PATH.
    static let path = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    init(executable: URL, environment: [String: String] = [:]) {
        self.executable = executable
        self.environment = environment
    }

    /// The tv inside this app.
    static var bundled: TV {
        TV(executable: Bundle.main.url(forResource: "tv", withExtension: nil)!)
    }

    func run(_ args: [String], stdin: Data? = nil, timeout: Duration = .seconds(30)) async throws -> TVResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Self.path
        env.merge(environment) { $1 }
        process.environment = env
        let out = Pipe(), err = Pipe(), input = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = input

        try process.run()
        // Read both pipes while it runs, so a full pipe can't stall it.
        async let stdoutData = Self.readAll(out.fileHandleForReading)
        async let stderrData = Self.readAll(err.fileHandleForReading)
        if let stdin { try? input.fileHandleForWriting.write(contentsOf: stdin) }
        try? input.fileHandleForWriting.close()

        // Cancellation (a window closing, Quit) doesn't stop tv: a half-done
        // catch-up or join is worse than a wasted one. Only the time limit does.
        let exited = await waitForExit(process, timeout: timeout)
        let (o, e) = await (stdoutData, stderrData)
        guard exited else { throw TVError.timedOut(args) }
        return TVResult(status: process.terminationStatus,
                        stdout: String(decoding: o, as: UTF8.self),
                        stderr: String(decoding: e, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Run tv and decode its JSON; a failure or anything else is a TVError.
    func json<T: Decodable>(_ type: T.Type, _ args: [String], timeout: Duration = .seconds(30)) async throws -> T {
        let r = try await run(args, timeout: timeout)
        guard r.status == 0 else { throw TVError.failed(r.status, r.stderr) }
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: Data(r.stdout.utf8))
        } catch {
            throw TVError.badOutput(args, String(r.stdout.prefix(200)))
        }
    }

    /// tv check: where this computer is, in one word.
    func check() async throws -> CheckState {
        let r = try await run(["check"], timeout: .seconds(15))
        let word = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let state = CheckState(rawValue: word) else { throw TVError.badOutput(["check"], word) }
        return state
    }

    /// A blocking read, on a dispatch thread rather than Swift's shared pool,
    /// so many runs at once can't starve it.
    private static func readAll(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { done in
            DispatchQueue.global().async { done.resume(returning: (try? handle.readToEnd()) ?? Data()) }
        }
    }
}

/// Waits for a running process to exit, or for the time limit, whichever is
/// first, and ignores task cancellation. True if it exited by itself; false if
/// the time ran out, in which case it's terminated and waited for, so either
/// way its exit status is readable afterwards.
func waitForExit(_ process: Process, timeout: Duration) async -> Bool {
    let first = FirstOf()
    let exited: Bool = await withCheckedContinuation { done in
        first.set(done)
        process.terminationHandler = { _ in first.resume(true) }
        if !process.isRunning { first.resume(true) }  // gone before the handler was set
        let (secs, atto) = timeout.components
        DispatchQueue.global().asyncAfter(deadline: .now() + Double(secs) + Double(atto) / 1e18) {
            first.resume(false)
        }
    }
    if !exited {
        process.terminate()
        await withCheckedContinuation { done in
            DispatchQueue.global().async { process.waitUntilExit(); done.resume() }
        }
    }
    return exited
}

/// Resumes a continuation once: whichever of exit and time limit comes first.
private final class FirstOf: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var early: Bool?

    func set(_ c: CheckedContinuation<Bool, Never>) {
        lock.withLock {
            if let early { c.resume(returning: early) } else { continuation = c }
        }
    }

    func resume(_ value: Bool) {
        lock.withLock {
            if let c = continuation { continuation = nil; c.resume(returning: value) }
            else if early == nil { early = value }
        }
    }
}
