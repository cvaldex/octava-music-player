import Foundation
import GRDB

/// Prueba de diagnóstico del escáner con la app compilada tal cual (Release): se lanza con la variable de entorno
/// OCTAVA_SCAN_SELFTEST=<carpeta> y escribe el resultado en la salida estándar. Usa una base en memoria: no toca
/// la biblioteca real. Si la carpeta no existe, genera MP3 de silencio con títulos conocidos.
enum ScanSelfTest {
    static func runIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["OCTAVA_SCAN_SELFTEST"] else { return }
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                let root = path == "tmp"
                    ? FileManager.default.temporaryDirectory.appendingPathComponent("octava-selftest-\(UUID().uuidString)")
                    : URL(fileURLWithPath: path)
                try await run(root: root)
            } catch {
                print("SELFTEST ERROR \(error)")
            }
            done.signal()
        }
        done.wait()
        exit(0)
    }

    private static func run(root: URL) async throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: root.path) {
            for album in 1...6 {
                for n in 1...14 {
                    let title = "Disco\(album) Tema \(n)"
                    var audio: [UInt8] = []
                    for _ in 0..<(30 + album * 11 + n * 5) { audio += [0xFF, 0xFB, 0x90, 0x64] + [UInt8](repeating: 0, count: 413) }
                    let data = try ID3TagWriter.apply(TagChanges(text: [.title: title, .artist: "Banda", .album: "Disco \(album)"]),
                                                      to: Data(audio))
                    let url = root.appendingPathComponent("Banda - Disco \(album)/\(String(format: "%02d", n)) - \(title).mp3")
                    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: url)
                }
            }
        }
        let database = try AppDatabase.makeEmpty()
        let scanner = LibraryScanner(database: database)
        let summary = try await scanner.scan(root: root) { _ in }
        let tracks = try await database.writer.read { db in try Track.fetchAll(db) }
        var mismatches = 0
        for track in tracks {
            let file = (track.relativePath as NSString).lastPathComponent
            if !file.contains(track.title) {
                mismatches += 1
                if mismatches <= 10 { print("SELFTEST MISMATCH id=\(track.id ?? -1) \(track.relativePath) title=\(track.title)") }
            }
        }
        print("SELFTEST added=\(summary.added) failed=\(summary.failed) rows=\(tracks.count) mismatches=\(mismatches)")
    }
}
