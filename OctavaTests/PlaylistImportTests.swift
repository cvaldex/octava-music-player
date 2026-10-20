import XCTest
@testable import Octava

final class PlaylistImportTests: XCTestCase {
    private func track(_ id: Int64, _ path: String, title: String, artist: String) -> Track {
        Track(id: id, relativePath: path, fileModifiedAt: Date(timeIntervalSince1970: 0),
              title: title, artist: artist, album: "Disco", duration: 180)
    }

    private lazy var library: [Track] = [
        track(1, "06 - Musica Cine/John Williams/CD 1/01 - Star Wars Main Title.mp3", title: "Star Wars Main Title", artist: "John Williams"),
        track(2, "06 - Musica Cine/John Williams/CD 1/02 - E.T. Flying Theme.mp3", title: "E.T. Flying Theme", artist: "John Williams"),
        // Tilde en forma descompuesta, como la guarda macOS.
        track(3, "Soda Stereo/1990 - Cancio\u{301}n Animal/01 - Te Para Tres.mp3", title: "Té Para Tres", artist: "Soda Stereo"),
    ]

    private let folder = URL(fileURLWithPath: "/Users/yo/02 - Musica")

    func testXSPFKeepsOrderAndMatchesByPath() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <playlist version="1" xmlns="http://xspf.org/ns/0/">
          <title>Cine</title>
          <trackList>
            <track>
              <location>/Users/yo/02 - Musica/06 - Musica Cine/John Williams/CD 1/02 - E.T. Flying Theme.mp3</location>
              <title>E.T. Flying Theme</title><creator>John Williams</creator>
            </track>
            <track>
              <location>file:///Users/yo/02%20-%20Musica/06%20-%20Musica%20Cine/John%20Williams/CD%201/01%20-%20Star%20Wars%20Main%20Title.mp3</location>
              <title>Star Wars Main Title</title>
            </track>
            <track>
              <location>/Users/yo/02 - Musica/Soda Stereo/1990 - Canción Animal/01 - Te Para Tres.mp3</location>
            </track>
            <track><location>/Users/yo/02 - Musica/No existe.mp3</location><title>Nada</title></track>
          </trackList>
        </playlist>
        """
        let parsed = PlaylistImport.parse(data: Data(xml.utf8), fileExtension: "xspf")
        XCTAssertEqual(parsed.title, "Cine")
        XCTAssertEqual(parsed.entries.count, 4)
        XCTAssertNil(parsed.entries[2].title, "el <title> de la lista no se confunde con el de una pista")

        let match = PlaylistImport.match(parsed.entries, tracks: library, musicFolder: folder, playlistFolder: nil)
        XCTAssertEqual(match.trackIDs, [2, 1, 3])
        XCTAssertEqual(match.missing.map(\.title), ["Nada"])
    }

    func testM3UFromAnotherComputerMatchesByPathTailAndTitle() {
        let m3u = """
        #EXTM3U
        #PLAYLIST:Viaje
        #EXTINF:220,John Williams - E.T. Flying Theme
        D:\\Musica\\Otra\\John Williams\\CD 1\\02 - E.T. Flying Theme.mp3
        #EXTINF:300,Soda Stereo - Té Para Tres
        /Volumes/Otro/renombrado.mp3
        http://radio.example.com/stream
        """
        let parsed = PlaylistImport.parse(data: Data(m3u.utf8), fileExtension: "m3u8")
        XCTAssertEqual(parsed.title, "Viaje")
        XCTAssertEqual(parsed.entries.count, 3)

        let match = PlaylistImport.match(parsed.entries, tracks: library, musicFolder: folder, playlistFolder: nil)
        XCTAssertEqual(match.trackIDs, [2, 3], "por el final de la ruta y por título + artista")
        XCTAssertEqual(match.missing.count, 1, "la radio no se importa")
    }

    func testRelativeM3UPaths() {
        let m3u = "CD 1/01 - Star Wars Main Title.mp3\n"
        let playlistFolder = URL(fileURLWithPath: "/Users/yo/02 - Musica/06 - Musica Cine/John Williams")
        let parsed = PlaylistImport.parse(data: Data(m3u.utf8), fileExtension: "m3u")
        let match = PlaylistImport.match(parsed.entries, tracks: library, musicFolder: folder, playlistFolder: playlistFolder)
        XCTAssertEqual(match.trackIDs, [1])
    }
}
