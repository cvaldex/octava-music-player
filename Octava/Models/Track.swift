import Foundation
import GRDB

/// Una canción de la colección. Los tags vienen del archivo MP3 (fuente de verdad);
/// las estadísticas (reproducciones, favorito) solo viven en la base de datos.
struct Track: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    /// Ruta relativa a la carpeta de música, para que la colección pueda moverse sin perder estadísticas.
    var relativePath: String
    /// Fecha de modificación del archivo: permite re-escanear solo lo que cambió.
    var fileModifiedAt: Date

    var title: String
    var artist: String
    var albumArtist: String?
    var album: String
    var trackNumber: Int?
    var discNumber: Int?
    var year: Int?
    var genre: String?
    var duration: Double
    var bitrate: Int?
    var replayGainTrack: Double?
    var replayGainAlbum: Double?

    var playCount: Int = 0
    var lastPlayedAt: Date?
    var isFavorite: Bool = false

    var albumId: Int64?

    static let databaseTableName = "track"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let relativePath = Column(CodingKeys.relativePath)
        static let title = Column(CodingKeys.title)
        static let artist = Column(CodingKeys.artist)
        static let trackNumber = Column(CodingKeys.trackNumber)
        static let discNumber = Column(CodingKeys.discNumber)
        static let albumId = Column(CodingKeys.albumId)
        static let playCount = Column(CodingKeys.playCount)
        static let lastPlayedAt = Column(CodingKeys.lastPlayedAt)
        static let isFavorite = Column(CodingKeys.isFavorite)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// Artista con el que se agrupa el disco: "Album Artist" si existe; si no, "Artist".
    var groupingArtist: String {
        if let albumArtist, !albumArtist.isEmpty { return albumArtist }
        return artist
    }
}
