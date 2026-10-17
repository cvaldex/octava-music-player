import Foundation
import GRDB

/// Base de datos SQLite de la biblioteca (GRDB).
/// El esquema incluye desde ya las tablas de fases futuras (listas, scrobbles, historial de tags)
/// para no tener que migrar datos reales más adelante.
final class AppDatabase: Sendable {
    let writer: DatabaseQueue

    init(_ writer: DatabaseQueue) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// Base de datos en ~/Library/Containers/local.octava.Octava/Data/Library/Application Support/Octava/.
    static func makeShared() throws -> AppDatabase {
        let folder = try Self.supportFolder()
        let url = folder.appendingPathComponent("library.sqlite")
        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(path: url.path, configuration: config)
        return try AppDatabase(queue)
    }

    /// Base de datos en memoria, para los tests.
    static func makeEmpty() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    static func supportFolder() throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = base.appendingPathComponent("Octava", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // Nota: no usar eraseDatabaseOnSchemaChange; la base guarda estadísticas que no se pueden reconstruir.
        // Cada cambio de esquema va en una migración nueva ("v2", "v3"…), nunca editando "v1".

        migrator.registerMigration("v1") { db in
            try db.create(table: "album") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                t.column("albumArtist", .text).notNull()
                t.column("year", .integer)
                t.column("folderPath", .text).notNull()
                t.column("coverCachePath", .text)
                t.column("addedAt", .datetime).notNull()
                t.uniqueKey(["albumArtist", "title"])
            }

            try db.create(table: "track") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("relativePath", .text).notNull().unique()
                t.column("fileModifiedAt", .datetime).notNull()
                t.column("title", .text).notNull()
                t.column("artist", .text).notNull()
                t.column("albumArtist", .text)
                t.column("album", .text).notNull()
                t.column("trackNumber", .integer)
                t.column("discNumber", .integer)
                t.column("year", .integer)
                t.column("genre", .text)
                t.column("duration", .double).notNull()
                t.column("bitrate", .integer)
                t.column("replayGainTrack", .double)
                t.column("replayGainAlbum", .double)
                t.column("playCount", .integer).notNull().defaults(to: 0)
                t.column("lastPlayedAt", .datetime)
                t.column("isFavorite", .boolean).notNull().defaults(to: false)
                t.column("albumId", .integer).indexed().references("album", onDelete: .setNull)
            }

            // Fase 3: listas guardadas.
            try db.create(table: "playlist") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("kind", .text).notNull() // "manual" | "generated"
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "playlistItem") { t in
                t.column("playlistId", .integer).notNull().references("playlist", onDelete: .cascade)
                t.column("trackId", .integer).notNull().references("track", onDelete: .cascade)
                t.column("position", .integer).notNull()
                t.primaryKey(["playlistId", "position"])
            }

            // Fase 5: cola offline de scrobbles.
            try db.create(table: "scrobbleQueue") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("artist", .text).notNull()
                t.column("title", .text).notNull()
                t.column("album", .text)
                t.column("startedAt", .datetime).notNull()
                t.column("duration", .double).notNull()
                t.column("attempts", .integer).notNull().defaults(to: 0)
            }

            // Fase 4: historial para deshacer ediciones de tags.
            try db.create(table: "tagEditHistory") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("trackId", .integer).notNull().references("track", onDelete: .cascade)
                t.column("previousTags", .text).notNull() // JSON
                t.column("editedAt", .datetime).notNull()
            }

            // Estado de la app (cola, posición). Fase 2: reanudar al abrir.
            try db.create(table: "appState") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
        }

        // Fase 2: el escáner ahora lee ReplayGain. Se marcan todas las pistas como "modificadas"
        // para que el próximo escaneo vuelva a leer sus tags (las estadísticas se conservan).
        migrator.registerMigration("v2") { db in
            try db.execute(sql: "UPDATE track SET fileModifiedAt = ?", arguments: [Date(timeIntervalSince1970: 0)])
        }

        return migrator
    }
}

// MARK: - Estado de reproducción (reanudar al abrir)

/// Instantánea de la cola para reanudar donde quedó.
struct PlaybackSnapshot: Codable, Equatable {
    var trackIDs: [Int64]
    var currentIndex: Int
    var position: Double
    var source: String
}

extension AppDatabase {
    private static let playbackKey = "playback"

    func savePlaybackSnapshot(_ snapshot: PlaybackSnapshot?) {
        do {
            try writer.write { db in
                if let snapshot {
                    let json = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
                    try db.execute(sql: "INSERT OR REPLACE INTO appState (key, value) VALUES (?, ?)",
                                   arguments: [Self.playbackKey, json])
                } else {
                    try db.execute(sql: "DELETE FROM appState WHERE key = ?", arguments: [Self.playbackKey])
                }
            }
        } catch {
            print("Octava: no se pudo guardar el estado de reproducción: \(error)")
        }
    }

    func loadPlaybackSnapshot() -> PlaybackSnapshot? {
        let json = try? writer.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM appState WHERE key = ?", arguments: [Self.playbackKey])
        }
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PlaybackSnapshot.self, from: data)
    }
}
