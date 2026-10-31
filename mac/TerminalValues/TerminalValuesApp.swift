import SwiftUI

@main
struct TerminalValuesApp: App {
    var body: some Scene {
        MenuBarExtra("Terminal Values", systemImage: "triangle") {
            Button("Quit Terminal Values") { NSApplication.shared.terminate(nil) }
        }
        Window("Terminal Values", id: "main") {
            Text("Terminal Values")
        }
    }
}
