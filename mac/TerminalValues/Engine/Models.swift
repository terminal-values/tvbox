import Foundation

// What tv prints with --json (tvbox's tests pin each shape). Keys arrive in
// snake_case and are decoded with .convertFromSnakeCase.

enum CheckState: String, Sendable {
    case noRuntime = "no-runtime", runtimeStopped = "runtime-stopped", notJoined = "not-joined"
    case stopped, running
}

enum BoxState: String, Codable, Sendable { case running, stopped, absent }
enum TailnetState: String, Codable, Sendable {
    case on, connecting, offline, notJoined = "not-joined"
}

struct Sync: Codable, Sendable, Equatable {
    var connected: Bool
    var shared: Bool
    var waitingForList: Bool
    var files: Int
    var needFiles: Int
    var needBytes: Int
    var sending: Int
}

struct Status: Codable, Sendable, Equatable {
    var box: BoxState
    var runtime: String
    var runtimeRunning: Bool
    var login: String
    var name: String
    var folder: String
    var port: Int
    /// The commit the box was built from (absent from an older tv).
    var revision: String? = nil
    var tailnet: TailnetState?
    var sync: Sync?
}

struct Stats: Codable, Sendable, Equatable {
    var cpuPercent: Double
    var memoryBytes: Int
    var diskBytes: Int?
}

struct Commit: Codable, Sendable, Equatable, Identifiable {
    var sha: String?
    var author: String
    var subject: String
    var when: String
    var id: String { (sha ?? "") + when + subject }
}

struct MyCommit: Codable, Sendable, Equatable {
    var sha: String
    var subject: String
}

struct CodeChanges: Codable, Sendable, Equatable {
    var to: String
    var incoming: [Commit]
    var files: [String]
    var mine: [MyCommit]
    var diff: String?
}

struct SecretsChanges: Codable, Sendable, Equatable {
    var to: String?
    var readersDiff: String?
    var mine: Int
}

struct Changes: Codable, Sendable, Equatable {
    var code: CodeChanges
    var secrets: SecretsChanges
    var recent: [Commit]
}

struct Identity: Codable, Sendable, Equatable {
    var login: String
    var syncthing: String
    var age: String
}

struct UpdateCheck: Codable, Sendable, Equatable {
    var current: String?
    var latest: String
    var available: Bool
    var commits: [String]
}

enum DoctorStatus: String, Codable, Sendable { case ok, warning, problem }
enum DoctorFix: String, Codable, Sendable {
    case startRuntime = "start-runtime", startBox = "start-box", catchUp = "catch-up", update
}

struct DoctorResult: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var status: DoctorStatus
    var message: String
    var fix: DoctorFix?
}

struct DoctorReport: Codable, Sendable, Equatable {
    var results: [DoctorResult]
}
