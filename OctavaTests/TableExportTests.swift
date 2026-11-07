import XCTest
@testable import Octava

final class TableExportTests: XCTestCase {
    private func track(title: String, artist: String, albumArtist: String?, album: String) -> Track {
        Track(relativePath: title, fileModifiedAt: Date(timeIntervalSince1970: 0), title: title, artist: artist,
              albumArtist: albumArtist, album: album, duration: 180)
    }

    func testArtistPrefersAlbumArtistAndTabsAreCleaned() {
        let tracks = [
            track(title: "Dancing Queen", artist: "Various Artists", albumArtist: "ABBA", album: "ABBA Gold"),
            track(title: "Uno\tDos", artist: "Soda Stereo", albumArtist: "  ", album: "Signos"),
        ]
        XCTAssertEqual(TableExport.tsv(tracks),
                       "Artista\tÁlbum\tTítulo\nABBA\tABBA Gold\tDancing Queen\nSoda Stereo\tSignos\tUno Dos\n")
    }
}
