import Foundation
import Testing
@testable import TerminalValues

/// The Finder's links must be exactly tv link's, so both read the same cases.
@Suite struct LinkTests {
    struct Case: Decodable, Sendable, CustomStringConvertible {
        var path: String; var dir: Bool?; var link: String?; var refused: String?
        var description: String { path.isEmpty ? "(the folder)" : path }
    }
    static let cases: [Case] = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "../../tests/link_cases.json")
        struct File: Decodable { var cases: [Case] }
        return try! JSONDecoder().decode(File.self, from: Data(contentsOf: url)).cases
    }()

    @Test(arguments: cases) func sameAsTvLink(_ c: Case) {
        switch TVLink.link(relative: c.path, isDirectory: c.dir ?? false) {
        case .success(let link): #expect(link == c.link)
        case .failure(let r): #expect(c.refused == (r == .git ? "git" : r == .hidden ? "hidden" : "outside"))
        }
    }

    @Test func outsideTheFolder() {
        let f = URL(fileURLWithPath: "/tmp/tv/terminalvalues")
        #expect(TVLink.link(for: URL(fileURLWithPath: "/tmp/tv/terminalvalues2/doc/a.txt"), folder: f) == .failure(.outside))
    }

    /// A TVhome Folder in a temporary directory, made with POSIX calls so
    /// names keep the bytes given (Foundation would decompose them to NFD).
    struct Tree: ~Copyable {
        let base: String
        var folder: URL { URL(fileURLWithPath: base + "/tv") }
        init() {
            base = NSTemporaryDirectory() + "tv-links-\(UUID().uuidString)"
            for dir in ["", "/tv", "/tv/doc", "/tv/ledger", "/tv/doc/caf\u{e9}", "/outside"] { mkdir(base + dir, 0o755) }
            for file in ["/tv/doc/a.txt", "/tv/doc/caf\u{e9}/a.txt", "/outside/b.txt"] {
                close(open(base + file, O_CREAT | O_WRONLY, 0o644))
            }
            symlink("a.txt", base + "/tv/doc/alias.txt")
            symlink("../ledger", base + "/tv/doc/books")
            symlink("../../outside", base + "/tv/doc/away")
            symlink("tv", base + "/tvlink")
        }
        func link(_ path: String, folder: URL? = nil) -> Result<String, TVLink.Refusal> {
            TVLink.link(for: URL(fileURLWithPath: base + path), folder: folder ?? self.folder)
        }
        deinit { try? FileManager.default.removeItem(atPath: base) }
    }

    @Test func theFolderItself() {
        let t = Tree()
        #expect(t.link("/tv") == .success(TVLink.base))
    }

    @Test func aDirectoryEndsInASlash() {
        let t = Tree()
        #expect(t.link("/tv/doc") == .success(TVLink.base + "doc/"))
    }

    @Test func aSymlinkedFolder() {
        let t = Tree()
        let viaLink = URL(fileURLWithPath: t.base + "/tvlink")
        #expect(t.link("/tv/doc/a.txt", folder: viaLink) == .success(TVLink.base + "doc/a.txt"))
        #expect(t.link("/tvlink/doc/a.txt") == .success(TVLink.base + "doc/a.txt"))
    }

    // As tv link: a file's directory is resolved, the file itself isn't.
    @Test func aSymlinkedFileLinksToItsOwnName() {
        let t = Tree()
        #expect(t.link("/tv/doc/alias.txt") == .success(TVLink.base + "doc/alias.txt"))
    }

    // As tv link's [ -d ] and cd && pwd -P: a symlink to a directory is that directory.
    @Test func aSymlinkToADirectoryIsTheDirectory() {
        let t = Tree()
        #expect(t.link("/tv/doc/books") == .success(TVLink.base + "ledger/"))
        #expect(t.link("/tv/doc/away") == .failure(.outside))
    }

    // Review Focus: a composed é on disk stays composed, as pwd -P gives it.
    @Test func composedNamesStayComposed() {
        let t = Tree()
        #expect(t.link("/tv/doc/caf\u{e9}/a.txt") == .success(TVLink.base + "doc/caf%C3%A9/a.txt"))
    }

    @Test func readsTheFolderFromTvsConfig() {
        let text = "# tv's settings\nFOLDER='/Users/sam/Documents/Sam'\\''s TV'\nLOGIN='sam'\n"
        #expect(TVLink.folder(fromConfig: text) == "/Users/sam/Documents/Sam's TV")
    }
}
