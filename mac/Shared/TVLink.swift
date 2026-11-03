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
    /// As in tv link, a file's directory is resolved but not the file itself,
    /// so a symlinked file links to its own name.
    static func link(for item: URL, folder: URL) -> Result<String, Refusal> {
        let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory
            ?? item.hasDirectoryPath
        let path = isDirectory
            ? item.resolvingSymlinksInPath().path
            : item.deletingLastPathComponent().resolvingSymlinksInPath()
                .appending(path: item.lastPathComponent).path
        let root = folder.resolvingSymlinksInPath().path
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
