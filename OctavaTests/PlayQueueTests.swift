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
        XCTAssertEqual(queue.upcoming.map(\.track.title), ["Pista 3"])
    }

    func testAdvanceUntilEndKeepsLast() {
        var queue = PlayQueue()
        queue.replace(with: [track(1), track(2)])
        XCTAssertEqual(queue.advance()?.title, "Pista 2")
        XCTAssertNil(queue.advance())
        XCTAssertEqual(queue.current?.title, "Pista 2")
    }

    func testGoBackStopsAtFirst() {
        var queue = PlayQueue()
        queue.replace(with: [track(1), track(2)], startAt: 1)
        XCTAssertTrue(queue.goBack())
        XCTAssertEqual(queue.current?.title, "Pista 1")
        XCTAssertFalse(queue.goBack())
        XCTAssertEqual(queue.current?.title, "Pista 1")
    }

    func testPlayNextInsertsAfterCurrent() {
        var queue = PlayQueue()
        queue.replace(with: [track(1), track(2), track(3)])
        queue.playNext([track(9)])
        XCTAssertEqual(queue.upcoming.map(\.track.title), ["Pista 9", "Pista 2", "Pista 3"])
    }

    func testRemoveBeforeCurrentKeepsCurrent() {
        var queue = PlayQueue()
        queue.replace(with: [track(1), track(2), track(3)], startAt: 2)
        queue.remove(entryID: queue.items[0].id)
        XCTAssertEqual(queue.current?.title, "Pista 3")
        XCTAssertEqual(queue.items.count, 2)
    }

    func testCannotRemoveCurrent() {
        var queue = PlayQueue()
        queue.replace(with: [track(1), track(2)])
        queue.remove(entryID: queue.items[0].id)
        XCTAssertEqual(queue.items.count, 2)
    }

    func testRepeatModes() {
        var queue = PlayQueue()
        queue.replace(with: [track(1), track(2)], startAt: 1)
        XCTAssertNil(queue.indexAfterCurrent(repeatMode: .off, automatic: true))
        XCTAssertEqual(queue.indexAfterCurrent(repeatMode: .all, automatic: true), 0)
        XCTAssertEqual(queue.indexAfterCurrent(repeatMode: .one, automatic: true), 1)
        // "Siguiente" manual con repetir una avanza a la próxima; al final de la cola no hay siguiente.
        XCTAssertNil(queue.indexAfterCurrent(repeatMode: .one, automatic: false))
        queue.select(0)
        XCTAssertEqual(queue.indexAfterCurrent(repeatMode: .one, automatic: false), 1)
    }

    func testRepeatModeCycle() {
        XCTAssertEqual(RepeatMode.off.next, .all)
        XCTAssertEqual(RepeatMode.all.next, .one)
        XCTAssertEqual(RepeatMode.one.next, .off)
    }

    func testRewind() {
        var queue = PlayQueue()
        queue.replace(with: [track(1), track(2)], startAt: 1)
        queue.rewind()
        XCTAssertEqual(queue.current?.title, "Pista 1")
    }

    func testPlayNextOnEmptyQueueStartsIt() {
        var queue = PlayQueue()
        queue.playNext([track(5), track(6)])
        XCTAssertEqual(queue.current?.title, "Pista 5")
        XCTAssertEqual(queue.upcoming.map(\.track.title), ["Pista 6"])
    }

    func testAppendOnEmptyQueueStartsIt() {
        var queue = PlayQueue()
        queue.append([track(7)])
        XCTAssertEqual(queue.current?.title, "Pista 7")
    }

    func testMoveUpcoming() {
        var queue = PlayQueue()
        queue.replace(with: [track(1), track(2), track(3), track(4)])
        // Mover "Pista 4" (offset 2 en upcoming) al principio de lo que viene.
        queue.moveUpcoming(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(queue.upcoming.map(\.track.title), ["Pista 4", "Pista 2", "Pista 3"])
        // Mover "Pista 4" al final (destino = count, como lo entrega SwiftUI).
        queue.moveUpcoming(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(queue.upcoming.map(\.track.title), ["Pista 2", "Pista 3", "Pista 4"])
        XCTAssertEqual(queue.current?.title, "Pista 1")
    }

    func testRemoveUpcomingOffsets() {
        var queue = PlayQueue()
        queue.replace(with: [track(1), track(2), track(3), track(4)], startAt: 1)
        queue.removeUpcoming(atOffsets: IndexSet([0, 1]))
        XCTAssertEqual(queue.items.map(\.track.title), ["Pista 1", "Pista 2"])
        XCTAssertEqual(queue.current?.title, "Pista 2")
    }

    func testSameTrackTwiceHasDistinctEntries() {
        var queue = PlayQueue()
        queue.replace(with: [track(1)])
        queue.append([track(1)])
        XCTAssertNotEqual(queue.items[0].id, queue.items[1].id)
    }

    func testClearUpcoming() {
        var queue = PlayQueue()
        queue.replace(with: [track(1), track(2), track(3)])
        queue.clearUpcoming()
        XCTAssertEqual(queue.items.count, 1)
        XCTAssertTrue(queue.upcoming.isEmpty)
        XCTAssertEqual(queue.current?.title, "Pista 1")
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

final class ReplayGainTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(ReplayGain.parse("-6.54 dB"), -6.54)
        XCTAssertEqual(ReplayGain.parse("+1.20 dB"), 1.2)
        XCTAssertEqual(ReplayGain.parse("2,5 db"), 2.5)
        XCTAssertNil(ReplayGain.parse("abc"))
        XCTAssertNil(ReplayGain.parse(nil))
    }

    func testModes() {
        XCTAssertEqual(ReplayGain.gain(trackGain: -7, albumGain: -5, mode: .off, source: .album), 0)
        XCTAssertEqual(ReplayGain.gain(trackGain: -7, albumGain: -5, mode: .track, source: .album), -7)
        XCTAssertEqual(ReplayGain.gain(trackGain: -7, albumGain: -5, mode: .album, source: .mix), -5)
        XCTAssertEqual(ReplayGain.gain(trackGain: -7, albumGain: -5, mode: .auto, source: .album), -5)
        XCTAssertEqual(ReplayGain.gain(trackGain: -7, albumGain: -5, mode: .auto, source: .mix), -7)
    }

    func testFallbacksAndLimits() {
        XCTAssertEqual(ReplayGain.gain(trackGain: nil, albumGain: -5, mode: .track, source: .mix), -5)
        XCTAssertEqual(ReplayGain.gain(trackGain: -3, albumGain: nil, mode: .album, source: .mix), -3)
        XCTAssertEqual(ReplayGain.gain(trackGain: nil, albumGain: nil, mode: .auto, source: .mix), 0)
        XCTAssertEqual(ReplayGain.gain(trackGain: 12, albumGain: nil, mode: .track, source: .mix), ReplayGain.maxBoost)
    }
}

final class ID3UserTextReaderTests: XCTestCase {
    private func synchsafe(_ value: Int) -> [UInt8] {
        [UInt8((value >> 21) & 0x7F), UInt8((value >> 14) & 0x7F), UInt8((value >> 7) & 0x7F), UInt8(value & 0x7F)]
    }

    private func bigEndian(_ value: Int) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private func txxx(encoding: UInt8, description: [UInt8], value: [UInt8], terminator: [UInt8]) -> [UInt8] {
        [encoding] + description + terminator + value
    }

    private func tag(major: UInt8, frames: [(String, [UInt8])], padding: Int = 16) -> [UInt8] {
        var body: [UInt8] = []
        for (id, content) in frames {
            body += Array(id.utf8)
            body += major == 4 ? synchsafe(content.count) : bigEndian(content.count)
            body += [0, 0]
            body += content
        }
        body += [UInt8](repeating: 0, count: padding)
        return [0x49, 0x44, 0x33, major, 0, 0] + synchsafe(body.count) + body
    }

    func testLatin1V23() {
        let content = txxx(encoding: 0, description: Array("replaygain_track_gain".utf8), value: Array("-6.54 dB".utf8), terminator: [0])
        let other = [UInt8(0)] + Array("Titulo".utf8)
        let result = ID3UserTextReader.parse(tag: tag(major: 3, frames: [("TIT2", other), ("TXXX", content)]))
        XCTAssertEqual(result["REPLAYGAIN_TRACK_GAIN"], "-6.54 dB")
    }

    func testUTF16WithBOM() {
        func utf16le(_ s: String) -> [UInt8] {
            [0xFF, 0xFE] + s.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        }
        let content = txxx(encoding: 1, description: utf16le("REPLAYGAIN_ALBUM_GAIN"), value: utf16le("-4.10 dB"), terminator: [0, 0])
        let result = ID3UserTextReader.parse(tag: tag(major: 3, frames: [("TXXX", content)]))
        XCTAssertEqual(result["REPLAYGAIN_ALBUM_GAIN"], "-4.10 dB")
    }

    func testUTF8V24() {
        let content = txxx(encoding: 3, description: Array("REPLAYGAIN_TRACK_GAIN".utf8), value: Array("+0.75 dB".utf8), terminator: [0])
        let result = ID3UserTextReader.parse(tag: tag(major: 4, frames: [("TXXX", content)]))
        XCTAssertEqual(result["REPLAYGAIN_TRACK_GAIN"], "+0.75 dB")
    }

    func testNotATag() {
        XCTAssertTrue(ID3UserTextReader.parse(tag: [0xFF, 0xFB, 0x90, 0x00, 0, 0, 0, 0, 0, 0]).isEmpty)
    }
}
