import Foundation

/// What a tvhome: URL opened by macOS asks the app to do. tv update, on a
/// Mac with the app, opens tvhome://update, so the app (which keeps itself,
/// its tv and the box in step) checks for updates; anything else under
/// tvhome: is a TVhome link, from a link page's "Open on this computer".
enum AppRequest: Equatable {
    case update
    case link(String)

    init?(_ url: URL) {
        guard url.scheme?.lowercased() == "tvhome" else { return nil }
        if url.host()?.lowercased() == "update" { self = .update } else { self = .link(url.absoluteString) }
    }
}
