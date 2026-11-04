import Foundation

/// TVhome links, as tv link makes them: the same encoding and the same
/// refusals, pinned by tests/link_cases.json. Pure logic, so the app and the
/// Finder extension both compile it.
enum TVLink {
    static let base = "http://box.terminalvalues.org:8484/folder/"

    /// Why an item has no TVhome link: outside the folder; travelling by git,
    /// so TVhome has no copy; or hidden, which TVhome won't serve.
    enum Refusal: Error, Equatable { case outside, git, hidden }

    /// The directories Syncthing carries; everything else in the folder
    /// travels by git.
    private static let synced: Set<String> = ["doc", "www", "ledger", "entity", "site", "users"]

    /// Names that travel by git (or not at all) wherever they are: box/stignore's
    /// list, lower-cased, as tv's link_refusal has it.
    private static let gitNames: Set<String> = [
        "claude.md", "claude.local.md", "agents.md", "agent.md", "gemini.md", ".git", ".venv",
        "secrets", "__pycache__", ".pytest_cache", ".ds_store", ".claude", ".agents", ".codex",
        ".cursor", ".cursorrules", ".windsurfrules", ".mcp.json", ".envrc", ".vscode",
    ]

    /// The unreserved characters and "/"; every other UTF-8 byte becomes %XX.
    private static let unencoded = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/")

    /// relative: path inside the folder ("" for the folder itself).
    static func link(relative: String, isDirectory: Bool) -> Result<String, Refusal> {
        if let refusal = refusal(relative) { return .failure(refusal) }
        var link = base + (relative.addingPercentEncoding(withAllowedCharacters: unencoded) ?? relative)
        if isDirectory && !link.hasSuffix("/") { link += "/" }
        return .success(link)
    }

    /// Resolves symlinks on both, then defers to link(relative:isDirectory:).
    /// As tv link does: a directory, or a symlink to one, is resolved in full;
    /// a file's directory is resolved but not the file itself, so a symlinked
    /// file links to its own name. realpath(3) keeps the names' bytes as they
    /// are on disk, as pwd -P does; URL's resolvingSymlinksInPath would
    /// decompose them to NFD and strip /private.
    static func link(for item: URL, folder: URL) -> Result<String, Refusal> {
        var st = stat()
        let isDirectory = stat(item.path, &st) == 0 && st.st_mode & S_IFMT == S_IFDIR
        let resolved = isDirectory
            ? realPath(item.path)
            : realPath(item.deletingLastPathComponent().path).map { $0 + "/" + item.lastPathComponent }
        guard let path = resolved, let root = realPath(folder.path) else { return .failure(.outside) }
        let relative: String
        if path == root {
            relative = ""
        } else if path.hasPrefix(root + "/") {
            relative = String(path.dropFirst(root.count + 1))
        } else {
            return .failure(.outside)
        }
        return link(relative: relative, isDirectory: isDirectory)
    }

    /// The physical path, symlinks resolved, or nil if it isn't there.
    private static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// tv's link_refusal: git for anything outside the synced directories or
    /// with a git-only name in it, hidden for a dot-name, nil if it links.
    private static func refusal(_ relative: String) -> Refusal? {
        guard !relative.isEmpty else { return nil }
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard synced.contains(String(parts[0])) else { return .git }
        var hidden = false
        for part in parts {
            let lower = part.lowercased()
            if gitNames.contains(lower) { return .git }
            if lower.hasPrefix(".") { hidden = true }
        }
        return hidden ? .hidden : nil
    }

    /// FOLDER from tv's config text (shell-quoted, '\'' escapes). tv writes
    /// it with quote(); a hand-edited line may use double quotes or none.
    /// The last assignment wins, as when sh reads the file.
    static func folder(fromConfig text: String) -> String? {
        var folder: String?
        for line in text.split(whereSeparator: \.isNewline) {
            let line = line.drop(while: { $0 == " " || $0 == "\t" })
            guard line.hasPrefix("FOLDER=") else { continue }
            folder = unquote(line.dropFirst("FOLDER=".count))
        }
        return folder.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// One shell word: '...' as is, "..." with backslash escapes, a bare
    /// backslash quoting the next character. Ends at unquoted white space.
    private static func unquote(_ word: Substring) -> String {
        var out = ""
        var chars = word.makeIterator()
        while let c = chars.next() {
            switch c {
            case "'":
                while let q = chars.next(), q != "'" { out.append(q) }
            case "\"":
                while let q = chars.next(), q != "\"" {
                    if q == "\\", let n = chars.next() {
                        if !"\"\\$`".contains(n) { out.append(q) }
                        out.append(n)
                    } else {
                        out.append(q)
                    }
                }
            case "\\":
                if let n = chars.next() { out.append(n) }
            case " ", "\t":
                return out
            default:
                out.append(c)
            }
        }
        return out
    }

    /// The disabled menu item's words.
    static func notice(_ refusal: Refusal) -> String {
        switch refusal {
        case .git: "No TVhome Link: travels by git"
        case .hidden: "No TVhome Link: hidden file"
        case .outside: "No TVhome Link: not in the TVhome Folder"
        }
    }
}

/// Reading a link back into a path: the opposite of link(relative:), and tv's
/// decode_link / real_path, pinned by the same tests/link_cases.json. Works on
/// bytes with its own matching, not URLComponents, which decodes and
/// normalises differently from tv.
extension TVLink {
    enum OpenRefusal: String, Error, Equatable {
        case notALink = "not-a-link", traversal, nul, utf8, git, hidden, outside
    }
    struct Decoded: Equatable { var path: String; var isDirectory: Bool }
    enum Found: Equatable {
        /// logical: folder + "/" + path, as the member would browse to it.
        /// resolved: realpath(3) of it, the file that gets checked and opened.
        case here(logical: String, resolved: String, isDirectory: Bool)
        case missing(logical: String)
    }

