import Foundation
import GRDB
import Observation

/// Lecturas y escrituras de la biblioteca para la interfaz.
@MainActor
@Observable
final class LibraryStore {
    private(set) var albums: [Album] = []
    private(set) var trackCount = 0
    private(set) var favoriteIDs: Set<Int64> = []
    private(set) var sort: AlbumSort = .artist

    func setSort(_ newSort: AlbumSort) {
        guard newSort != sort else { return }
        sort = newSort
        reload()
    }

    /// Cambia cada vez que se modifica una pista (favoritos, reproducciones), para que las vistas recarguen.
    private(set) var revision = 0

    @ObservationIgnored private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func reload() {
        do {
            let sort = self.sort
            favoriteIDs = try database.writer.read { db in
                Set(try Int64.fetchAll(db, sql: "SELECT id FROM track WHERE isFavorite = 1"))
            }
            (albums, trackCount) = try database.writer.read { db in
                let request: QueryInterfaceRequest<Album>
                switch sort {
                case .artist:
                    request = Album.order(Album.Columns.albumArtist.collating(.localizedCaseInsensitiveCompare),
                                          Album.Columns.year,
                                          Album.Columns.title.collating(.localizedCaseInsensitiveCompare))
                case .year:
                    request = Album.order(Album.Columns.year.desc,
                                          Album.Columns.albumArtist.collating(.localizedCaseInsensitiveCompare))
                case .added:
                    request = Album.order(Album.Columns.addedAt.desc, Album.Columns.id.desc)
                }
                return (try request.fetchAll(db), try Track.fetchCount(db))
            }
        } catch {
            print("Octava: error al leer la biblioteca: \(error)")
        }
    }

    /// Pistas de un disco en orden de disco y pista.
    func tracks(for album: Album) -> [Track] {
        guard let albumId = album.id else { return [] }
        return (try? database.writer.read { db in
            try Track
                .filter(Track.Columns.albumId == albumId)
                .order(Track.Columns.discNumber.ascNullsLast,
                       Track.Columns.trackNumber.ascNullsLast,
                       Track.Columns.title)
                .fetchAll(db)
        }) ?? []
    }

    func allTracks() -> [Track] {
        (try? database.writer.read { db in try Track.fetchAll(db) }) ?? []
    }

    func toggleFavorite(_ track: Track) {
        guard let id = track.id else { return }
        do {
            let nowFavorite = try database.writer.write { db -> Bool in
                guard var stored = try Track.fetchOne(db, key: id) else { return false }
                stored.isFavorite.toggle()
                try stored.update(db)
                return stored.isFavorite
            }
            if nowFavorite { favoriteIDs.insert(id) } else { favoriteIDs.remove(id) }
            // Fase 5: sincronizar con track.love / track.unlove de Last.fm.
            revision += 1
        } catch {
            print("Octava: no se pudo cambiar el favorito: \(error)")
        }
    }

    func markPlayed(_ track: Track) {
        guard let id = track.id else { return }
        do {
            try database.writer.write { db in
                guard var stored = try Track.fetchOne(db, key: id) else { return }
                stored.playCount += 1
                stored.lastPlayedAt = Date()
                try stored.update(db)
            }
            revision += 1
        } catch {
            print("Octava: no se pudo registrar la reproducción: \(error)")
        }
    }

    func isFavorite(_ track: Track) -> Bool {
        guard let id = track.id else { return false }
        return favoriteIDs.contains(id)
    }
}
