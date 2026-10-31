import Foundation
import Testing
@testable import TerminalValues

@MainActor @Suite struct TerminalTests {
    @Test func busyWhileACommandRuns() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tv folder \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let session = TerminalSession(tvDirectory: URL(fileURLWithPath: "/usr/bin"))
        session.start(in: folder, shell: "/bin/sh")
        try await Task.sleep(for: .milliseconds(500))
        #expect(!session.isBusy)
        session.type("sleep 2\n")
        try await Task.sleep(for: .milliseconds(700))
        #expect(session.isBusy)
        try await Task.sleep(for: .seconds(2))
        #expect(!session.isBusy)
    }

    @Test func startsInTheFolderWithTvOnThePath() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tv folder \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let tvDir = FileManager.default.temporaryDirectory.appendingPathComponent("tvbin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tvDir, withIntermediateDirectories: true)
        let session = TerminalSession(tvDirectory: tvDir)
        session.start(in: folder, shell: "/bin/sh")
        try await Task.sleep(for: .milliseconds(500))
        let out = folder.appendingPathComponent("where.txt")
        session.type("pwd > where.txt; echo \"$PATH\" >> where.txt\n")
        try await Task.sleep(for: .milliseconds(700))
        let lines = try String(contentsOf: out, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(URL(fileURLWithPath: lines[0]).resolvingSymlinksInPath() == folder.resolvingSymlinksInPath())
        #expect(lines[1].split(separator: ":").contains(Substring(tvDir.path)))
    }
}
