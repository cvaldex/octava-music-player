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
}

/// Lectura de tags ID3 con AVFoundation (solo lectura; la escritura llega en la fase 4 con ID3TagEditor).
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

        let userText = ID3UserTextReader.read(url: url)
        tags.replayGainTrack = ReplayGain.parse(userText["REPLAYGAIN_TRACK_GAIN"])
        tags.replayGainAlbum = ReplayGain.parse(userText["REPLAYGAIN_ALBUM_GAIN"])

        // TODO fase 1: bitrate (AVAssetTrack.estimatedDataRate).
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

    /// ID3v1 guarda a veces el género como "(17)"; se deja el texto si viene, y se descarta el código numérico solo.
    static func cleanGenre(_ text: String?) -> String? {
        guard var text else { return nil }
        if text.hasPrefix("("), let close = text.firstIndex(of: ")") {
            let rest = text[text.index(after: close)...].trimmingCharacters(in: .whitespaces)
            text = rest
        }
        return text.isEmpty ? nil : text
    }
}
