import XCTest
@testable import Octava

final class LastFMAPITests: XCTestCase {
    func testSignatureMatchesLastFMRules() {
        let parameters = ["token": "tok", "api_key": "abc", "method": "auth.getSession", "format": "json"]
        // md5("api_keyabcmethodauth.getSessiontokentok" + "secreto"); `format` no se firma.
        XCTAssertEqual(LastFMAPI.signature(for: parameters, secret: "secreto"), "0e64924f5c50a6dc6f100e5115bd9445")
    }

    func testSignedParametersWithUTF8() {
        let all = LastFMAPI.signedParameters(method: "track.love",
                                             parameters: ["artist": "Sui Generis", "track": "Canción para mi muerte"],
                                             apiKey: "abc", secret: "secreto", sessionKey: "S")
        XCTAssertEqual(all["api_sig"], "c70bacfd77b8bc6ebb14279faa2d4913")
        XCTAssertEqual(all["format"], "json")
        XCTAssertEqual(all["sk"], "S")
    }

    func testFormEncoding() {
        XCTAssertEqual(LastFMAPI.percentEncode("AC/DC & Ñandú"), "AC%2FDC%20%26%20%C3%91and%C3%BA")
        XCTAssertEqual(LastFMAPI.query(["b": "2", "a": "x y"]), "a=x%20y&b=2")
    }

    func testScrobbleBatchParameters() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let items = [
            ScrobbleItem(artist: "Soda Stereo", title: "De Música Ligera", album: "Canción Animal", albumArtist: nil,
                         trackNumber: 2, duration: 213.4, startedAt: date),
            ScrobbleItem(artist: "Los Prisioneros", title: "Tren al sur", album: nil, albumArtist: nil,
                         trackNumber: nil, duration: 0, startedAt: date.addingTimeInterval(300)),
        ]
        let parameters = LastFMAPI.scrobbleParameters(items)
        XCTAssertEqual(parameters["artist[0]"], "Soda Stereo")
        XCTAssertEqual(parameters["track[0]"], "De Música Ligera")
        XCTAssertEqual(parameters["timestamp[0]"], "1800000000")
        XCTAssertEqual(parameters["duration[0]"], "213")
        XCTAssertEqual(parameters["trackNumber[0]"], "2")
        XCTAssertEqual(parameters["timestamp[1]"], "1800000300")
        XCTAssertNil(parameters["album[1]"])
        XCTAssertNil(parameters["duration[1]"])

