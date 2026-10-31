import Foundation

/// Moving in, on every start of an installed app (quietly, when there's
/// nothing to do): the member's tv becomes a link to the app's own, which the
/// app keeps up to date; ~/.local/bin is put on the shell's PATH as the
/// installer would; and the AppleScript app the installer used to make goes,
/// so Spotlight shows one Terminal Values. Returns what it changed, in words.
func migrate(home: URL, bundledTV: URL, shell: String) throws -> [String] {
    let fm = FileManager.default
    var said: [String] = []

    let bin = home.appendingPathComponent(".local/bin")
    let tv = bin.appendingPathComponent("tv")
    if (try? fm.destinationOfSymbolicLink(atPath: tv.path)) != bundledTV.path {
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        if (try? fm.attributesOfItem(atPath: tv.path)) != nil { try fm.removeItem(at: tv) }
        try fm.createSymbolicLink(at: tv, withDestinationURL: bundledTV)
        said.append("~/.local/bin/tv is now the app's own, so it stays up to date with the app.")
    }

    let mark = "# added by the tvbox installer"
    let rcName = switch URL(fileURLWithPath: shell).lastPathComponent {
    case "zsh": ".zshrc"
    case "bash": ".bashrc"
    default: ".profile"
    }
    let rc = home.appendingPathComponent(rcName)
    // As bytes: a startup file needn't be UTF-8, and is only ever appended to,
    // in place (it may be a link, from stow), never rewritten.
    let bytes = (try? Data(contentsOf: rc)) ?? Data()
    let has = { (needle: String) in bytes.range(of: Data(needle.utf8)) != nil }
    if !has(mark) && !has(".local/bin") {
        var line = "export PATH=\"$HOME/.local/bin:$PATH\"  \(mark)\n"
        if let last = bytes.last, last != UInt8(ascii: "\n") { line = "\n" + line }
        if fm.fileExists(atPath: rc.path) {
            let handle = try FileHandle(forWritingTo: rc)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } else {
            try Data(line.utf8).write(to: rc)
        }
        said.append("Added ~/.local/bin to your PATH, in ~/\(rcName), so terminals find tv.")
    }

    let old = home.appendingPathComponent("Applications/Terminal Values.app")
    if fm.fileExists(atPath: old.appendingPathComponent("Contents/Resources/Scripts/main.scpt").path) {
        try fm.removeItem(at: old)
        said.append("Removed the old Terminal Values app from ~/Applications; this one replaces it.")
    }
    return said
}
