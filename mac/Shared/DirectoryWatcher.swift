import Foundation

/// Calls onChange when a directory's entries change: a file added, removed
/// or renamed over another. The Finder extension watches tv's config
/// directory with it, since write_config replaces the file by rename, which
/// a watch on the file itself would lose.
final class DirectoryWatcher {
    private let source: DispatchSourceFileSystemObject

    /// nil if the directory can't be opened (it isn't there yet).
    init?(directory: URL, queue: DispatchQueue, onChange: @escaping @Sendable () -> Void) {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: queue)
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    deinit { source.cancel() }
}
