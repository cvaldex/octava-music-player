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

        // Fase 1: el escáner ahora guarda el bitrate. Igual que v2, fuerza a releer los tags una vez.
        migrator.registerMigration("v3") { db in
            try db.execute(sql: "UPDATE track SET fileModifiedAt = ?", arguments: [Date(timeIntervalSince1970: 0)])
        }

        // Fase 1: los géneros guardados como código numérico de ID3v1 ("17", "(9)") pasan a su nombre.
        migrator.registerMigration("v4") { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, genre FROM track WHERE genre GLOB '[0-9]*' OR genre GLOB '(*'")
            for row in rows {
                let id: Int64 = row["id"]
                let genre: String? = row["genre"]
                try db.execute(sql: "UPDATE track SET genre = ? WHERE id = ?", arguments: [TagReader.cleanGenre(genre), id])
            }
        }

        // Fase 5: la cola de scrobbles guarda también el artista del álbum y el número de pista.
        migrator.registerMigration("v5") { db in
            try db.alter(table: "scrobbleQueue") { t in
                t.add(column: "albumArtist", .text)
                t.add(column: "trackNumber", .integer)
            }
        }

        // Los discos pasan a agruparse por "Artist" (TPE1) en vez de "Album Artist" (TPE2): las compilaciones quedan
        // como un solo disco de "Various Artists". Se fuerza a releer los tags para reagruparlos (se conservan las
        // estadísticas: van en cada canción).
        migrator.registerMigration("v6") { db in
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

// MARK: - Edición de tags (historial para deshacer)

/// Una edición guardada: la canción y los valores que tenía antes.
struct TagEditRecord: Sendable {
    var id: Int64
    var trackId: Int64
    var previous: TagChanges
}

extension AppDatabase {
    /// Guarda los valores anteriores de un lote de ediciones. Todas comparten `editedAt`: así se deshacen juntas.
    func recordTagEdits(_ edits: [(trackId: Int64, previous: TagChanges)], at date: Date) throws {
        try writer.write { db in
            for edit in edits {
                let json = String(decoding: try JSONEncoder().encode(edit.previous), as: UTF8.self)
                try db.execute(sql: "INSERT INTO tagEditHistory (trackId, previousTags, editedAt) VALUES (?, ?, ?)",
                               arguments: [edit.trackId, json, date])
            }
        }
    }

    /// El último lote de ediciones (el que deshace "Deshacer edición de tags").
    func latestTagEditBatch() -> [TagEditRecord] {
        (try? writer.read { db -> [TagEditRecord] in
            guard let latest = try Date.fetchOne(db, sql: "SELECT MAX(editedAt) FROM tagEditHistory") else { return [] }
            let rows = try Row.fetchAll(db, sql: "SELECT id, trackId, previousTags FROM tagEditHistory WHERE editedAt = ?",
                                        arguments: [latest])
            return rows.compactMap { row in
                let json: String = row["previousTags"]
                guard let previous = try? JSONDecoder().decode(TagChanges.self, from: Data(json.utf8)) else { return nil }
                return TagEditRecord(id: row["id"], trackId: row["trackId"], previous: previous)
            }
        }) ?? []
    }

    func deleteTagEdits(_ ids: [Int64]) throws {
        try writer.write { db in
            for id in ids {
                try db.execute(sql: "DELETE FROM tagEditHistory WHERE id = ?", arguments: [id])
            }
        }
    }

    var hasTagEdits: Bool {
        let count = try? writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tagEditHistory") ?? 0 }
        return (count ?? 0) > 0
    }

    /// Marca canciones para que el próximo escaneo vuelva a leer sus tags (conserva las estadísticas).
    /// Si cambió la carátula, también se descarta la miniatura de sus discos.
    func markForReread(trackIDs: [Int64], clearingCovers: Bool) throws {
        try writer.write { db in
            for id in trackIDs {
                try db.execute(sql: "UPDATE track SET fileModifiedAt = ? WHERE id = ?",
                               arguments: [Date(timeIntervalSince1970: 0), id])
                if clearingCovers {
                    try db.execute(sql: "UPDATE album SET coverCachePath = NULL WHERE id = (SELECT albumId FROM track WHERE id = ?)",
                                   arguments: [id])
                }
            }
        }
    }
}

// MARK: - Cola de scrobbles (sin conexión)

struct PendingScrobble: Sendable {
    var id: Int64
    var item: ScrobbleItem
    var attempts: Int
}

extension AppDatabase {
    func enqueueScrobble(_ item: ScrobbleItem) throws {
        try writer.write { db in
            try db.execute(sql: """
                INSERT INTO scrobbleQueue (artist, title, album, albumArtist, trackNumber, startedAt, duration, attempts)
                VALUES (?, ?, ?, ?, ?, ?, ?, 0)
                """, arguments: [item.artist, item.title, item.album, item.albumArtist, item.trackNumber,
                                 item.startedAt, item.duration])
        }
    }

    /// Los más antiguos primero.
    func pendingScrobbles(limit: Int) -> [PendingScrobble] {
        (try? writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM scrobbleQueue ORDER BY startedAt LIMIT ?", arguments: [limit]).map { row in
                PendingScrobble(id: row["id"],
                                item: ScrobbleItem(artist: row["artist"], title: row["title"], album: row["album"],
                                                   albumArtist: row["albumArtist"], trackNumber: row["trackNumber"],
                                                   duration: row["duration"], startedAt: row["startedAt"]),
                                attempts: row["attempts"])
            }
        }) ?? []
    }

    var pendingScrobbleCount: Int {
        (try? writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM scrobbleQueue") ?? 0 }) ?? 0
    }

    func deleteScrobbles(_ ids: [Int64]) throws {
        try writer.write { db in
            for id in ids { try db.execute(sql: "DELETE FROM scrobbleQueue WHERE id = ?", arguments: [id]) }
        }
    }

    /// Suma un intento fallido y descarta los que ya fallaron `maxAttempts` veces.
    func markScrobblesFailed(_ ids: [Int64], maxAttempts: Int) throws {
        try writer.write { db in
            for id in ids {
                try db.execute(sql: "UPDATE scrobbleQueue SET attempts = attempts + 1 WHERE id = ?", arguments: [id])
            }
            try db.execute(sql: "DELETE FROM scrobbleQueue WHERE attempts >= ?", arguments: [maxAttempts])
        }
    }

    /// Descarta lo que Last.fm ya no aceptaría (más de 14 días). Devuelve cuántos se borraron.
    @discardableResult
    func dropScrobbles(olderThan date: Date) throws -> Int {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM scrobbleQueue WHERE startedAt < ?", arguments: [date])
            return db.changesCount
        }
    }
}
