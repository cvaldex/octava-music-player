import Foundation

/// Un artista (del álbum) con sus discos.
struct ArtistSummary: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let albumCount: Int
    /// Disco representativo para mostrar su carátula.
    let coverAlbum: Album?
}

/// Un género con su cantidad de canciones.
struct GenreSummary: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let trackCount: Int
}

/// Resultado de una búsqueda.
struct SearchResults {
    var albums: [Album] = []
    var tracks: [Track] = []
    var isEmpty: Bool { albums.isEmpty && tracks.isEmpty }
}

/// Agrupaciones y búsqueda sobre la biblioteca. Lógica pura, testeada.
enum LibraryIndex {
    /// Artistas a partir de los discos (agrupados por artista del álbum), en orden alfabético.
    static func artists(from albums: [Album]) -> [ArtistSummary] {
        let groups = Dictionary(grouping: albums, by: \.albumArtist)
        return groups.map { name, albums in
            let sorted = albums.sorted { ($0.year ?? 0, $0.title) < ($1.year ?? 0, $1.title) }
            return ArtistSummary(name: name, albumCount: albums.count, coverAlbum: sorted.first)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Géneros a partir de las canciones (las que no tienen género se omiten), en orden alfabético.
    static func genres(from tracks: [Track]) -> [GenreSummary] {
        var counts: [String: Int] = [:]
        for track in tracks {
            guard let genre = track.genre?.trimmingCharacters(in: .whitespaces), !genre.isEmpty else { continue }
            counts[genre, default: 0] += 1
        }
        return counts.map { GenreSummary(name: $0.key, trackCount: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// ¿Contiene el texto todas las palabras de la búsqueda? Sin distinguir mayúsculas ni acentos.
    static func matches(_ query: String, in fields: [String]) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return false }
        let haystack = fields.joined(separator: " ")
        return words.allSatisfy { haystack.localizedStandardContains($0) }
    }

    static func search(_ query: String, albums: [Album], tracks: [Track], trackLimit: Int = 500) -> SearchResults {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SearchResults() }
        let foundAlbums = albums.filter { matches(trimmed, in: [$0.title, $0.albumArtist]) }
        var foundTracks: [Track] = []
        for track in tracks where matches(trimmed, in: [track.title, track.artist, track.album]) {
            foundTracks.append(track)
            if foundTracks.count >= trackLimit { break }
        }
        return SearchResults(albums: foundAlbums, tracks: foundTracks)
    }

    /// Bitrate para mostrar en un disco: el valor si todas las pistas coinciden; si no, el promedio aproximado.
    static func bitrateLabel(for tracks: [Track]) -> String? {
        let rates = tracks.compactMap(\.bitrate).filter { $0 > 0 }
        guard !rates.isEmpty else { return nil }
        if Set(rates).count == 1, let rate = rates.first { return "\(rate) kbps" }
        let average = Double(rates.reduce(0, +)) / Double(rates.count)
        return "~\(Int(average.rounded())) kbps"
    }
}

extension Track {
    /// Claves no opcionales para ordenar en tablas.
    var sortYear: Int { year ?? 0 }
    var sortGenre: String { genre ?? "" }
    var sortTrackNumber: Int { (discNumber ?? 1) * 1000 + (trackNumber ?? 0) }
}
