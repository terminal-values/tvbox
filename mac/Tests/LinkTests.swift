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
        struct Only: Decodable { var cases: [Case] }
        return try! JSONDecoder().decode(Only.self, from: Data(contentsOf: url)).cases
    }()
    struct File: Decodable {
        var decodes: [LinkCase]; var refused_links: [LinkCase]; var runs_code_extensions: [String]
    }
    static let file: File = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "../../tests/link_cases.json")
        return try! JSONDecoder().decode(File.self, from: Data(contentsOf: url))
    }()
    struct LinkCase: Decodable, Sendable, CustomStringConvertible {
        var link: String; var path: String?; var dir: Bool?; var refused: String?
        var description: String { link }
    }

    @Test(arguments: cases) func sameAsTvLink(_ c: Case) {
        switch TVLink.link(relative: c.path, isDirectory: c.dir ?? false) {
        case .success(let link): #expect(link == c.link)
        case .failure(let r): #expect(c.refused == (r == .git ? "git" : r == .hidden ? "hidden" : "outside"))
        }
    }

    static let linkCases: [LinkCase] = cases.compactMap { c in
        c.link.map { LinkCase(link: $0, path: c.path, dir: c.dir) }
    }

    @Test(arguments: linkCases) func everyLinkDecodesBack(_ c: LinkCase) {
        #expect(TVLink.decode(c.link) == .success(.init(path: c.path!, isDirectory: c.dir ?? false)))
    }

    @Test(arguments: file.decodes) func otherFormsDecode(_ c: LinkCase) {
        #expect(TVLink.decode(c.link) == .success(.init(path: c.path!, isDirectory: c.dir ?? false)))
    }

    @Test(arguments: file.refused_links) func badLinksAreRefused(_ c: LinkCase) {
        #expect(TVLink.decode(c.link) == .failure(TVLink.OpenRefusal(rawValue: c.refused!)!))
    }

    @Test func theExtensionListIsTvs() {
        #expect(TVLink.runsCodeExtensions == Set(Self.file.runs_code_extensions))
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
            mkdir(base + "/tv/doc/b", 0o755); mkdir(base + "/tv/doc/b/c", 0o755)
            close(open(base + "/tv/doc/b/t.md", O_CREAT | O_WRONLY, 0o644))
            symlink("b/c", base + "/tv/doc/sym")
            symlink("sym/../t.md", base + "/tv/doc/lex")
            symlink("gone.txt", base + "/tv/doc/dangling")
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

    static func real(_ p: String) -> String {
        let r = realpath(p, nil)!; defer { free(r) }; return String(cString: r)
    }

    /// Swift's == treats canonically equivalent strings as equal, so compare bytes.
    static func here(_ r: Result<TVLink.Found, TVLink.OpenRefusal>) -> (logical: [UInt8], resolved: [UInt8], isDirectory: Bool)? {
        guard case .success(.here(let l, let r, let d)) = r else { return nil }
        return (Array(l.utf8), Array(r.utf8), d)
    }

    @Test func findsAFile() {
        let t = Tree()
        let h = Self.here(TVLink.find(.init(path: "doc/alias.txt", isDirectory: false), folder: t.base + "/tv"))
        #expect(h?.logical == Array((t.base + "/tv/doc/alias.txt").utf8))
        #expect(h?.resolved == Array(Self.real(t.base + "/tv/doc/a.txt").utf8))
        #expect(h?.isDirectory == false)
    }

    @Test func aFolderLinkWithoutItsSlash() {
        let t = Tree()
        #expect(TVLink.find(.init(path: "ledger", isDirectory: false), folder: t.base + "/tv")
            == .success(.here(logical: t.base + "/tv/ledger",
                              resolved: Self.real(t.base + "/tv/ledger"), isDirectory: true)))
    }

    @Test func theFolderItselfIsFound() {
        let t = Tree()
        #expect(TVLink.find(.init(path: "", isDirectory: true), folder: t.base + "/tv")
            == .success(.here(logical: t.base + "/tv",
                              resolved: Self.real(t.base + "/tv"), isDirectory: true)))
    }

    @Test func missingIsNotHereYet() {
        let t = Tree()
        #expect(TVLink.find(.init(path: "doc/nope.txt", isDirectory: false), folder: t.base + "/tv")
            == .success(.missing(logical: t.base + "/tv/doc/nope.txt")))
    }

    @Test func aDanglingSymlinkIsMissing() {
        let t = Tree()
        #expect(TVLink.find(.init(path: "doc/dangling", isDirectory: false), folder: t.base + "/tv")
            == .success(.missing(logical: t.base + "/tv/doc/dangling")))
    }

    @Test func aSymlinkOutIsOutside() {
        let t = Tree()
        #expect(TVLink.find(.init(path: "doc/away/b.txt", isDirectory: false), folder: t.base + "/tv")
            == .failure(.outside))
    }

    // .. after a symlinked directory means the disk's parent, not the spelling's.
    @Test func dotDotFollowsTheDisk() {
        let t = Tree()
        #expect(TVLink.find(.init(path: "doc/lex", isDirectory: false), folder: t.base + "/tv")
            == .success(.here(logical: t.base + "/tv/doc/lex",
                              resolved: Self.real(t.base + "/tv/doc/b/t.md"), isDirectory: false)))
    }

    // Review Focus: a decomposed name on disk, linked composed as tv link writes it.
    @Test func aDecomposedNameIsFound() {
        let t = Tree()
        close(open(t.base + "/tv/doc/cafe\u{301}.txt", O_CREAT | O_WRONLY, 0o644))
        let h = Self.here(TVLink.find(.init(path: "doc/caf\u{e9}.txt", isDirectory: false), folder: t.base + "/tv"))
        #expect(h != nil)
        #expect(h?.logical == Array((t.base + "/tv/doc/caf\u{e9}.txt").utf8))
        // The disk's bytes survive: e + U+0301, not é.
        #expect(h?.resolved == Array(Self.real(t.base + "/tv/doc/cafe\u{301}.txt").utf8))
        #expect(h?.resolved.suffix(10) == Array("cafe\u{301}.txt".utf8)[...])
        #expect(h?.isDirectory == false)
    }

    // A name that starts with a combining mark, right after root + "/": inside the
    // folder. String.hasPrefix(root + "/") wrongly called this outside.
    @Test func aNameStartingWithACombiningMarkIsHere() {
        let t = Tree()
        close(open(t.base + "/tv/\u{301}x", O_CREAT | O_WRONLY, 0o644))
        symlink("../\u{301}x", t.base + "/tv/doc/link")
        let h = Self.here(TVLink.find(.init(path: "doc/link", isDirectory: false), folder: t.base + "/tv"))
        #expect(h?.resolved == Array((Self.real(t.base + "/tv") + "/\u{301}x").utf8))
    }

    // The folder's own name followed by a combining mark is a different, outside, folder.
    @Test func aCombiningMarkAfterTheFolderNameIsOutside() {
        let t = Tree()
        mkdir(t.base + "/tv\u{301}", 0o755)
        close(open(t.base + "/tv\u{301}/f", O_CREAT | O_WRONLY, 0o644))
        symlink("../../tv\u{301}/f", t.base + "/tv/doc/sneaky")
        let r = TVLink.find(.init(path: "doc/sneaky", isDirectory: false), folder: t.base + "/tv")
        #expect(r == .failure(.outside))
    }

    @Test func readsTheFolderFromTvsConfig() {
        let text = "# tv's settings\nFOLDER='/Users/sam/Documents/Sam'\\''s TV'\nLOGIN='sam'\n"
        #expect(TVLink.folder(fromConfig: text) == "/Users/sam/Documents/Sam's TV")
    }
}