        let many = Array(repeating: items[0], count: 70)
        XCTAssertEqual(LastFMAPI.scrobbleParameters(many).keys.filter { $0.hasPrefix("artist[") }.count, 50)
    }

    func testNowPlayingHasNoTimestamp() {
        let item = ScrobbleItem(artist: "A", title: "T", album: "D", albumArtist: "B", trackNumber: 1, duration: 100, startedAt: Date())
        let parameters = LastFMAPI.nowPlayingParameters(item)
        XCTAssertNil(parameters["timestamp"])
        XCTAssertEqual(parameters["albumArtist"], "B")
    }

    func testParseErrorsAndAcceptedCount() throws {
        XCTAssertThrowsError(try LastFMAPI.parse(Data(#"{"error":9,"message":"Invalid session key"}"#.utf8))) { error in
            XCTAssertEqual((error as? LastFMError)?.code, 9)
            XCTAssertFalse((error as? LastFMError)?.isTemporary ?? true)
        }
        XCTAssertTrue(LastFMError(code: 16, message: "").isTemporary)
        XCTAssertTrue(LastFMError(code: nil, message: "red").isTemporary)

        let object = try LastFMAPI.parse(Data(#"{"scrobbles":{"@attr":{"accepted":2,"ignored":0},"scrobble":[]}}"#.utf8))
        XCTAssertEqual(LastFMAPI.acceptedCount(object), 2)
    }

    func testItemUsesPerformerAndAlbumArtist() {
        // Disco normal: Artist = Album Artist.
        var track = Track(relativePath: "a.mp3", fileModifiedAt: Date(), title: "T", artist: "Banda", album: "Disco", duration: 200)
        track.albumArtist = "Banda"
        var item = ScrobbleItem(track: track, startedAt: Date())
        XCTAssertEqual(item.artist, "Banda")
        XCTAssertNil(item.albumArtist)

        // Compilación de esta colección: Artist = "Various Artists", Album Artist = intérprete.
        track.artist = "Various Artists"
        track.albumArtist = "Clarence Carter"
        item = ScrobbleItem(track: track, startedAt: Date())
        XCTAssertEqual(item.artist, "Clarence Carter")
        XCTAssertEqual(item.albumArtist, "Various Artists")

        // Sin Album Artist: se usa Artist.
        track.artist = "Soda Stereo"
        track.albumArtist = nil
        XCTAssertEqual(ScrobbleItem(track: track, startedAt: Date()).artist, "Soda Stereo")
    }

    func testPerformerIgnoresGenericAlbumArtist() {
        var track = Track(relativePath: "a.mp3", fileModifiedAt: Date(), title: "T", artist: "Dream Theater", album: "D", duration: 1)
        track.albumArtist = "Various Artists"
        XCTAssertEqual(track.performer, "Dream Theater")
        XCTAssertEqual(track.groupingArtist, "Dream Theater")
    }
}

final class ScrobbleQueueTests: XCTestCase {
    private func item(_ title: String, minutesAgo: Double) -> ScrobbleItem {
        ScrobbleItem(artist: "A", title: title, album: "D", albumArtist: nil, trackNumber: 1, duration: 200,
                     startedAt: Date().addingTimeInterval(-minutesAgo * 60))
    }

    func testQueueOrderFailuresAndExpiry() throws {
        let database = try AppDatabase.makeEmpty()
        try database.enqueueScrobble(item("nueva", minutesAgo: 1))
        try database.enqueueScrobble(item("vieja", minutesAgo: 60))
        try database.enqueueScrobble(item("caducada", minutesAgo: 15 * 24 * 60))
        XCTAssertEqual(database.pendingScrobbleCount, 3)

        XCTAssertEqual(try database.dropScrobbles(olderThan: Date().addingTimeInterval(-LastFMAPI.maxScrobbleAge)), 1)
        let pending = database.pendingScrobbles(limit: 50)
        XCTAssertEqual(pending.map(\.item.title), ["vieja", "nueva"], "los más antiguos primero")
        XCTAssertEqual(pending.first?.item.trackNumber, 1)

        let first = try XCTUnwrap(pending.first?.id)
        try database.markScrobblesFailed([first], maxAttempts: 2)
        XCTAssertEqual(database.pendingScrobbleCount, 2)
        try database.markScrobblesFailed([first], maxAttempts: 2)
        XCTAssertEqual(database.pendingScrobbleCount, 1, "tras 2 fallos se descarta")

        try database.deleteScrobbles(database.pendingScrobbles(limit: 50).map(\.id))
        XCTAssertEqual(database.pendingScrobbleCount, 0)
    }
}

@MainActor
final class ScrobblerTrackingTests: XCTestCase {
    /// Ajustes aislados: nunca toca la cuenta real de la app.
    private func makeScrobbler() -> Scrobbler {
        let defaults = UserDefaults(suiteName: "octava-tests-\(UUID().uuidString)")!
        return Scrobbler(database: try! AppDatabase.makeEmpty(), client: LastFMClient(apiKey: "", secret: ""), defaults: defaults)
    }

    private func track() -> Track {
        Track(id: 1, relativePath: "a.mp3", fileModifiedAt: Date(), title: "T", artist: "A", album: "D", duration: 300)
    }

    func testThresholdMarksScrobbledWithoutQueueingWhenDisconnected() throws {
        let scrobbler = makeScrobbler()
        let entry = UUID()
        scrobbler.update(entryID: entry, track: track(), isPlaying: true, position: 0)
        XCTAssertFalse(scrobbler.currentScrobbled)
        scrobbler.update(entryID: entry, track: track(), isPlaying: true, position: 151) // mitad de 300 s
        XCTAssertTrue(scrobbler.currentScrobbled)
        XCTAssertEqual(scrobbler.pendingCount, 0, "sin cuenta conectada no se guarda nada")

        // Otra canción empieza de cero.
        scrobbler.update(entryID: UUID(), track: track(), isPlaying: true, position: 0)
        XCTAssertFalse(scrobbler.currentScrobbled)
    }

    func testResumedPastThresholdIsNotCountedAgain() throws {
        let scrobbler = makeScrobbler()
        scrobbler.update(entryID: UUID(), track: track(), isPlaying: false, position: 200)
        XCTAssertTrue(scrobbler.currentScrobbled)
    }
}
