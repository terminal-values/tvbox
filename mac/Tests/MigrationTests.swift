import Foundation
import Testing
@testable import TerminalValues

@Suite struct MigrationTests {
    let fm = FileManager.default

    func home() throws -> (URL, URL) {
        let root = fm.temporaryDirectory.appendingPathComponent("mig-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home")
        try fm.createDirectory(at: home.appendingPathComponent(".local/bin"), withIntermediateDirectories: true)
        let bundled = root.appendingPathComponent("Terminal Values.app/Contents/Resources/tv")
        try fm.createDirectory(at: bundled.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: bundled, atomically: true, encoding: .utf8)
        return (home, bundled)
    }

    @Test func replacesAnOrdinaryTvWithTheSymlink() throws {
        let (home, bundled) = try home()
        let tv = home.appendingPathComponent(".local/bin/tv")
        try "#!/bin/sh\necho old\n".write(to: tv, atomically: true, encoding: .utf8)
        let said = try migrate(home: home, bundledTV: bundled, shell: "/bin/zsh")
        #expect(try fm.destinationOfSymbolicLink(atPath: tv.path) == bundled.path)
        #expect(said.contains { $0.contains("~/.local/bin/tv") })
    }

    @Test func leavesACorrectSymlinkAndSaysNothing() throws {
        let (home, bundled) = try home()
        try "export PATH=\"$HOME/.local/bin:$PATH\"  # added by the tvbox installer\n"
            .write(to: home.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(at: home.appendingPathComponent(".local/bin/tv"), withDestinationURL: bundled)
        #expect(try migrate(home: home, bundledTV: bundled, shell: "/bin/zsh").isEmpty)
    }

    @Test func addsThePathLineOnce() throws {
        let (home, bundled) = try home()
        _ = try migrate(home: home, bundledTV: bundled, shell: "/bin/bash")
        _ = try migrate(home: home, bundledTV: bundled, shell: "/bin/bash")
        let rc = try String(contentsOf: home.appendingPathComponent(".bashrc"), encoding: .utf8)
        #expect(rc.components(separatedBy: "# added by the tvbox installer").count == 2)
    }

    @Test func removesOnlyTheAppleScriptApp() throws {
        let (home, bundled) = try home()
        let old = home.appendingPathComponent("Applications/Terminal Values.app/Contents/Resources/Scripts")
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try "x".write(to: old.appendingPathComponent("main.scpt"), atomically: true, encoding: .utf8)
        let said = try migrate(home: home, bundledTV: bundled, shell: "/bin/zsh")
        #expect(!fm.fileExists(atPath: home.appendingPathComponent("Applications/Terminal Values.app").path))
        #expect(said.contains { $0.contains("old Terminal Values app") })

        let decoy = home.appendingPathComponent("Applications/Terminal Values.app/Contents/MacOS")
        try fm.createDirectory(at: decoy, withIntermediateDirectories: true)
        _ = try migrate(home: home, bundledTV: bundled, shell: "/bin/zsh")
        #expect(fm.fileExists(atPath: decoy.path))
    }
}

@Suite struct MigrationSafetyTests {
    // The final review: a .zshrc that isn't UTF-8 was read as empty and
    // overwritten with the one PATH line.
    @Test func neverOverwritesAStartupFileItCantRead() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("mig-\(UUID().uuidString)")
        try fm.createDirectory(at: home.appendingPathComponent(".local/bin"), withIntermediateDirectories: true)
        let bundled = home.appendingPathComponent("tv")
        try Data("#!/bin/sh\n".utf8).write(to: bundled)
        let latin1 = Data("alias caf\u{e9}=ls\n".data(using: .isoLatin1)!)
        let rc = home.appendingPathComponent(".zshrc")
        try latin1.write(to: rc)
        _ = try migrate(home: home, bundledTV: bundled, shell: "/bin/zsh")
        let after = try Data(contentsOf: rc)
        #expect(after.starts(with: latin1))
        #expect(String(decoding: after.dropFirst(latin1.count), as: UTF8.self).contains("# added by the tvbox installer"))
    }
}
