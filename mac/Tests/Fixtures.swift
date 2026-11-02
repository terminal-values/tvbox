import Foundation
@testable import TerminalValues

/// JSON as tv prints it (shapes from tvbox's own tests, Tasks 1–5).
enum Fixture {
    static let statusRunning = """
    {"box": "running", "runtime": "container", "runtime_running": true, "login": "sam", "name": "Sam Smith", "folder": "/Users/sam/Documents/terminalvalues", "port": 8484, "tailnet": "on", "sync": {"connected": true, "shared": true, "waiting_for_list": false, "files": 11, "need_files": 0, "need_bytes": 0, "sending": 0}}
    """
    static let statusStopped = """
    {"box": "stopped", "runtime": "container", "runtime_running": true, "login": "sam", "name": "Sam Smith", "folder": "/Users/sam/Documents/terminalvalues", "port": 8484, "tailnet": null, "sync": null}
    """
    static let stats = """
    {"cpu_percent": 3.0, "memory_bytes": 408944640, "disk_bytes": null}
    """
    static let changes = """
    {"code": {"to": "abc123", "incoming": [{"sha": "abc123", "author": "Alex Example", "subject": "Add the March receipts", "when": "2026-10-30T09:00:00+00:00"}], "files": ["bin/import-receipts"], "mine": [], "diff": null}, "secrets": {"to": "def456", "readers_diff": null, "mine": 0}, "recent": [{"author": "Alex Example", "subject": "Add the March receipts", "when": "2026-10-30T09:00:00+00:00"}]}
    """
    static let identity = """
    {"login": "sam", "syncthing": "MVOEDBP-QTCGNI7-Q6ZZW22-HCGLNE5-5EQZ4NS-5USUULU-D7EIS4I-J2Q3EQX", "age": "age1abc"}
    """
    static let updateCheck = """
    {"current": "aaa", "latest": "bbb", "available": true, "commits": ["Make the box smaller", "Fix tv status"]}
    """
    static let doctor = """
    {"results": [{"id": "runtime", "status": "problem", "message": "container isn't running.", "fix": "start-runtime"}, {"id": "box", "status": "ok", "message": "The box is running.", "fix": null}]}
    """
}

/// A scratch directory for faketv, and a TV that runs it.
struct FakeTV {
    let dir: URL
    let tv: TerminalValues.TV

    init(answers: [String: String] = [:], exits: [String: Int32] = [:], env: [String: String] = [:]) throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("faketv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (cmd, out) in answers { try out.write(to: dir.appendingPathComponent("\(cmd).out"), atomically: true, encoding: .utf8) }
        for (cmd, code) in exits { try "\(code)".write(to: dir.appendingPathComponent("\(cmd).exit"), atomically: true, encoding: .utf8) }
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("faketv")
        tv = TerminalValues.TV(executable: script, environment: ["FAKETV_DIR": dir.path].merging(env) { $1 })
    }

    /// Each call's arguments, in order.
    var calls: [String] {
        ((try? String(contentsOf: dir.appendingPathComponent("calls.log"), encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
    }
}