    /// Files that run code when opened, by extension (lower case, no dot).
    static let runsCodeExtensions: Set<String> = [
        "app", "command", "sh", "bash", "zsh", "py", "pl", "rb", "scpt", "workflow",
        "terminal", "desktop", "jar", "exe", "bat",
    ]

    private static let prefixes = ["tvhome://folder/", "http://box.terminalvalues.org:8484/folder/"]

    static func decode(_ link: String) -> Result<Decoded, OpenRefusal> {
        var bytes = Array(link.utf8)
        if let i = bytes.firstIndex(of: UInt8(ascii: "#")) { bytes.removeSubrange(i...) }
        if let i = bytes.firstIndex(of: UInt8(ascii: "?")) { bytes.removeSubrange(i...) }
        func lower(_ b: UInt8) -> UInt8 { (65...90).contains(b) ? b + 32 : b }
        // Scheme and host in any case; in the http form "folder/" is a path, so exact.
        guard let prefix = prefixes.map({ Array($0.utf8) }).first(where: { p in
            let folded = p.first == UInt8(ascii: "h") ? p.count - 7 : p.count
            return bytes.count >= p.count && zip(bytes, p).enumerated().allSatisfy { n, pair in
                n < folded ? lower(pair.0) == pair.1 : pair.0 == pair.1
            }
        }) else { return .failure(.notALink) }
        var rest = Array(bytes.dropFirst(prefix.count))
        let isDirectory = rest.isEmpty || rest.last == UInt8(ascii: "/")
        if rest.last == UInt8(ascii: "/") { rest.removeLast() }
        if rest.isEmpty { return .success(Decoded(path: "", isDirectory: isDirectory)) }

        func hex(_ b: UInt8) -> UInt8? {
            switch b {
            case 48...57: b - 48
            case 65...70: b - 55
            case 97...102: b - 87
            default: nil
            }
        }
        var notALink = false, traversal = false, nul = false
        var out: [UInt8] = []
        var component: [UInt8] = []
        func endComponent() {
            if component.isEmpty || component == [46] || component == [46, 46] { traversal = true }
            component = []
        }
        var i = 0
        while i < rest.count {
            let b = rest[i]
            if b == UInt8(ascii: "/") {
                endComponent(); out.append(b); i += 1; continue
            }
            var v = b
            if b == UInt8(ascii: "%") {
                guard i + 2 < rest.count, let h = hex(rest[i + 1]), let l = hex(rest[i + 2]) else {
                    notALink = true; i += 1; continue
                }
                v = h * 16 + l; i += 2
                if v == UInt8(ascii: "/") { traversal = true }
            }
            if v == 0 { nul = true }
            component.append(v); out.append(v); i += 1
        }
        endComponent()
        if notALink { return .failure(.notALink) }
        if traversal { return .failure(.traversal) }
        if nul { return .failure(.nul) }
        guard let path = String(validating: out, as: UTF8.self) else { return .failure(.utf8) }
        if let r = refusal(path) { return .failure(r == .git ? .git : .hidden) }
        return .success(Decoded(path: path, isDirectory: isDirectory))
    }

    /// Where the link points in this folder, as the disk has it: symlinks and
    /// .. followed by realpath(3). A dangling symlink is missing. Only
    /// .outside can fail; isDirectory comes from the disk, not the link.
    static func find(_ decoded: Decoded, folder: String) -> Result<Found, OpenRefusal> {
        let logical = decoded.path.isEmpty ? folder : folder + "/" + decoded.path
        guard let resolved = realPath(logical) else { return .success(.missing(logical: logical)) }
        guard let root = realPath(folder), resolved == root || resolved.hasPrefix(root + "/") else {
            return .failure(.outside)
        }
        var st = stat()
        let isDirectory = stat(resolved, &st) == 0 && st.st_mode & S_IFMT == S_IFDIR
        return .success(.here(logical: logical, resolved: resolved, isDirectory: isDirectory))
    }
}
