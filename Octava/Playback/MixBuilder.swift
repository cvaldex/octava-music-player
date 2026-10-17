import Foundation

/// De qué parte de la colección sale una mezcla.
enum MixSource: String, Codable, CaseIterable, Identifiable {
    case library, favorites, forgotten

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: "Toda la colección"
        case .favorites: "Favoritos"
        case .forgotten: "Hace tiempo sin oír"
        }
    }
}

/// Reglas de una mezcla. Dentro de cada filtro las opciones se suman (Metal o Thrash);
/// entre filtros se combinan (Metal o Thrash, y además de los 80). Un filtro vacío no restringe.
struct MixRule: Codable, Equatable {
    var source: MixSource = .library
    var artists: [String] = []
    var genres: [String] = []
    /// Décadas como año inicial: 1980 = los 80.
    var decades: [Int] = []

    /// Nombre corto para mostrar ("Metal · los 80", "Black Sabbath", "Toda la colección").
    var title: String {
        var parts: [String] = []
        if source != .library { parts.append(source.title) }
        if !artists.isEmpty { parts.append(Self.summarize(artists)) }
        if !genres.isEmpty { parts.append(Self.summarize(genres)) }
        if !decades.isEmpty { parts.append(Self.summarize(decades.sorted().map(MixRule.decadeLabel))) }
        return parts.isEmpty ? MixSource.library.title : parts.joined(separator: " · ")
    }

    static func decadeLabel(_ decade: Int) -> String {
        "los \(String(decade).suffix(2))"
    }

    private static func summarize(_ items: [String]) -> String {
        items.count <= 2 ? items.joined(separator: " y ") : "\(items[0]), \(items[1]) y \(items.count - 2) más"
    }

    /// ¿Calza la canción con los filtros (sin contar el origen)?
    func matchesFilters(_ track: Track) -> Bool {
        if !artists.isEmpty && !artists.contains(track.groupingArtist) && !artists.contains(track.artist) { return false }
        if !genres.isEmpty {
            guard let genre = track.genre?.trimmingCharacters(in: .whitespaces), genres.contains(genre) else { return false }
        }
        if !decades.isEmpty {
            guard let year = track.year, decades.contains(year / 10 * 10) else { return false }
        }
        return true
    }
}

/// Armado de mezclas y shuffle inteligente. Lógica pura, testeada.
enum MixBuilder {
    /// Largo de las mezclas: siempre se mantienen esta cantidad de canciones por delante.
    static let targetLength = 100
    /// Escuchadas en este período van al final de la mezcla.
    static let recentInterval: TimeInterval = 7 * 24 * 3600
    /// "Hace tiempo sin oír": más de 6 meses o nunca.
    static let forgottenInterval: TimeInterval = 182 * 24 * 3600

    static func isForgotten(_ track: Track, now: Date = Date()) -> Bool {
        guard let last = track.lastPlayedAt else { return true }
        return now.timeIntervalSince(last) > forgottenInterval
    }

    static func isRecent(_ track: Track, now: Date) -> Bool {
        guard let last = track.lastPlayedAt else { return false }
        return now.timeIntervalSince(last) <= recentInterval
    }

    /// Canciones que pueden entrar en la mezcla.
    static func candidates(for rule: MixRule, in tracks: [Track], favoriteIDs: Set<Int64>, now: Date = Date()) -> [Track] {
        tracks.filter { track in
            switch rule.source {
            case .library: break
            case .favorites: guard let id = track.id, favoriteIDs.contains(id) else { return false }
            case .forgotten: guard isForgotten(track, now: now) else { return false }
            }
            return rule.matchesFilters(track)
        }
    }

    /// Elige `count` canciones de `candidates` (sin las de `excluding`): primero las no escuchadas en la última
    /// semana, al final las recientes (de la menos a la más reciente), con los artistas y discos separados.
    static func build<R: RandomNumberGenerator>(from candidates: [Track],
                                                count: Int,
                                                excluding: Set<Int64> = [],
                                                previousArtist: String? = nil,
                                                now: Date = Date(),
                                                using rng: inout R) -> [Track] {
        guard count > 0 else { return [] }
        var seen = Set<Int64>()
        let pool = candidates.filter { track in
            guard let id = track.id, !excluding.contains(id) else { return false }
            return seen.insert(id).inserted
        }
        let fresh = pool.filter { !isRecent($0, now: now) }.shuffled(using: &rng)
        let recent = pool.filter { isRecent($0, now: now) }
            .sorted { ($0.lastPlayedAt ?? .distantPast) < ($1.lastPlayedAt ?? .distantPast) }

        let freshPart = spread(Array(fresh.prefix(count)), previousArtist: previousArtist)
        let remaining = count - freshPart.count
        let recentPart = remaining > 0
            ? spread(Array(recent.prefix(remaining)), previousArtist: freshPart.last?.groupingArtist ?? previousArtist)
            : []
        return freshPart + recentPart
    }

    static func build(from candidates: [Track], count: Int, excluding: Set<Int64> = [],
                      previousArtist: String? = nil, now: Date = Date()) -> [Track] {
        var rng = SystemRandomNumberGenerator()
        return build(from: candidates, count: count, excluding: excluding, previousArtist: previousArtist, now: now, using: &rng)
    }

    /// Reordena para que no queden seguidas canciones del mismo artista (mirando las últimas `window`)
    /// ni del mismo disco. Si no hay alternativa, prioriza cambiar de disco y, en último caso, acepta la repetición.
    static func spread(_ tracks: [Track], previousArtist: String? = nil, window: Int = 2, lookahead: Int = 60) -> [Track] {
        var remaining = tracks
        var result: [Track] = []
        result.reserveCapacity(tracks.count)
        var recentArtists: [String] = previousArtist.map { [$0] } ?? []

        while !remaining.isEmpty {
            let lastAlbum = result.last?.albumId
            let limit = min(remaining.count, lookahead)
            let blocked = recentArtists.suffix(window)
            func albumClash(_ candidate: Track) -> Bool { lastAlbum != nil && candidate.albumId == lastAlbum }
            // Primero: ni el artista ni el disco recién sonados. Si no hay (una mezcla casi de un solo artista),
            // al menos otro disco. Si tampoco, se acepta la repetición.
            let pick = (0..<limit).first { index in
                !blocked.contains(remaining[index].groupingArtist) && !albumClash(remaining[index])
            } ?? (0..<limit).first { !albumClash(remaining[$0]) } ?? 0
            let track = remaining.remove(at: pick)
            result.append(track)
            recentArtists.append(track.groupingArtist)
        }
        return result
    }

    /// Décadas presentes en la colección (para ofrecer en los filtros).
    static func decades(in tracks: [Track]) -> [Int] {
        Array(Set(tracks.compactMap { $0.year.map { $0 / 10 * 10 } }.filter { $0 >= 1900 })).sorted()
    }
}
