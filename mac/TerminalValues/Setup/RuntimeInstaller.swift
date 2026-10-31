import AppKit
import Foundation

/// Fetches Apple's container installer and opens it: the member clicks
/// through Apple's own installer and types their password once.
enum RuntimeInstaller {
    static let latestRelease = URL(string: "https://api.github.com/repos/apple/container/releases/latest")!

    struct NotApples: Error, CustomStringConvertible {
        let output: String
        var description: String { "That installer isn't signed by Apple, so it wasn't opened." }
    }

    /// The .pkg in a GitHub release (JSON from the releases API).
    static func installerURL(fromRelease json: Data) throws -> URL {
        struct Release: Decodable {
            struct Asset: Decodable { let name: String; let browser_download_url: URL }
            let assets: [Asset]
        }
        let release = try JSONDecoder().decode(Release.self, from: json)
        let pkgs = release.assets.filter { $0.name.hasSuffix(".pkg") }
        guard let pick = pkgs.first(where: { $0.name.contains("signed") }) ?? pkgs.first else {
            throw URLError(.fileDoesNotExist)
        }
        return pick.browser_download_url
    }

    /// Downloads the newest installer to a temporary file.
    static func latestInstaller() async throws -> URL {
        let (json, _) = try await URLSession.shared.data(from: latestRelease)
        let (file, _) = try await URLSession.shared.download(from: try installerURL(fromRelease: json))
        let pkg = FileManager.default.temporaryDirectory.appendingPathComponent("container-installer.pkg")
        try? FileManager.default.removeItem(at: pkg)
        try FileManager.default.moveItem(at: file, to: pkg)
        return pkg
    }

    /// pkgutil's verdict says signed for distribution, by Apple itself.
    static func isApplesPackage(pkgutilOutput out: String) -> Bool {
        out.contains("Status: signed by a developer certificate issued by Apple for distribution")
            && out.contains("Developer ID Installer: Apple Inc.")
    }

    /// Refuses anything that isn't Apple's own signed package.
    static func verify(_ pkg: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        p.arguments = ["--check-signature", pkg.path]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        try p.run()
        p.waitUntilExit()
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard p.terminationStatus == 0, isApplesPackage(pkgutilOutput: text) else { throw NotApples(output: text) }
    }

    static func open(_ pkg: URL) { NSWorkspace.shared.open(pkg) }
}
