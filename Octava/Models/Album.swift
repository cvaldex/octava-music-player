import Foundation
import GRDB

/// Un disco, agrupado por artista del álbum + título.
struct Album: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var title: String
    var albumArtist: String
    var year: Int?
    /// Carpeta del disco, relativa a la carpeta de música.
    var folderPath: String
    /// Miniatura de la carátula en la caché de la app (ruta absoluta).
    var coverCachePath: String?
    /// Momento en que el disco entró a la biblioteca (orden "Agregados").
    var addedAt: Date = Date()

    static let databaseTableName = "album"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let title = Column(CodingKeys.title)
        static let albumArtist = Column(CodingKeys.albumArtist)
        static let year = Column(CodingKeys.year)
        static let coverCachePath = Column(CodingKeys.coverCachePath)
        static let addedAt = Column(CodingKeys.addedAt)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// Orden de la grilla de álbumes.
enum AlbumSort: String, CaseIterable, Identifiable {
    case artist = "Artista"
    case year = "Año"
    case added = "Agregados"

    var id: String { rawValue }
}
