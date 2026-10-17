import CoreServices
import Foundation

/// Vigila la carpeta de música con FSEvents y avisa cuando algo cambia (archivos agregados, borrados,
/// movidos o modificados, también en subcarpetas). Los eventos se agrupan: el aviso llega una vez,
/// unos segundos después de que los cambios se calman.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void

    /// Extensiones que importan; los cambios en otros archivos (.DS_Store, etc.) se ignoran.
    private static let relevantExtensions: Set<String> = ["mp3", "jpg", "jpeg", "png"]

    init(url: URL, latency: TimeInterval = 2.0, onChange: @escaping () -> Void) {
        self.onChange = onChange

        var context = FSEventStreamContext(version: 0,
                                           info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let pathList = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            let flagList = Array(UnsafeBufferPointer(start: flags, count: count))
            if FolderWatcher.isRelevant(paths: pathList, flags: flagList) {
                watcher.onChange()
            }
        }

        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        stream = FSEventStreamCreate(kCFAllocatorDefault,
                                     callback,
                                     &context,
                                     [url.path] as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                     latency,
                                     flags)
        if let stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
        }
    }

    deinit {
        stop()
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Un cambio importa si toca un MP3, una imagen de carátula o una carpeta (renombrar o mover un disco completo).
    static func isRelevant(paths: [String], flags: [FSEventStreamEventFlags]) -> Bool {
        for (index, path) in paths.enumerated() {
            let flag = index < flags.count ? Int(flags[index]) : 0
            if flag & kFSEventStreamEventFlagItemIsDir != 0 { return true }
            if flag & kFSEventStreamEventFlagMustScanSubDirs != 0 { return true }
            let ext = (path as NSString).pathExtension.lowercased()
            if relevantExtensions.contains(ext) { return true }
        }
        return false
    }
}
