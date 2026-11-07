import XCTest
@testable import Octava

final class ListFilterTests: XCTestCase {
    private func track(_ title: String, artist: String, album: String) -> Track {
        Track(relativePath: title, fileModifiedAt: Date(timeIntervalSince1970: 0), title: title, artist: artist,
              album: album, duration: 180)
    }

    func testMatchesTitleArtistAlbumIgnoringCaseAndAccents() {
        let tracks = [
            track("Cornfield Chase", artist: "Hans Zimmer", album: "Interstellar"),
            track("Té Para Tres", artist: "Soda Stereo", album: "Canción Animal"),
            track("Dancing Queen", artist: "ABBA", album: "ABBA Gold"),
        ]
        XCTAssertEqual(ListFilter.apply(tracks, query: "zimmer").map(\.title), ["Cornfield Chase"])
        XCTAssertEqual(ListFilter.apply(tracks, query: "cancion").map(\.title), ["Té Para Tres"], "sin tildes")
        XCTAssertEqual(ListFilter.apply(tracks, query: "TE PARA").map(\.title), ["Té Para Tres"])
        XCTAssertEqual(ListFilter.apply(tracks, query: "abba queen").map(\.title), ["Dancing Queen"], "cada palabra en cualquier campo")
        XCTAssertEqual(ListFilter.apply(tracks, query: "  ").count, 3, "vacío = todo")
        XCTAssertTrue(ListFilter.apply(tracks, query: "metallica").isEmpty)
    }

    func testCountLabel() {
        XCTAssertEqual(ListFilter.countLabel(shown: 330, total: 330), "330 canciones")
        XCTAssertEqual(ListFilter.countLabel(shown: 8, total: 330), "8 de 330 canciones")
    }
}
