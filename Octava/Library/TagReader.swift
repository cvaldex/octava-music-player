import AVFoundation

/// Tags leídos de un MP3.
struct TrackTags: Sendable {
    var title: String?
    var artist: String?
    var albumArtist: String?
    var album: String?
    var trackNumber: Int?
    var discNumber: Int?
    var year: Int?
    var genre: String?
    var duration: Double = 0
    var artwork: Data?
    var replayGainTrack: Double?
    var replayGainAlbum: Double?
    /// kbps (promedio estimado; en archivos VBR varía entre canciones).
    var bitrate: Int?
}

/// Lectura de tags ID3 con AVFoundation. La escritura la hace `ID3TagWriter` (AVFoundation no escribe tags MP3).
enum TagReader {
    static func read(url: URL) async throws -> TrackTags {
        let asset = AVURLAsset(url: url)
        let (duration, items) = try await asset.load(.duration, .metadata)

        var tags = TrackTags()
        tags.duration = duration.seconds.isFinite ? duration.seconds : 0

        func string(_ identifiers: AVMetadataIdentifier...) async -> String? {
            for identifier in identifiers {
                guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier).first else { continue }
                if let value = try? await item.load(.stringValue) {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
            return nil
        }

        tags.title = await string(.id3MetadataTitleDescription, .commonIdentifierTitle)
        tags.artist = await string(.id3MetadataLeadPerformer, .commonIdentifierArtist)
        tags.albumArtist = await string(.id3MetadataBand)
        tags.album = await string(.id3MetadataAlbumTitle, .commonIdentifierAlbumName)
        tags.trackNumber = leadingNumber(await string(.id3MetadataTrackNumber))
        tags.discNumber = leadingNumber(await string(.id3MetadataPartOfASet))
        tags.year = year(from: await string(.id3MetadataRecordingTime, .id3MetadataYear, .id3MetadataReleaseTime))
        tags.genre = cleanGenre(await string(.id3MetadataContentType))

        if let pictureItem = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .id3MetadataAttachedPicture).first
            ?? AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierArtwork).first {
            tags.artwork = try? await pictureItem.load(.dataValue)
        }

        // ID3v2.2: AVFoundation entrega título, artista y álbum, pero no pista, disco, año, artista del álbum
        // ni género. Se completan con el lector propio (el mismo que usa el editor de tags).
        if ID3TagWriter.tagVersion(ofFileAt: url) == 2, let tag = ID3TagWriter.readTag(fromFileAt: url) {
            func value(_ field: TagField) -> String? {
                guard let text = tag.text(for: field), !text.isEmpty else { return nil }
                return text
            }
            tags.title = tags.title ?? value(.title)
            tags.artist = tags.artist ?? value(.artist)
            tags.albumArtist = tags.albumArtist ?? value(.albumArtist)
            tags.album = tags.album ?? value(.album)
            tags.trackNumber = tags.trackNumber ?? leadingNumber(value(.trackNumber))
            tags.discNumber = tags.discNumber ?? leadingNumber(value(.discNumber))
            tags.year = tags.year ?? year(from: value(.year))
            tags.genre = tags.genre ?? cleanGenre(value(.genre))
            if tags.artwork == nil, let cover = tag.frontCover(), !cover.data.isEmpty {
                tags.artwork = cover.data
            }
        }

        let userText = ID3UserTextReader.read(url: url)
        tags.replayGainTrack = ReplayGain.parse(userText["REPLAYGAIN_TRACK_GAIN"])
        tags.replayGainAlbum = ReplayGain.parse(userText["REPLAYGAIN_ALBUM_GAIN"])

        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
           let rate = try? await audioTrack.load(.estimatedDataRate), rate > 0 {
            tags.bitrate = Int((Double(rate) / 1000).rounded())
        }
        return tags
    }

    /// "3/11" → 3
    static func leadingNumber(_ text: String?) -> Int? {
        guard let text else { return nil }
        let digits = text.prefix { $0.isNumber }
        return Int(digits)
    }

    /// "1998-05-01" o "1998" → 1998
    static func year(from text: String?) -> Int? {
        guard let text else { return nil }
        let digits = text.prefix(4)
        guard digits.count == 4, let value = Int(digits), value > 1000 else { return nil }
        return value
    }

    /// Normaliza el género. Algunos programas guardan el código numérico de ID3v1 en vez del nombre:
    /// "17", "(17)" → "Rock"; "(17)Rock" → "Rock" (se prefiere el texto si viene).
    static func cleanGenre(_ text: String?) -> String? {
        guard var text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if text.hasPrefix("("), let close = text.firstIndex(of: ")") {
            let code = String(text[text.index(after: text.startIndex)..<close])
            let rest = text[text.index(after: close)...].trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { return rest }
            text = code
        }
        if text.allSatisfy(\.isNumber), let code = Int(text) {
            return id3v1Genres.indices.contains(code) ? id3v1Genres[code] : nil
        }
        return text
    }

    /// Lista estándar de géneros de ID3v1 (0–79) con las extensiones de Winamp (80–147).
    static let id3v1Genres: [String] = [
        "Blues", "Classic Rock", "Country", "Dance", "Disco", "Funk", "Grunge", "Hip-Hop", "Jazz", "Metal",
        "New Age", "Oldies", "Other", "Pop", "R&B", "Rap", "Reggae", "Rock", "Techno", "Industrial",
        "Alternative", "Ska", "Death Metal", "Pranks", "Soundtrack", "Euro-Techno", "Ambient", "Trip-Hop", "Vocal", "Jazz+Funk",
        "Fusion", "Trance", "Classical", "Instrumental", "Acid", "House", "Game", "Sound Clip", "Gospel", "Noise",
        "Alternative Rock", "Bass", "Soul", "Punk", "Space", "Meditative", "Instrumental Pop", "Instrumental Rock", "Ethnic", "Gothic",
        "Darkwave", "Techno-Industrial", "Electronic", "Pop-Folk", "Eurodance", "Dream", "Southern Rock", "Comedy", "Cult", "Gangsta",
        "Top 40", "Christian Rap", "Pop/Funk", "Jungle", "Native American", "Cabaret", "New Wave", "Psychedelic", "Rave", "Showtunes",
        "Trailer", "Lo-Fi", "Tribal", "Acid Punk", "Acid Jazz", "Polka", "Retro", "Musical", "Rock & Roll", "Hard Rock",
        "Folk", "Folk-Rock", "National Folk", "Swing", "Fast Fusion", "Bebop", "Latin", "Revival", "Celtic", "Bluegrass",
        "Avantgarde", "Gothic Rock", "Progressive Rock", "Psychedelic Rock", "Symphonic Rock", "Slow Rock", "Big Band", "Chorus", "Easy Listening", "Acoustic",
        "Humour", "Speech", "Chanson", "Opera", "Chamber Music", "Sonata", "Symphony", "Booty Bass", "Primus", "Porn Groove",
        "Satire", "Slow Jam", "Club", "Tango", "Samba", "Folklore", "Ballad", "Power Ballad", "Rhythmic Soul", "Freestyle",
        "Duet", "Punk Rock", "Drum Solo", "A Cappella", "Euro-House", "Dance Hall", "Goa", "Drum & Bass", "Club-House", "Hardcore Techno",
        "Terror", "Indie", "BritPop", "Afro-Punk", "Polsk Punk", "Beat", "Christian Gangsta Rap", "Heavy Metal", "Black Metal", "Crossover",
        "Contemporary Christian", "Christian Rock", "Merengue", "Salsa", "Thrash Metal", "Anime", "J-Pop", "Synthpop"
    ]
}
