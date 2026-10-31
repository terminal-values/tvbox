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
            MenuLabel(model: delegate.model)
        }
        Window("Terminal Values", id: "main") {
            MainWindow(model: delegate.model, terminal: delegate.terminal, walk: delegate.walkthrough)
        }
        .windowResizability(.contentSize)
    }
}

/// Starting and quitting: the box runs while the app does.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel(tv: .bundled)
    /// The window's terminal, kept for the app's life so closing the window
    /// doesn't end a command running in it.
    let terminal = TerminalSession(tvDirectory: Bundle.main.resourceURL!)
    lazy var walkthrough = WalkthroughController(model: model)
    private var quitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The unit tests run inside the app: never touch the real box then.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        let atLogin = Self.launchedAtLogin()
        Task {
            await model.launch(atLogin: atLogin)
            model.startPolling()
        }
        // Opened by hand (not at login): show the window.
        if !atLogin { model.wantsWindow = true }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitting { return .terminateNow }
        if model.quitRequested(terminalBusy: terminal.isBusy) == .ask {
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

    /// Whether macOS opened the app as a login item.
    private static func launchedAtLogin() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication &&
            event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}

/// The menu bar icon. It's also what opens the main window when the app
/// asks (at launch, say): only a SwiftUI view can open a window scene.
struct MenuLabel: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: MenuIcon.image(model.isRunning ? .running : .stopped, attention: model.needsAttention))
            .onAppear(perform: show)
            .onChange(of: model.wantsWindow) { show() }
    }

    private func show() {
        guard model.wantsWindow else { return }
        model.wantsWindow = false
        openWindow(id: "main")
        NSApplication.shared.activate()
    }
}
