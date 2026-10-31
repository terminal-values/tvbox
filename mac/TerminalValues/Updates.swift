import Foundation

/// The box image a release of the app was built with (Contents/Resources/
/// BoxImage.plist, written by mac/scripts/release.sh). Development builds
/// have none.
struct BoxImage: Equatable, Sendable {
    let digest: String
    let revision: String

    static func read(from resources: URL? = Bundle.main.resourceURL) -> BoxImage? {
        guard let resources,
              let data = try? Data(contentsOf: resources.appendingPathComponent("BoxImage.plist")),
              let dict = try? PropertyListDecoder().decode([String: String].self, from: data),
              let digest = dict["Digest"], let revision = dict["Revision"] else { return nil }
        return BoxImage(digest: digest, revision: revision)
    }
}

/// With the app installed, an update is an app update: after one, the box
/// moves to the image that release was built with, so the tv inside the app
/// and the scripts inside the box come from the same commit.
@MainActor
func moveBoxIfNeeded(model: AppModel, pinned: BoxImage?) async -> Bool {
    guard let pinned, model.isSetUp, let status = model.status,
          status.revision != pinned.revision else { return false }
    model.busy = "Moving the box to this version…"
    defer { model.busy = nil }
    let r = try? await model.tv.run(["update", "--to", pinned.digest, "--revision", pinned.revision],
                                    timeout: .seconds(900))
    if let r, r.status != 0 { model.lastError = r.stderr.isEmpty ? r.stdout : r.stderr }
    await model.refresh()
    return true
}
