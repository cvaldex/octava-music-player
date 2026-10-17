import Foundation
import GRDB
import Observation

/// Una lista guardada. Sus canciones están en la tabla `playlistItem` (id de canción + posición).
struct Playlist: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var name: String
    /// "manual" (armada a mano) o "generated" (guardada desde la cola o una mezcla).
    var kind: String
    var createdAt: Date

    static let databaseTableName = "playlist"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// Listas guardadas: crear, agregar, reordenar, quitar, renombrar y borrar.
/// Guarda solo ids de canciones: si una canción desaparece de la colección, deja de aparecer en la lista.
@MainActor
@Observable
final class PlaylistStore {
    private(set) var playlists: [Playlist] = []
    /// Cambia con cada modificación del contenido de cualquier lista, para que las vistas recarguen.
    private(set) var revision = 0

    @ObservationIgnored private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func reload() {
        playlists = (try? database.writer.read { db in
            try Playlist.order(Column("name").collating(.localizedCaseInsensitiveCompare)).fetchAll(db)
        }) ?? []
    }

    func playlist(id: Int64) -> Playlist? {
        playlists.first { $0.id == id }
    }

    /// Ids de las canciones de una lista, en orden.
    func trackIDs(for playlistID: Int64) -> [Int64] {
        (try? database.writer.read { db in
            try Int64.fetchAll(db, sql: "SELECT trackId FROM playlistItem WHERE playlistId = ? ORDER BY position",
                               arguments: [playlistID])
        }) ?? []
    }

    @discardableResult
    func create(name: String, trackIDs: [Int64], kind: String? = nil) -> Int64? {
        let cleanName = Self.clean(name)
        do {
            let id = try database.writer.write { db -> Int64? in
                var playlist = Playlist(name: cleanName,
                                        kind: kind ?? (trackIDs.isEmpty ? "manual" : "generated"),
                                        createdAt: Date())
                try playlist.insert(db)
                guard let id = playlist.id else { return nil }
                try Self.writeItems(trackIDs, playlistID: id, db: db)
                return id
            }
            reload()
            revision += 1
            return id
        } catch {
            print("Octava: no se pudo crear la lista: \(error)")
            return nil
        }
    }

    func append(trackIDs: [Int64], to playlistID: Int64) {
        guard !trackIDs.isEmpty else { return }
        setTrackIDs(self.trackIDs(for: playlistID) + trackIDs, for: playlistID)
    }

    /// Reemplaza el contenido completo de la lista (para reordenar o quitar canciones).
    func setTrackIDs(_ trackIDs: [Int64], for playlistID: Int64) {
        do {
            try database.writer.write { db in
                try Self.writeItems(trackIDs, playlistID: playlistID, db: db)
            }
            revision += 1
        } catch {
            print("Octava: no se pudo actualizar la lista: \(error)")
        }
    }

    func removeItems(atOffsets offsets: IndexSet, from playlistID: Int64) {
        var ids = trackIDs(for: playlistID)
        for offset in offsets.sorted(by: >) where ids.indices.contains(offset) {
            ids.remove(at: offset)
        }
        setTrackIDs(ids, for: playlistID)
    }

    func moveItems(fromOffsets source: IndexSet, toOffset destination: Int, in playlistID: Int64) {
        setTrackIDs(Self.moved(trackIDs(for: playlistID), fromOffsets: source, toOffset: destination), for: playlistID)
    }

    func rename(_ playlistID: Int64, to name: String) {
        let cleanName = Self.clean(name)
        do {
            try database.writer.write { db in
                try db.execute(sql: "UPDATE playlist SET name = ? WHERE id = ?", arguments: [cleanName, playlistID])
            }
            reload()
        } catch {
            print("Octava: no se pudo renombrar la lista: \(error)")
        }
    }

    func delete(_ playlistID: Int64) {
        do {
            try database.writer.write { db in
                // playlistItem se borra en cascada.
                try db.execute(sql: "DELETE FROM playlist WHERE id = ?", arguments: [playlistID])
            }
            reload()
            revision += 1
        } catch {
            print("Octava: no se pudo eliminar la lista: \(error)")
        }
    }

    // MARK: Ayudas

    private static func writeItems(_ trackIDs: [Int64], playlistID: Int64, db: Database) throws {
        try db.execute(sql: "DELETE FROM playlistItem WHERE playlistId = ?", arguments: [playlistID])
        for (position, trackID) in trackIDs.enumerated() {
            try db.execute(sql: "INSERT INTO playlistItem (playlistId, trackId, position) VALUES (?, ?, ?)",
                           arguments: [playlistID, trackID, position])
        }
    }

    static func clean(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Lista sin nombre" : trimmed
    }

    /// Reordena como lo hace `onMove` de SwiftUI. Lógica pura, testeada.
    static func moved<T>(_ items: [T], fromOffsets source: IndexSet, toOffset destination: Int) -> [T] {
        var items = items
        let valid = source.filter { $0 < items.count }.sorted()
        guard !valid.isEmpty else { return items }
        let moving = valid.map { items[$0] }
        for offset in valid.reversed() {
            items.remove(at: offset)
        }
        let adjusted = destination - valid.filter { $0 < destination }.count
        items.insert(contentsOf: moving, at: min(max(0, adjusted), items.count))
        return items
    }
}
