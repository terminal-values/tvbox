import Foundation
import Observation

/// The four things the short tour asks a new member to try (the rest of
/// what was WELCOME2TV.md's stages 5 to 8).
enum TutorialItem: String, CaseIterable, Sendable {
    case page, note, agent, guestbook

    var title: String {
        switch self {
        case .page: "Put something on the wall"
        case .note: "A note left just for you"
        case .agent: "Your agent has read the manual"
        case .guestbook: "Sign the guestbook"
        }
    }

    var detail: String {
        switch self {
        case .page: "A page of your own in www/, seen through tvhome by every member."
        case .note: "Your welcome note, from TV's shared secrets, opened with your own key."
        case .agent: "Start your agent (Claude Code, Codex or another) in the TV folder."
        case .guestbook: "Catch up, change something, commit, push: the everyday loop, once."
        }
    }
}

/// What's been tried. Items 1 and 4 tick themselves when the app sees them
/// work; 2 and 3 when the member says so.
@MainActor @Observable
final class TutorialProgress {
    private let defaults: UserDefaults
    private let fetch: @Sendable (URL) async -> Int
    private(set) var done: Set<TutorialItem>

    init(defaults: UserDefaults = .standard,
         fetch: @escaping @Sendable (URL) async -> Int = TutorialProgress.httpStatus) {
        self.defaults = defaults
        self.fetch = fetch
        done = Set((defaults.stringArray(forKey: "tutorialDone") ?? []).compactMap(TutorialItem.init))
    }

    func isDone(_ item: TutorialItem) -> Bool { done.contains(item) }
    var allDone: Bool { done.count == TutorialItem.allCases.count }

    func mark(_ item: TutorialItem) {
        done.insert(item)
        defaults.set(done.map(\.rawValue), forKey: "tutorialDone")
    }

    /// The member's page answers through the box.
    func checkPage(port: Int, login: String) async {
        guard let url = URL(string: "http://127.0.0.1:\(port)/hello-\(login).html") else { return }
        if await fetch(url) == 200 { mark(.page) }
    }

    /// A commit of theirs has reached tvhome.
    func checkGuestbook(changes: Changes, name: String) {
        if changes.recent.contains(where: { $0.author == name }) { mark(.guestbook) }
    }

    nonisolated static func httpStatus(_ url: URL) async -> Int {
        guard let (_, response) = try? await URLSession.shared.data(from: url) else { return 0 }
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }
}
