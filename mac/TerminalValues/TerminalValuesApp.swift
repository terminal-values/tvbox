import AppKit
import Sparkle
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
            MainWindow(model: delegate.model, terminal: delegate.terminal, walk: delegate.walkthrough,
                       canUpdate: delegate.updatesOn, checkForUpdates: delegate.checkForUpdates)
        }
        Window("The Doctor", id: "doctor") {
            DoctorView(doctor: delegate.doctor)
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
    lazy var doctor = Doctor(model: model)
    /// Sparkle, for the app's own updates (and with them, its tv and box).
    let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    /// Only a release build carries Sparkle's public key.
    var updatesOn: Bool {
        !((Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String) ?? "").isEmpty
    }
    func checkForUpdates() { if updatesOn { updater.checkForUpdates(nil) } }
    private var quitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The unit tests run inside the app: never touch the real box then.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        // Only one copy runs: give way to a newer one already running, and
        // show its window instead.
        let others = otherCopies()
        if let keeper = copyToStepAsideFor(among: others), let url = keeper.bundleURL {
            quitting = true
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in
                DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
            }
            return
        }
        listenForStepAside()
        moveIn()
        // The Finder extension watches tv's config directory to follow tv
        // move. Sandboxed, it can't make the directory, so it's made here
        // before tv join writes the config into it.
        try? FileManager.default.createDirectory(
            at: FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/tv"),
            withIntermediateDirectories: true)
        model.pinned = BoxImage.read()
        let atLogin = Self.launchedAtLogin()
        if updatesOn { updater.startUpdater() }
        Task {
            // Older copies quit first, leaving the box running for this one.
            await takeOver(from: others)
            await model.launch(atLogin: atLogin)
            // After an app update, the box follows to the image this release pins.
            _ = await moveBoxIfNeeded(model: model, pinned: model.pinned)
            model.startPolling()
        }
        // Opened by hand (not at login): show the window.
        if !atLogin { model.wantsWindow = true }
    }

    /// Opened again while it runs (from Spotlight, Finder or Launchpad):
    /// macOS sends a reopen, not a launch, so bring the window forward,
    /// even if it's open behind other windows. False, since that's done here.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        model.wantsWindow = true
        return false
    }

    /// A newer copy has opened: quit at once, without stopping the box or
    /// asking, since the newer copy takes the box over.
    private func listenForStepAside() {
        let me = Int(ProcessInfo.processInfo.processIdentifier)
        DistributedNotificationCenter.default().addObserver(forName: stepAsideNotice, object: nil, queue: .main) { note in
            guard note.userInfo?["pid"] as? Int != me else { return }
            MainActor.assumeIsolated {
                self.quitting = true
                NSApplication.shared.terminate(nil)
            }
        }
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

    /// Only an installed app moves in: a development build run from
    /// elsewhere mustn't re-point the member's tv at itself.
    private func moveIn() {
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/"),
              let bundled = Bundle.main.url(forResource: "tv", withExtension: nil) else { return }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard let said = try? migrate(home: FileManager.default.homeDirectoryForCurrentUser,
                                      bundledTV: bundled, shell: shell), !said.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Terminal Values has moved in."
        alert.informativeText = said.joined(separator: "\n\n")
        alert.runModal()
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
