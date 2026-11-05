import AppKit
import UniformTypeIdentifiers

/// What the app offers for one tvhome:// link. name: the file's or folder's
/// own name ("TVhome Folder" for the folder). shown: its path in the TVhome
/// Folder. logical: where to reveal it. resolved: what is checked and opened.
enum LinkAnswer: Equatable {
    case open(name: String, shown: String, app: String, logical: String, resolved: String)
    case showFolder(name: String, logical: String)
    case runsCode(name: String, shown: String, logical: String)
    case noApp(name: String, shown: String, logical: String)
    case notHereYet(name: String, shown: String)
    case refused(TVLink.OpenRefusal)
    case notJoined

    var buttons: [LinkButton] {
        switch self {
        case .open: [.open, .showInFinder, .cancel]
        case .showFolder, .runsCode, .noApp: [.showInFinder, .cancel]
        case .notHereYet, .refused, .notJoined: [.ok]
        }
    }
}

enum LinkButton: Equatable { case open, showInFinder, cancel, ok }

enum LinkAction: Equatable {
    case open(resolved: String), reveal(logical: String), openFolder(logical: String)
    case show(LinkAnswer), nothing
}

/// folder: from tv's config, nil if this Mac hasn't joined.
func answer(for link: String, folder: String?,
            runsCode: (String) -> Bool = runsCode(atPath:),
            appName: (String) -> String? = defaultAppName(forPath:)) -> LinkAnswer {
    guard let folder else { return .notJoined }
    let decoded: TVLink.Decoded
    switch TVLink.decode(link) {
    case .failure(let why): return .refused(why)
    case .success(let d): decoded = d
    }
    let name = decoded.path.isEmpty ? "TVhome Folder" : decoded.path.split(separator: "/").last.map(String.init) ?? decoded.path
    switch TVLink.find(decoded, folder: folder) {
    case .failure(let why): return .refused(why)
    case .success(.missing): return .notHereYet(name: name, shown: decoded.path)
    case .success(.here(let logical, let resolved, let isDirectory)):
        if runsCode(resolved) { return .runsCode(name: name, shown: decoded.path, logical: logical) }
        if isDirectory && !isPackage(resolved) { return .showFolder(name: name, logical: logical) }
        guard let app = appName(resolved) else { return .noApp(name: name, shown: decoded.path, logical: logical) }
        return .open(name: name, shown: decoded.path, app: app, logical: logical, resolved: resolved)
    }
}

/// What a button press does. Open re-checks: it opens only if recheck()
/// gives the same .open answer; otherwise it shows the new one.
func afterChoice(_ button: LinkButton, on answer: LinkAnswer, recheck: () -> LinkAnswer) -> LinkAction {
    switch button {
    case .cancel, .ok: return .nothing
    case .showInFinder:
        switch answer {
        case .showFolder(_, let logical): return .openFolder(logical: logical)
        case .open(_, _, _, let logical, _), .runsCode(_, _, let logical), .noApp(_, _, let logical):
            return .reveal(logical: logical)
        default: return .nothing
        }
    case .open:
        let now = recheck()
        if now == answer, case .open(_, _, _, _, let resolved) = now { return .open(resolved: resolved) }
        return .show(now)
    }
}

/// A directory the Finder treats as one file (.rtfd, .pkg, a bundle).
func isPackage(_ resolved: String) -> Bool {
    (try? URL(fileURLWithPath: resolved).resourceValues(forKeys: [.isPackageKey]))?.isPackage ?? false
}

/// Whether opening this file could run code: a regular file with any execute
/// bit, or an extension in TVLink.runsCodeExtensions (that list is what
/// catches .terminal, .workflow, installers and location files). Beyond
/// those, a content type that is executable, a script or an application. A
/// path that can't be examined counts as code.
func runsCode(atPath resolved: String) -> Bool {
    var st = stat()
    guard stat(resolved, &st) == 0 else { return true }
    let ext = (resolved as NSString).pathExtension.lowercased()
    if TVLink.runsCodeExtensions.contains(ext) { return true }
    if st.st_mode & S_IFMT == S_IFREG, st.st_mode & 0o111 != 0 { return true }
    let url = URL(fileURLWithPath: resolved)
    let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType ?? UTType(filenameExtension: ext)
    guard let type else { return false }
    // Macro-enabled Office files (.docm, .xlsm) are marked executable by the
    // system, but open normally in their app.
    if let office = UTType("org.openxmlformats.openxml"), type.conforms(to: office) { return false }
    return type.conforms(to: .executable) || type.conforms(to: .script) || type.conforms(to: .application)
}

/// The name of the app that opens this file by default, if any.
func defaultAppName(forPath resolved: String) -> String? {
    guard let app = NSWorkspace.shared.urlForApplication(toOpen: URL(fileURLWithPath: resolved)) else { return nil }
    let name = FileManager.default.displayName(atPath: app.path)
    return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
}

/// The words of the dialog for an answer.
extension LinkAnswer {
    var words: (title: String, detail: String) {
        switch self {
        case .open(let name, let shown, let app, _, _):
            ("Open “\(name)”?", "\(shown)\n\nIt will open in \(app).")
        case .showFolder(let name, _):
            (name == "TVhome Folder" ? "This is the TVhome Folder." : "“\(name)” is a folder.",
             "TVhome links don't open folders. Show it in the Finder instead.")
        case .runsCode(let name, let shown, _):
            ("“\(name)” runs code when opened.", "\(shown)\n\nTVhome links won't open it. You can still show it in the Finder.")
        case .noApp(let name, let shown, _):
            ("No app on this Mac opens “\(name)”.", "\(shown)\n\nYou can show it in the Finder instead.")
        case .notHereYet(let name, let shown):
            ("“\(name)” isn't on this Mac yet.", "\(shown)\n\nSyncthing may not have brought it yet (the box has to be running), or it has been deleted.")
        case .refused:
            ("That link doesn't name a file in the TVhome Folder.", "Nothing was opened.")
        case .notJoined:
            ("This Mac hasn't joined TV yet.", "Join first, then open the link again.")
        }
    }
}

extension LinkButton {
    var title: String {
        switch self {
        case .open: "Open"
        case .showInFinder: "Show in Finder"
        case .cancel: "Cancel"
        case .ok: "OK"
        }
    }
}
