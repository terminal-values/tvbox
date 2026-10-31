import AppKit
import SwiftTerm
import SwiftUI

/// The terminal in the window: the member's own shell, on this Mac (not in
/// the box), in the TV folder, with the app's tv on its PATH. It lives as long
/// as the app, so closing the window doesn't end a command.
@MainActor
final class TerminalSession {
    let view: LocalProcessTerminalView
    let tvDirectory: URL
    private(set) var started = false

    init(tvDirectory: URL) {
        self.tvDirectory = tvDirectory
        view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 360, height: 160))
        view.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        view.nativeBackgroundColor = NSColor(white: 0.12, alpha: 1)
        view.nativeForegroundColor = NSColor(white: 0.9, alpha: 1)
    }

    /// Starts the shell in the folder, once.
    func start(in folder: URL, shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh") {
        guard !started else { return }
        started = true
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = tvDirectory.path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        env["TERM"] = "xterm-256color"
        env["TV_FOLDER"] = folder.path
        env["TV_SHELL"] = shell
        // cd first, then become a login shell, so the member's usual setup applies.
        view.startProcess(executable: "/bin/sh",
                          args: ["-c", "cd \"$TV_FOLDER\" && exec \"$TV_SHELL\" -l"],
                          environment: env.map { "\($0.key)=\($0.value)" },
                          execName: "sh")
    }

    /// Types into the terminal, as if at the keyboard.
    func type(_ text: String) { view.send(txt: text) }

    /// Is a command running in it (the shell isn't the foreground job)?
    var isBusy: Bool {
        guard started else { return false }
        let fd = view.process.childfd
        let foreground = tcgetpgrp(fd)
        return foreground > 0 && foreground != view.process.shellPid
    }
}

struct TerminalSection: NSViewRepresentable {
    let session: TerminalSession
    let folder: URL?

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        if let folder { session.start(in: folder) }
        return session.view
    }

    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {
        if let folder { session.start(in: folder) }
    }
}
