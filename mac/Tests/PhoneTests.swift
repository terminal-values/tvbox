import AppKit
import Testing
@testable import TerminalValues

@MainActor @Suite struct PhoneTests {
    static let json = #"{"url": "https://box.example.org/#join=tskey-auth-FAKE", "expires": 600}"#

    @Test func phoneLinkDecodes() async throws {
        let fake = try FakeTV(answers: ["phone": Self.json])
        let link = try await fake.tv.json(PhoneLink.self, ["phone", "--json"])
        #expect(link.url == "https://box.example.org/#join=tskey-auth-FAKE")
        #expect(link.expires == 600)
    }

    @Test func qrImageIsSquareAndNonEmpty() throws {
        let image = try #require(qrImage(for: "https://box.example.org/#join=tskey-auth-FAKE"))
        #expect(image.size.width == image.size.height)
        #expect(image.size.width > 100)
        #expect(image.tiffRepresentation != nil)
    }

    @Test func menuRunsPhoneJSON() async throws {
        let fake = try FakeTV(answers: ["phone": Self.json])
        let phone = PhoneModel(tv: fake.tv)
        await phone.load()
        #expect(fake.calls == ["phone --json"])
        #expect(phone.image != nil)
        #expect(phone.error == nil)
        #expect(phone.secondsLeft(now: phone.loadedAt!) == 600)
    }

    @Test func errorShowsMessage() async throws {
        let msg = "TVhome won't pair a phone for this box: not a member"
        let fake = try FakeTV(exits: ["phone": 1], env: [:])
        try msg.write(to: fake.dir.appendingPathComponent("phone.err"), atomically: true, encoding: .utf8)
        let phone = PhoneModel(tv: fake.tv)
        await phone.load()
        #expect(phone.image == nil)
        #expect(phone.error == msg)
    }
}
