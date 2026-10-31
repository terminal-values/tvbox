import Foundation
import Testing
@testable import TerminalValues

@MainActor @Suite struct TutorialTests {
    func defaults() -> UserDefaults { UserDefaults(suiteName: "tv-tests-\(UUID().uuidString)")! }

    final class Asked: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        func add(_ u: URL) { lock.withLock { urls.append(u) } }
        var all: [URL] { lock.withLock { urls } }
    }

    @Test func pageDoneWhenServed() async throws {
        let asked = Asked()
        let tour = TutorialProgress(defaults: defaults()) { url in asked.add(url); return 200 }
        #expect(!tour.isDone(.page))
        await tour.checkPage(port: 8485, login: "sam")
        #expect(asked.all == [URL(string: "http://127.0.0.1:8485/hello-sam.html")!])
        #expect(tour.isDone(.page))
    }

    @Test func pageNotDoneWhenMissing() async throws {
        let tour = TutorialProgress(defaults: defaults()) { _ in 404 }
        await tour.checkPage(port: 8484, login: "sam")
        #expect(!tour.isDone(.page))
    }

    @Test func guestbookDoneWhenRecentHasMyCommit() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let changes = try decoder.decode(Changes.self, from: Data(Fixture.changes.utf8))
        let tour = TutorialProgress(defaults: defaults()) { _ in 0 }
        tour.checkGuestbook(changes: changes, name: "Sam Smith")
        #expect(!tour.isDone(.guestbook))
        tour.checkGuestbook(changes: changes, name: "Alex Example")
        #expect(tour.isDone(.guestbook))
    }

    @Test func tickedItemsStayTicked() {
        let d = defaults()
        let tour = TutorialProgress(defaults: d) { _ in 0 }
        tour.mark(.note)
        #expect(TutorialProgress(defaults: d) { _ in 0 }.isDone(.note))
        #expect(!tour.allDone)
    }
}
