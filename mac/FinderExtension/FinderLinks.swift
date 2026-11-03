import AppKit
import FinderSync

/// Copy TVhome Link in the Finder's right-click menu. A Finder Sync extension
/// rather than a Service, so the item shows only inside the TVhome Folder,
/// at the top level of the menu. The links themselves are TVLink's.
final class FinderLinks: FIFinderSync {
    override init() {
        super.init()
        watchTheFolder()
    }

    /// The folder, from tv's config: the one place that says where it is.
    /// The real home comes from the password database, since
    /// NSHomeDirectory() is the sandbox's container.
    private var folder: URL? {
        guard let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir else { return nil }
        let config = URL(fileURLWithPath: String(cString: home)).appending(path: ".config/tv/config")
        guard let text = try? String(contentsOf: config, encoding: .utf8),
              let path = TVLink.folder(fromConfig: text) else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Tells the Finder which folder to ask about, read afresh each time so
    /// a tv move is picked up.
    @discardableResult
    private func watchTheFolder() -> URL? {
        let folder = folder
        let urls: Set<URL> = folder.map { [$0] } ?? []
        let controller = FIFinderSyncController.default()
        if controller.directoryURLs != urls { controller.directoryURLs = urls }
        return folder
    }

    /// The selected items' links, or why the first one that can't link doesn't.
    private func selectedLinks(folder: URL) -> Result<[String], TVLink.Refusal> {
        var links: [String] = []
        for item in FIFinderSyncController.default().selectedItemURLs() ?? [] {
            switch TVLink.link(for: item, folder: folder) {
            case .success(let link): links.append(link)
            case .failure(let refusal): return .failure(refusal)
            }
        }
        return .success(links)
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems, let folder = watchTheFolder() else { return nil }
        let menu = NSMenu(title: "")
        menu.autoenablesItems = false
        switch selectedLinks(folder: folder) {
        case .success(let links) where !links.isEmpty:
            let title = links.count == 1 ? "Copy TVhome Link" : "Copy TVhome Links"
            menu.addItem(withTitle: title, action: #selector(copyLinks(_:)), keyEquivalent: "")
        case .failure(let refusal) where refusal != .outside:
            // Disabled, so the member sees why there's no link rather than nothing.
            let item = NSMenuItem(title: TVLink.notice(refusal), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        default:
            return nil
        }
        return menu
    }

    /// The Finder calls this with its own copy of the menu item, so the
    /// selection is asked for again.
    @objc func copyLinks(_ sender: AnyObject?) {
        guard let folder = folder, case .success(let links) = selectedLinks(folder: folder),
              !links.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(links.joined(separator: "\n"), forType: .string)
    }
}
