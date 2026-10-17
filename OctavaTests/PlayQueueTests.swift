import XCTest
import GRDB
@testable import Octava

final class PlayQueueTests: XCTestCase {
    private func track(_ n: Int) -> Track {
        Track(id: Int64(n),
              relativePath: "Artista/Disco/\(n).mp3",
              fileModifiedAt: Date(timeIntervalSince1970: 0),
              title: "Pista \(n)",
              artist: "Artista",
              album: "Disco",
              trackNumber: n,
              duration: 180)
    }

    func testReplaceStartsAtRequestedIndex() {
        var queue = PlayQueue()
        queue.replace(with: [track(1), track(2), track(3)], startAt: 1)
        XCTAssertEqual(queue.current?.title, "Pista 2")
        XCTAssertEqual(queue.upcoming.map(\.title), ["Pista 3"])
    }

    func testAdvanceUntilEnd() {
        var queue = PlayQueue()
        queue.replace(with: [track(1), track(2)])
        XCTAssertEqual(queue.advance()?.title, "Pista 2")
        XCTAssertNil(queue.advance())
        XCTAssertNil(queue.current)
    }

    func testGoBackStopsAtFirst() {
        var queue = PlayQueue()
        queue.replace(with: [track(1), track(2)], startAt: 1)
        XCTAssertEqual(queue.goBack()?.title, "Pista 1")
        XCTAssertEqual(queue.goBack()?.title, "Pista 1")
    }

    func testPlayNextInsertsAfterCurrent() {
        var queue = PlayQueue()
        queue.replace(with: [track(1), track(2), track(3)])
        queue.playNext(track(9))
        XCTAssertEqual(queue.upcoming.map(\.title), ["Pista 9", "Pista 2", "Pista 3"])
    }

    func testRemoveBeforeCurrentKeepsCurrent() {
        var queue = PlayQueue()
        queue.replace(with: [track(1), track(2), track(3)], startAt: 2)
        queue.remove(at: 0)
        XCTAssertEqual(queue.current?.title, "Pista 3")
    }

    func testClearUpcoming() {
        var queue = PlayQueue()
        queue.replace(with: [track(1), track(2), track(3)])
        queue.clearUpcoming()
        XCTAssertEqual(queue.items.count, 1)
        XCTAssertTrue(queue.upcoming.isEmpty)
    }

    func testOutOfRangeStartFallsBackToFirst() {
        var queue = PlayQueue()
        queue.replace(with: [track(1)], startAt: 5)
        XCTAssertEqual(queue.current?.title, "Pista 1")
    }
}

final class ScrobbleRuleTests: XCTestCase {
    func testShortTracksNeverScrobble() {
        XCTAssertNil(scrobbleThreshold(forDuration: 30))
    }

    func testHalfOfShortTrack() {
        XCTAssertEqual(scrobbleThreshold(forDuration: 262), 131)
    }

    func testFourMinuteCap() {
        XCTAssertEqual(scrobbleThreshold(forDuration: 600), 240)
    }
}

final class TagParsingTests: XCTestCase {
    func testLeadingNumber() {
        XCTAssertEqual(TagReader.leadingNumber("3/11"), 3)
        XCTAssertEqual(TagReader.leadingNumber("07"), 7)
        XCTAssertNil(TagReader.leadingNumber("x"))
    }

    func testYear() {
        XCTAssertEqual(TagReader.year(from: "1998-05-01"), 1998)
        XCTAssertEqual(TagReader.year(from: "2004"), 2004)
        XCTAssertNil(TagReader.year(from: "98"))
    }

    func testGenre() {
        XCTAssertEqual(TagReader.cleanGenre("(17)Rock"), "Rock")
        XCTAssertNil(TagReader.cleanGenre("(17)"))
        XCTAssertEqual(TagReader.cleanGenre("Jazz"), "Jazz")
    }

    func testRelativePath() {
        XCTAssertEqual(LibraryScanner.relativePath(of: URL(fileURLWithPath: "/Musica/A/B/1.mp3"), rootPath: "/Musica"), "A/B/1.mp3")
    }
}

final class DatabaseTests: XCTestCase {
    func testMigrationAndInsert() throws {
        let database = try AppDatabase.makeEmpty()
        try database.writer.write { db in
            var album = Album(title: "Disco", albumArtist: "Artista", year: 1998, folderPath: "Artista/Disco")
            try album.insert(db)
            var track = Track(relativePath: "Artista/Disco/1.mp3",
                              fileModifiedAt: Date(),
                              title: "Uno",
                              artist: "Artista",
                              album: "Disco",
                              duration: 200,
                              albumId: album.id)
            try track.insert(db)
            XCTAssertNotNil(track.id)
            XCTAssertEqual(try Track.fetchCount(db), 1)
        }
    }
}
