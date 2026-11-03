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

    @Test func readsTheFolderFromTvsConfig() {
        let text = "# tv's settings\nFOLDER='/Users/sam/Documents/Sam'\\''s TV'\nLOGIN='sam'\n"
        #expect(TVLink.folder(fromConfig: text) == "/Users/sam/Documents/Sam's TV")
    }
}
