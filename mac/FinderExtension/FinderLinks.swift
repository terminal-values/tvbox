import AppKit
import FinderSync

/// Copy TVhome Link in the Finder's right-click menu. A Finder Sync extension
/// rather than a Service, so the item shows only inside the TVhome Folder,
/// at the top level of the menu. The links themselves are TVLink's.
final class FinderLinks: FIFinderSync {
    /// Follows tv move: the Finder only asks about the folder it's told to
    /// watch, so once the old folder is gone no menu would ever re-read it.
    private var configWatcher: DirectoryWatcher?

    override init() {
        super.init()
        Self.watchTheFolder()
        configWatcher = DirectoryWatcher(directory: Self.configDirectory, queue: .main) {
            Self.watchTheFolder()
        }
    }

    /// tv's config directory in the real home, from the password database,
    /// since NSHomeDirectory() is the sandbox's container.
    private static var configDirectory: URL {
        let home = getpwuid(getuid())?.pointee.pw_dir.map { String(cString: $0) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appending(path: ".config/tv")
    }

    /// The folder, from tv's config: the one place that says where it is.
    private static var folder: URL? {
        guard let text = try? String(contentsOf: configDirectory.appending(path: "config"), encoding: .utf8),
              let path = TVLink.folder(fromConfig: text) else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Tells the Finder which folder to ask about, read afresh when the
    /// config changes and before each menu.
    @discardableResult
    private static func watchTheFolder() -> URL? {
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
        guard menuKind == .contextualMenuForItems, let folder = Self.watchTheFolder() else { return nil }
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
        guard let folder = Self.folder, case .success(let links) = selectedLinks(folder: folder),
              !links.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(links.joined(separator: "\n"), forType: .string)
    }
}
