import Foundation
import Testing
@testable import TerminalValues

/// What the app offers for a tvhome:// link, and what each button does.
@Suite struct OpenLinkTests {
    /// A TVhome Folder in a temporary directory, made with POSIX calls.
    final class Tree: Sendable {
        let base: String
        var folder: String { base + "/tv" }
        init() {
            base = NSTemporaryDirectory() + "tv-open-\(UUID().uuidString)"
            for dir in ["", "/tv", "/tv/doc", "/tv/ledger", "/tv/doc/Thing.app", "/tv/doc/plain", "/tv/doc/Notes.rtfd", "/tv/doc/Setup.pkg", "/outside"] {
                mkdir(base + dir, 0o755)
            }
            for file in ["/tv/doc/a.md", "/tv/doc/run.sh", "/tv/doc/x.pdf", "/tv/doc/go.command",
                         "/tv/doc/job.PY", "/tv/doc/job2.SH", "/tv/doc/budget.docm", "/tv/doc/budget.xlsm", "/tv/doc/xbudget.docm",
                         "/outside/b.txt"] {
                close(open(base + file, O_CREAT | O_WRONLY, 0o644))
            }
            chmod(base + "/tv/doc/x.pdf", 0o755)
            chmod(base + "/tv/doc/xbudget.docm", 0o755)
            symlink("run.sh", base + "/tv/doc/notes.md")
            symlink("../../outside", base + "/tv/doc/away")
        }
        deinit { try? FileManager.default.removeItem(atPath: base) }
        func path(_ p: String) -> String { folder + "/" + p }
    }

    static let textEdit: @Sendable (String) -> String? = { _ in "TextEdit" }
    func answer(_ t: Tree, _ path: String, folder: String?? = nil,
                appName: @escaping (String) -> String? = OpenLinkTests.textEdit) -> LinkAnswer {
        TerminalValues.answer(for: "tvhome://folder/" + path, folder: folder ?? t.folder, appName: appName)
    }

    @Test func aFileOffersOpen() {
        let t = Tree()
        let a = answer(t, "doc/a.md")
        guard case .open(let name, let shown, let app, let logical, let resolved) = a else {
            Issue.record("got \(a)"); return
        }
        #expect(name == "a.md"); #expect(shown == "doc/a.md"); #expect(app == "TextEdit")
        #expect(logical == t.path("doc/a.md"))
        #expect(resolved.hasSuffix("/tv/doc/a.md"))
        #expect(a.buttons == [.open, .showInFinder, .cancel])
    }

    @Test func aFolderOffersShow() {
        let t = Tree()
        guard case .showFolder(let name, _) = answer(t, "ledger/") else { Issue.record("not showFolder"); return }
        #expect(name == "ledger")
        guard case .showFolder(let top, let logical) = answer(t, "") else { Issue.record("not showFolder"); return }
        #expect(top == "TVhome Folder"); #expect(logical == t.folder)
        #expect(answer(t, "ledger/").buttons == [.showInFinder, .cancel])
    }

    @Test(arguments: ["doc/run.sh", "doc/x.pdf", "doc/Thing.app/", "doc/go.command", "doc/job.PY",
                         "doc/xbudget.docm", "doc/notes.md", "doc/Setup.pkg/"])
    func codeOffersOnlyShow(_ path: String) {
        let t = Tree()
        let a = answer(t, path)
        guard case .runsCode = a else { Issue.record("got \(a)"); return }
        #expect(a.buttons == [.showInFinder, .cancel])
    }

    @Test func aPackageIsAFileNotAFolder() {
        let t = Tree()
        guard case .open(let name, _, _, let logical, _) = answer(t, "doc/Notes.rtfd/") else { Issue.record("not open"); return }
        #expect(name == "Notes.rtfd")
        let a = answer(t, "doc/Notes.rtfd/")
        #expect(TerminalValues.afterChoice(.showInFinder, on: a, recheck: { a }) == .reveal(logical: logical))
    }

    @Test func aPathThatCantBeExaminedCountsAsCode() {
        #expect(runsCode(atPath: "/nonexistent/\(UUID().uuidString)"))
    }

    @Test func noAppOffersOnlyShow() {
        let t = Tree()
        let a = answer(t, "doc/a.md", appName: { _ in nil })
        guard case .noApp(let name, let shown, _) = a else { Issue.record("got \(a)"); return }
        #expect(name == "a.md"); #expect(shown == "doc/a.md")
        #expect(a.buttons == [.showInFinder, .cancel])
    }

    @Test func missingIsNotHereYet() {
        let t = Tree()
        let a = answer(t, "doc/nope.md")
        #expect(a == .notHereYet(name: "nope.md", shown: "doc/nope.md"))
        #expect(a.buttons == [.ok])
    }

    @Test func badLinkIsRefused() {
        let t = Tree()
        let a = answer(t, "doc/../x")
        #expect(a == .refused(.traversal)); #expect(a.buttons == [.ok])
    }

    @Test func aSymlinkOutIsRefused() {
        let t = Tree()
        let a = answer(t, "doc/away/b.txt")
        #expect(a == .refused(.outside)); #expect(a.buttons == [.ok])
    }

    @Test func notJoined() {
        let t = Tree()
        let a = answer(t, "doc/a.md", folder: .some(nil))
        #expect(a == .notJoined); #expect(a.buttons == [.ok])
    }

    @Test func afterChoice() {
        let t = Tree()
        let file = answer(t, "doc/a.md")
        guard case .open(_, _, _, let logical, let resolved) = file else { Issue.record("not open"); return }
        #expect(TerminalValues.afterChoice(.open, on: file, recheck: { file }) == .open(resolved: resolved))
        let code = answer(t, "doc/run.sh")
        #expect(TerminalValues.afterChoice(.open, on: file, recheck: { code }) == .show(code))
        let folder = answer(t, "ledger/")
        #expect(TerminalValues.afterChoice(.showInFinder, on: folder, recheck: { folder }) == .openFolder(logical: t.path("ledger")))
        #expect(TerminalValues.afterChoice(.showInFinder, on: file, recheck: { file }) == .reveal(logical: logical))
        #expect(TerminalValues.afterChoice(.cancel, on: file, recheck: { file }) == .nothing)
        #expect(TerminalValues.afterChoice(.ok, on: .notJoined, recheck: { .notJoined }) == .nothing)
    }

    @Test func runsCodeRules() {
        let t = Tree()
        for p in ["doc/go.command", "doc/job.PY", "doc/job2.SH", "doc/x.pdf", "doc/Thing.app"] {
            #expect(runsCode(atPath: t.path(p)), "\(p)")
        }
        for p in ["doc/a.md", "doc/budget.docm", "doc/budget.xlsm", "doc/plain"] {
            #expect(!runsCode(atPath: t.path(p)), "\(p)")
        }
    }

    @Test func registersTheScheme() {
        let types = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] ?? []
        #expect(types.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains("tvhome") == true })
    }
}
