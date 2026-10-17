import Foundation
import GRDB
import Observation

/// Lecturas y escrituras de la biblioteca para la interfaz.
/// Mantiene en memoria los discos y las canciones (una colección de decenas de miles de pistas cabe sin problema),
/// para que las vistas de artistas, géneros y la búsqueda sean instantáneas.
@MainActor
@Observable
final class LibraryStore {
    private(set) var albums: [Album] = []
    /// Todas las canciones, en orden de artista, disco y pista.
    private(set) var tracks: [Track] = []
    private(set) var artists: [ArtistSummary] = []
    private(set) var genres: [GenreSummary] = []
    private(set) var favoriteIDs: Set<Int64> = []
    private(set) var sort: AlbumSort = .artist

    var trackCount: Int { tracks.count }

    /// Cambia cada vez que se modifica una pista (favoritos, reproducciones), para que las vistas recarguen.
    private(set) var revision = 0

    @ObservationIgnored private let database: AppDatabase
    @ObservationIgnored private var trackIndexByID: [Int64: Int] = [:]

    init(database: AppDatabase) {
        self.database = database
    }

    func setSort(_ newSort: AlbumSort) {
        guard newSort != sort else { return }
        sort = newSort
        reload()
    }

    func reload() {
        do {
            let sort = self.sort
            let (loadedAlbums, loadedTracks) = try database.writer.read { db in
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
                return (try request.fetchAll(db), try Track.fetchAll(db))
            }
            albums = loadedAlbums
            tracks = Self.sortedForLibrary(loadedTracks)
            rebuildIndexes()
        } catch {
            print("Octava: error al leer la biblioteca: \(error)")
        }
    }

    /// Orden de la biblioteca: artista del álbum (o artista, si no hay), disco, número de disco y de pista.
    static func sortedForLibrary(_ tracks: [Track]) -> [Track] {
        tracks.sorted { a, b in
            let artist = a.groupingArtist.localizedStandardCompare(b.groupingArtist)
            if artist != .orderedSame { return artist == .orderedAscending }
            let album = a.album.localizedStandardCompare(b.album)
            if album != .orderedSame { return album == .orderedAscending }
            if a.sortTrackNumber != b.sortTrackNumber { return a.sortTrackNumber < b.sortTrackNumber }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    private func rebuildIndexes() {
        trackIndexByID = Dictionary(tracks.enumerated().compactMap { index, track in track.id.map { ($0, index) } },
                                    uniquingKeysWith: { first, _ in first })
        favoriteIDs = Set(tracks.filter(\.isFavorite).compactMap(\.id))
        artists = LibraryIndex.artists(from: albums)
        genres = LibraryIndex.genres(from: tracks)
    }

    // MARK: Consultas

    /// Pistas de un disco en orden de disco y pista.
    func tracks(for album: Album) -> [Track] {
        guard let albumId = album.id else { return [] }
        return tracks
            .filter { $0.albumId == albumId }
            .sorted { ($0.sortTrackNumber, $0.title) < ($1.sortTrackNumber, $1.title) }
    }

    /// Pistas por id, en el orden pedido (se omiten las que ya no existen; los ids repetidos se respetan).
    func tracks(ids: [Int64]) -> [Track] {
        ids.compactMap { id in trackIndexByID[id].map { tracks[$0] } }
    }

    func allTracks() -> [Track] {
        tracks
    }

    func album(id: Int64?) -> Album? {
        guard let id else { return nil }
        return albums.first { $0.id == id }
    }

    /// Discos de un artista, del más antiguo al más reciente.
    func albums(byArtist name: String) -> [Album] {
        albums
            .filter { $0.albumArtist == name }
            .sorted { ($0.year ?? 0, $0.title) < ($1.year ?? 0, $1.title) }
    }

    /// Canciones de un artista, disco por disco en orden.
    func tracks(byArtist name: String) -> [Track] {
        albums(byArtist: name).flatMap { tracks(for: $0) }
    }

    func tracks(inGenre name: String) -> [Track] {
        tracks.filter { $0.genre?.trimmingCharacters(in: .whitespaces) == name }
    }

    var favoriteTracks: [Track] {
        tracks.filter { $0.id.map(favoriteIDs.contains) ?? false }
    }

    func search(_ query: String) -> SearchResults {
        LibraryIndex.search(query, albums: albums, tracks: tracks)
    }

    func isFavorite(_ track: Track) -> Bool {
        guard let id = track.id else { return false }
        return favoriteIDs.contains(id)
    }

    // MARK: Cambios

    func toggleFavorite(_ track: Track) {
        guard let id = track.id else { return }
        do {
            let updated = try database.writer.write { db -> Track? in
                guard var stored = try Track.fetchOne(db, key: id) else { return nil }
                stored.isFavorite.toggle()
                try stored.update(db)
                return stored
            }
            guard let updated else { return }
            if updated.isFavorite { favoriteIDs.insert(id) } else { favoriteIDs.remove(id) }
            replaceInCache(updated)
            // Fase 5: sincronizar con track.love / track.unlove de Last.fm.
            revision += 1
        } catch {
            print("Octava: no se pudo cambiar el favorito: \(error)")
        }
    }

    func markPlayed(_ track: Track) {
        guard let id = track.id else { return }
        do {
            let updated = try database.writer.write { db -> Track? in
                guard var stored = try Track.fetchOne(db, key: id) else { return nil }
                stored.playCount += 1
                stored.lastPlayedAt = Date()
                try stored.update(db)
                return stored
            }
            if let updated { replaceInCache(updated) }
            revision += 1
        } catch {
            print("Octava: no se pudo registrar la reproducción: \(error)")
        }
    }

    private func replaceInCache(_ track: Track) {
        guard let id = track.id, let index = trackIndexByID[id], tracks.indices.contains(index) else { return }
        tracks[index] = track
    }
}
