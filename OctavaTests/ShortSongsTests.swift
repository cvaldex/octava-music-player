import XCTest
@testable import Octava

final class ShortSongsTests: XCTestCase {
    private func track(_ path: String, duration: Double, added: Double?) -> Track {
        Track(id: Int64(path.hashValue & 0xFFFF), relativePath: path, fileModifiedAt: Date(timeIntervalSince1970: 0),
              title: path, artist: "A", album: "D", duration: duration,
              addedAt: added.map { Date(timeIntervalSince1970: $0) })
    }

    func testRuleAndOrder() {
        let library = [
            track("B/Disco/02.mp3", duration: 200, added: 100),
            track("B/Disco/01.mp3", duration: 180, added: 100),
            track("A/Nuevo/01.mp3", duration: 150, added: 500),
            track("A/Viejo/01.mp3", duration: 210.9, added: 10),
            track("A/Intro.mp3", duration: 30, added: 1),                 // 30 s justos: Last.fm no la cuenta
            track("A/Larga.mp3", duration: 211, added: 1),                // 211 s: fuera
            track("07 - Drumless Tracks/x.mp3", duration: 120, added: 1), // excluida
        ]
        let result = ShortSongs.tracks(in: library).map(\.relativePath)
        XCTAssertEqual(result, ["A/Viejo/01.mp3", "B/Disco/01.mp3", "B/Disco/02.mp3", "A/Nuevo/01.mp3"])
    }
}
