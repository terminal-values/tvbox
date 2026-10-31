import AppKit
import SwiftUI

@main
struct TerminalValuesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: delegate.model)
                .task { await delegate.model.menuOpened() }
        } label: {
            Image(nsImage: MenuIcon.image(delegate.model.isRunning ? .running : .stopped,
                                          attention: delegate.model.needsAttention))
        }
        Window("Terminal Values", id: "main") {
            Text("Terminal Values")
                .frame(width: 400, height: 640)
        }
        .windowResizability(.contentSize)
    }
}

/// Starting and quitting: the box runs while the app does.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel(tv: .bundled)
    /// Set by the window's terminal (Task 10): is a command running in it?
    var terminalBusy: () -> Bool = { false }
    private var quitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The unit tests run inside the app: never touch the real box then.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        let atLogin = Self.launchedAtLogin()
        Task {
            await model.launch(atLogin: atLogin)
            model.startPolling()
        }
        // Opened by hand (not at login), or not set up yet: show the window.
        if !atLogin { showMainWindow() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitting { return .terminateNow }
        if model.quitRequested(terminalBusy: terminalBusy()) == .ask {
            let alert = NSAlert()
            alert.messageText = "A command is still running in the terminal."
            alert.informativeText = "Quitting stops it, and stops the box."
            alert.addButton(withTitle: "Quit Anyway")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() != .alertFirstButtonReturn { return .terminateCancel }
        }
        let defaults = UserDefaults.standard
        if model.isRunning && !defaults.bool(forKey: "quitExplained") {
            let alert = NSAlert()
            alert.messageText = "Quitting stops the box."
            alert.informativeText = "TV's documents sync only while it runs. Open Terminal Values again to start it."
            alert.showsSuppressionButton = true
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Cancel")
            let answer = alert.runModal()
            if alert.suppressionButton?.state == .on { defaults.set(true, forKey: "quitExplained") }
            if answer != .alertFirstButtonReturn { return .terminateCancel }
        }
        quitting = true
        Task {
            await model.prepareToQuit()
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func showMainWindow() {
        NSApplication.shared.activate()
        // The Window scene opens itself at launch; bring it forward.
        for window in NSApplication.shared.windows where window.identifier?.rawValue == "main" {
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Whether macOS opened the app as a login item.
    private static func launchedAtLogin() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication &&
            event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
