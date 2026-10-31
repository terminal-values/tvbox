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

        let box = ProcessBox(process)
        let ended = AsyncStream<Void> { continuation in
            process.terminationHandler = { _ in continuation.yield(); continuation.finish() }
        }
        try process.run()
        // Read both pipes while it runs, so a full pipe can't stall it.
        async let stdoutData = Self.readAll(out.fileHandleForReading)
        async let stderrData = Self.readAll(err.fileHandleForReading)
        if let stdin { try? input.fileHandleForWriting.write(contentsOf: stdin) }
        try? input.fileHandleForWriting.close()

        let finished = await withTaskGroup(of: Bool.self) { group in
            group.addTask { for await _ in ended {}; return true }
            group.addTask { try? await Task.sleep(for: timeout); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        if !finished {
            box.terminate()
            _ = await (stdoutData, stderrData)
            throw TVError.timedOut(args)
        }
        let (o, e) = await (stdoutData, stderrData)
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

    private static func readAll(_ handle: FileHandle) async -> Data {
        await Task.detached { (try? handle.readToEnd()) ?? Data() }.value
    }
}

/// Process isn't Sendable; this lets the timeout stop it.
private final class ProcessBox: @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }
    func terminate() { if process.isRunning { process.terminate() } }
}
