import SwiftUI

/// The short tour: four things to try, each ticked when it works.
struct TutorialView: View {
    @Bindable var tour: TutorialProgress
    @Bindable var model: AppModel
    let terminal: TerminalSession
    @Environment(\.openWindow) private var openWindow
    @State private var explaining: TutorialItem?
    @State private var askToWritePage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A quick tour, once you're in").font(.title3).bold()
            Text("Four short things to try. Each one ticks itself off when it works.").foregroundStyle(.secondary)
            Form {
                ForEach(TutorialItem.allCases, id: \.self) { item in
                    LabeledContent {
                        if tour.isDone(item) {
                            Text("Done").foregroundStyle(.secondary)
                        } else {
                            Button("Show Me") { Task { await showMe(item) } }
                        }
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text(item.title).bold()
                                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: tour.isDone(item) ? "checkmark.circle.fill" : "circle") }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding(20)
        .frame(width: 560)
        .task { await recheck() }
        .sheet(item: $explaining) { item in Explanation(item: item, tour: tour, login: model.status?.login ?? "LOGIN") }
        .confirmationDialog("Write a starter page for you?", isPresented: $askToWritePage) {
            Button("Write It") { Task { await writePageAndOpen() } }
        } message: { Text("It goes in www/hello-\(model.status?.login ?? "you").html in your TV folder; change it however you like.") }
    }

    private var login: String { model.status?.login ?? "" }

    private func showMe(_ item: TutorialItem) async {
        switch item {
        case .page:
            guard let folder = model.status?.folder else { return }
            let page = URL(fileURLWithPath: folder).appendingPathComponent("www/hello-\(login).html")
            if FileManager.default.fileExists(atPath: page.path) { await openPage() } else { askToWritePage = true }
        case .note:
            model.wantsWindow = true
            openWindow(id: "main")
            terminal.type("tv passage show welcome/\(login)\n")
            explaining = .note
        case .agent, .guestbook:
            explaining = item
        }
    }

    private func writePageAndOpen() async {
        guard let s = model.status else { return }
        let www = URL(fileURLWithPath: s.folder).appendingPathComponent("www")
        try? FileManager.default.createDirectory(at: www, withIntermediateDirectories: true)
        let html = "<!doctype html>\n<title>Hello from \(s.name)</title>\n<h1>Hello from \(s.name)</h1>\n"
        try? html.write(to: www.appendingPathComponent("hello-\(s.login).html"), atomically: true, encoding: .utf8)
        await openPage()
    }

    /// Opens the page through the box, then checks for it as it syncs round.
    private func openPage() async {
        guard let s = model.status else { return }
        for _ in 0..<12 {
            await tour.checkPage(port: s.port, login: s.login)
            if tour.isDone(.page) { break }
            try? await Task.sleep(for: .seconds(10))
        }
        _ = try? await model.tv.run(["pages", "hello-\(s.login).html"])
    }

    private func recheck() async {
        if let s = model.status, !tour.isDone(.page) { await tour.checkPage(port: s.port, login: s.login) }
        if let c = model.changes, let name = model.status?.name { tour.checkGuestbook(changes: c, name: name) }
    }
}

extension TutorialItem: Identifiable { var id: String { rawValue } }

/// How to do the items the app can't do for you.
private struct Explanation: View {
    let item: TutorialItem
    let tour: TutorialProgress
    let login: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.title).font(.headline)
            Text(text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                if item == .note || item == .agent {
                    Button("I've Done This") { tour.mark(item); dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20).frame(width: 440)
    }

    private var text: String {
        switch item {
        case .note:
            "In the window's terminal: tv passage show welcome/\(login). That's a note Danny left for you in TV's shared secrets, decrypted with your own key. (Every member can read the store; nothing in it is private from the rest of TV.)"
        case .agent:
            "Start your agent in the TV folder (in the terminal, it's already there): claude, or codex, or whichever you use. Then ask it: \"What is Terminal Values, and what can I do here?\" It answers from CLAUDE.md, TV's briefing for agents."
        case .guestbook:
            "In the terminal: tv catch-up first. Then have your agent add a line about your setup to the log at the end of WELCOME2TV.md, and: tv git add WELCOME2TV.md, tv git commit -m \"\(login) signs the guestbook\", tv push. This ticks itself once your commit reaches tvhome."
        case .page:
            ""
        }
    }
}
