import Foundation
import Testing
@testable import TerminalValues

/// The Finder extension follows tv move by watching tv's config directory;
/// write_config replaces the file by rename, which this must notice.
@Suite struct DirectoryWatcherTests {
    @Test(.timeLimit(.minutes(1))) func noticesAConfigReplacedByRename() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "tv-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = dir.appending(path: "config")
        try "FOLDER='/tmp/old'\n".write(to: config, atomically: false, encoding: .utf8)

        let (changes, changed) = AsyncStream.makeStream(of: Void.self)
        let watcher = try #require(DirectoryWatcher(directory: dir, queue: DispatchQueue(label: "test")) {
            changed.yield()
        })
        // As write_config does: write config.tmp, then mv it over config.
        let tmp = dir.appending(path: "config.tmp")
        try "FOLDER='/tmp/new'\n".write(to: tmp, atomically: false, encoding: .utf8)
        #expect(rename(tmp.path, config.path) == 0)
        var it = changes.makeAsyncIterator()
        await it.next()
        #expect(TVLink.folder(fromConfig: try String(contentsOf: config, encoding: .utf8)) == "/tmp/new")
        withExtendedLifetime(watcher) {}
    }

    @Test func noDirectoryNoWatcher() {
        #expect(DirectoryWatcher(directory: URL(fileURLWithPath: "/nonexistent/tv"), queue: .main) {} == nil)
    }
}
