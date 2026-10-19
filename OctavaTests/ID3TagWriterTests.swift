import XCTest
import GRDB
@testable import Octava

/// Pruebas del escritor de tags con MP3 generados (silencio): nunca se toca la colección del usuario.
final class ID3TagWriterTests: XCTestCase {

    // MARK: Construcción de archivos de prueba

    /// Audio MPEG-1 Layer III, 128 kbps, 44,1 kHz: tramas de silencio de 417 bytes.
    private func audio(frames: Int = 120) -> [UInt8] {
        var bytes: [UInt8] = []
        for _ in 0..<frames {
            bytes += [0xFF, 0xFB, 0x90, 0x64] + [UInt8](repeating: 0, count: 413)
        }
        return bytes
    }

    private func synchsafe(_ value: Int) -> [UInt8] {
        [UInt8((value >> 21) & 0x7F), UInt8((value >> 14) & 0x7F), UInt8((value >> 7) & 0x7F), UInt8(value & 0x7F)]
    }

    private func bigEndian(_ value: Int) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private func frame(_ id: String, _ content: [UInt8], major: UInt8, plainSize: Bool = false) -> [UInt8] {
        Array(id.utf8) + ((major == 4 && !plainSize) ? synchsafe(content.count) : bigEndian(content.count)) + [0, 0] + content
    }

    private func latin1(_ text: String) -> [UInt8] { [0x00] + [UInt8](text.data(using: .isoLatin1)!) }
    private func utf8(_ text: String) -> [UInt8] { [0x03] + Array(text.utf8) }

    private func txxx(_ description: String, _ value: String) -> [UInt8] {
        [0x00] + Array(description.utf8) + [0x00] + Array(value.utf8)
    }

    private func apic(type: UInt8, data: [UInt8]) -> [UInt8] {
        [0x00] + Array("image/jpeg".utf8) + [0x00, type, 0x00] + data
    }

    private func tag(major: UInt8, frames: [[UInt8]], padding: Int = 64, flags: UInt8 = 0) -> [UInt8] {
        let body = frames.flatMap { $0 } + [UInt8](repeating: 0, count: padding)
        return [0x49, 0x44, 0x33, major, 0, flags] + synchsafe(body.count) + body
    }

    private func id3v1(title: String, track: UInt8, genre: UInt8) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 128)
        bytes[0] = 0x54; bytes[1] = 0x41; bytes[2] = 0x47
        for (i, b) in Array(title.utf8).prefix(30).enumerated() { bytes[3 + i] = b }
        bytes[126] = track
        bytes[127] = genre
        return bytes
    }

    private let comment: [UInt8] = [0x00, 0x65, 0x6E, 0x67, 0x00] + Array("Grabado en vivo".utf8)
    private let backCover: [UInt8] = [0xAA, 0xBB, 0xCC]
    private let frontCover: [UInt8] = [0x11, 0x22, 0x33, 0x44]

    private func sampleV23() -> [UInt8] {
        tag(major: 3, frames: [
            frame("TIT2", latin1("Viejo título"), major: 3),
            frame("TPE1", latin1("Artista"), major: 3),
            frame("TALB", latin1("Disco"), major: 3),
            frame("TRCK", latin1("3/12"), major: 3),
            frame("TYER", latin1("1998"), major: 3),
            frame("TXXX", txxx("REPLAYGAIN_TRACK_GAIN", "-6.54 dB"), major: 3),
            frame("COMM", comment, major: 3),
            frame("APIC", apic(type: 4, data: backCover), major: 3),
            frame("APIC", apic(type: 3, data: frontCover), major: 3),
        ]) + audio()
    }

    private func tagBytes(_ file: Data) -> [UInt8] {
        let bytes = [UInt8](file)
        let size = ID3TagWriter.synchsafe(bytes[6], bytes[7], bytes[8], bytes[9])
        return Array(bytes[0..<(10 + size)])
    }

    // MARK: Pruebas

    func testV23ChangesOnlyEditedFieldsAndKeepsEverythingElse() throws {
        let original = sampleV23()
        var changes = TagChanges()
        changes.text = [.title: "Canción ñandú 日本", .trackNumber: "5", .genre: "Rock"]
        let result = try ID3TagWriter.apply(changes, to: Data(original))

        let text = try ID3TagWriter.readText(from: result)
        XCTAssertEqual(text[.title], "Canción ñandú 日本")
        XCTAssertEqual(text[.trackNumber], "5/12", "se conserva el total de pistas")
        XCTAssertEqual(text[.genre], "Rock")
        XCTAssertEqual(text[.artist], "Artista")
        XCTAssertEqual(text[.year], "1998")
        XCTAssertEqual(result[3], 3, "se conserva la versión v2.3")

        // ReplayGain, comentario y contraportada intactos.
        let tag = tagBytes(result)
        XCTAssertEqual(ID3UserTextReader.parse(tag: tag)["REPLAYGAIN_TRACK_GAIN"], "-6.54 dB")
        XCTAssertNotNil(tag.firstRange(of: frame("COMM", comment, major: 3)))
        XCTAssertNotNil(tag.firstRange(of: frame("APIC", apic(type: 4, data: backCover), major: 3)))

        // Audio idéntico byte a byte.
        XCTAssertEqual(Array(result.suffix(audio().count)), audio())
    }

    func testV24WritesUTF8AndRecordingTime() throws {
        let original = tag(major: 4, frames: [
            frame("TIT2", utf8("Título"), major: 4),
            frame("TYER", latin1("1990"), major: 4),
        ]) + audio()
        let result = try ID3TagWriter.apply(TagChanges(text: [.year: "1984"]), to: Data(original))
        let located = try ID3TagWriter.locateTag(in: [UInt8](result))
        let ids = located.tag?.frames.map(\.id) ?? []
        XCTAssertTrue(ids.contains("TDRC"))
        XCTAssertFalse(ids.contains("TYER"), "no deben quedar dos años distintos")
        XCTAssertEqual(try ID3TagWriter.readText(from: result)[.year], "1984")
        XCTAssertEqual(try ID3TagWriter.readText(from: result)[.title], "Título")
    }

    func testFileWithoutTagGetsV24() throws {
        let result = try ID3TagWriter.apply(TagChanges(text: [.album: "Nuevo"]), to: Data(audio()))
        XCTAssertEqual(Array(result.prefix(4)), [0x49, 0x44, 0x33, 4])
        XCTAssertEqual(try ID3TagWriter.readText(from: result)[.album], "Nuevo")
        XCTAssertEqual(Array(result.suffix(audio().count)), audio())
    }

    func testEmptyValueRemovesField() throws {
        let result = try ID3TagWriter.apply(TagChanges(text: [.year: ""]), to: Data(sampleV23()))
        XCTAssertNil(try ID3TagWriter.readText(from: result)[.year])
    }

    func testArtworkReplacesFrontCoverAndKeepsBackCover() throws {
        var changes = TagChanges()
        changes.artwork = TagChanges.Artwork(data: Data([0x99, 0x98]), mimeType: "image/png")
        let result = try ID3TagWriter.apply(changes, to: Data(sampleV23()))
        let tag = try XCTUnwrap(ID3TagWriter.locateTag(in: [UInt8](result)).tag)
        XCTAssertEqual(tag.frontCover(), TagChanges.Artwork(data: Data([0x99, 0x98]), mimeType: "image/png"))
        XCTAssertEqual(tag.frames.filter { $0.id == "APIC" }.count, 2, "portada nueva + contraportada")

        changes.artwork = TagChanges.Artwork(data: Data(), mimeType: "")
        let removed = try ID3TagWriter.apply(changes, to: result)
        let removedTag = try XCTUnwrap(ID3TagWriter.locateTag(in: [UInt8](removed)).tag)
        XCTAssertEqual(removedTag.frames.filter { $0.id == "APIC" }.count, 1)
    }

    func testPreviousValuesUndoRestoresOriginal() throws {
        let original = Data(sampleV23())
        var changes = TagChanges(text: [.title: "Otro", .album: "Otro disco", .albumArtist: "Nuevo artista"])
        changes.artwork = TagChanges.Artwork(data: Data([1, 2, 3]), mimeType: "image/jpeg")
        let previous = try ID3TagWriter.previousValues(for: changes, in: original)
        XCTAssertEqual(previous.text[.albumArtist], "", "no existía: deshacer lo borra")
        XCTAssertEqual(previous.artwork?.data, Data(frontCover))

        let edited = try ID3TagWriter.apply(changes, to: original)
        let undone = try ID3TagWriter.apply(previous, to: edited)
        XCTAssertEqual(try ID3TagWriter.readText(from: undone), try ID3TagWriter.readText(from: original))
        XCTAssertEqual(try ID3TagWriter.locateTag(in: [UInt8](undone)).tag?.frontCover()?.data, Data(frontCover))
    }

    func testID3v1IsUpdated() throws {
        let original = sampleV23() + id3v1(title: "Viejo", track: 3, genre: 9)
        let result = [UInt8](try ID3TagWriter.apply(TagChanges(text: [.title: "Nuevo título", .trackNumber: "7", .genre: "Rock"]),
                                                    to: Data(original)))
        let v1 = Array(result.suffix(128))
        XCTAssertEqual(String(bytes: v1[3..<15], encoding: .isoLatin1), "Nuevo título")
        XCTAssertEqual(v1[126], 7)
        XCTAssertEqual(v1[127], 17, "Rock es el género 17 de ID3v1")
    }

    func testRejectsUnsupportedAndDamagedTags() {
        let v22 = [0x49, 0x44, 0x33, 2, 0, 0] + synchsafe(10) + [UInt8](repeating: 0, count: 10) + audio(frames: 2)
        XCTAssertThrowsError(try ID3TagWriter.apply(TagChanges(text: [.title: "x"]), to: Data(v22)))

        // Un frame que dice medir más de lo que hay: dañado, no se toca.
        let damaged = [0x49, 0x44, 0x33, 3, 0, 0] + synchsafe(20) + Array("TIT2".utf8) + bigEndian(500) + [0, 0]
            + [UInt8](repeating: 0x41, count: 6) + audio(frames: 2)
        XCTAssertThrowsError(try ID3TagWriter.apply(TagChanges(text: [.title: "x"]), to: Data(damaged)))
    }

    func testV24WithPlainFrameSizes() throws {
        // iTunes antiguo: tamaños de frame v2.4 sin "synchsafe" (200 = 0xC8 no es un byte válido de synchsafe).
        let longTitle = String(repeating: "a", count: 199)
        let original = tag(major: 4, frames: [
            frame("TIT2", utf8(longTitle), major: 4, plainSize: true),
            frame("TALB", utf8("Disco"), major: 4),
        ]) + audio()
        let result = try ID3TagWriter.apply(TagChanges(text: [.genre: "Jazz"]), to: Data(original))
        let text = try ID3TagWriter.readText(from: result)
        XCTAssertEqual(text[.title], longTitle)
        XCTAssertEqual(text[.album], "Disco")
    }

    func testUnsynchronizedV23Tag() throws {
        // Desincronización: un FF seguido de 00 insertado.
        let content = latin1("Ã") // 0xC3
        let unsyncedFrame = Array("TIT2".utf8) + bigEndian(content.count) + [0, 0] + content
        let body = Array("TPE1".utf8) + bigEndian(3) + [0, 0] + [0x00, 0xFF, 0x00] + unsyncedFrame + [UInt8](repeating: 0, count: 8)
        // El byte FF00 dentro de TPE1 representa un FF real de 1 byte → el frame real mide 2 bytes; se ajusta el tamaño.
        var adjusted = body
        adjusted[7] = 2
        let original = [0x49, 0x44, 0x33, 3, 0, 0x80] + synchsafe(adjusted.count) + adjusted + audio()
        let result = try ID3TagWriter.apply(TagChanges(text: [.album: "Disco"]), to: Data(original))
        XCTAssertEqual(result[5], 0, "se escribe sin desincronización")
        XCTAssertEqual(try ID3TagWriter.readText(from: result)[.title], "Ã")
        XCTAssertEqual(try ID3TagWriter.readText(from: result)[.album], "Disco")
    }

    /// Escritura real en disco (carpeta temporal) y lectura con AVFoundation, como hace el escáner.
    func testWriteToFileAndReadBackWithAVFoundation() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("octava-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("prueba.mp3")
        try Data(sampleV23() + audio(frames: 300)).write(to: url)

        var changes = TagChanges(text: [.title: "Título nuevo", .album: "Álbum nuevo", .albumArtist: "Banda",
                                        .year: "2001", .genre: "Heavy Metal", .discNumber: "2"])
        changes.artwork = TagChanges.Artwork(data: Data([0xFF, 0xD8, 0xFF]), mimeType: "image/jpeg")
        let previous = try ID3TagWriter.apply(changes, toFileAt: url)
        XCTAssertEqual(previous.text[.title], "Viejo título")

        let tags = try await TagReader.read(url: url)
        XCTAssertEqual(tags.title, "Título nuevo")
        XCTAssertEqual(tags.album, "Álbum nuevo")
        XCTAssertEqual(tags.albumArtist, "Banda")
        XCTAssertEqual(tags.artist, "Artista")
        XCTAssertEqual(tags.year, 2001)
        XCTAssertEqual(tags.genre, "Heavy Metal")
        XCTAssertEqual(tags.trackNumber, 3)
        XCTAssertEqual(tags.discNumber, 2)
        XCTAssertEqual(tags.replayGainTrack, -6.54)
        XCTAssertGreaterThan(tags.duration, 1)

        // No quedan temporales en la carpeta.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(leftovers, ["prueba.mp3"])
    }
}

/// Flujo completo sobre una carpeta temporal: escanear, editar el disco, releer y deshacer.
/// Comprueba que se conservan las estadísticas y que los discos se reagrupan.
final class TagEditFlowTests: XCTestCase {
    private func silentAudio(frames: Int = 200) -> [UInt8] {
        var bytes: [UInt8] = []
        for _ in 0..<frames { bytes += [0xFF, 0xFB, 0x90, 0x64] + [UInt8](repeating: 0, count: 413) }
        return bytes
    }

    func testEditAlbumRereadAndUndoKeepsStatistics() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("octava-flow-\(UUID().uuidString)")
        let albumFolder = root.appendingPathComponent("Banda/Disco")
        try FileManager.default.createDirectory(at: albumFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Dos canciones con tags v2.4 iniciales.
        for n in 1...2 {
            let initial = try ID3TagWriter.apply(TagChanges(text: [.title: "Canción \(n)", .artist: "Banda", .album: "Disco",
                                                                   .trackNumber: "\(n)", .year: "1990"]),
                                                 to: Data(silentAudio()))
            try initial.write(to: albumFolder.appendingPathComponent("\(n).mp3"))
        }

        let database = try AppDatabase.makeEmpty()
        let scanner = LibraryScanner(database: database)
        _ = try await scanner.scan(root: root) { _ in }

        var tracks = try await database.writer.read { db in try Track.order(Column("relativePath")).fetchAll(db) }
        XCTAssertEqual(tracks.count, 2)
        XCTAssertEqual(tracks.map(\.album), ["Disco", "Disco"])
        let originalAlbumID = try XCTUnwrap(tracks.first?.albumId)

        // Estadísticas que no se deben perder.
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE track SET playCount = 7, isFavorite = 1 WHERE relativePath = 'Banda/Disco/1.mp3'")
        }

        // Editar el disco completo (como el editor por lote) y registrar el historial.
        let changes = TagChanges(text: [.album: "Disco (Remaster)", .year: "1991"])
        var edits: [(trackId: Int64, previous: TagChanges)] = []
        for track in tracks {
            let previous = try ID3TagWriter.apply(changes, toFileAt: root.appendingPathComponent(track.relativePath))
            edits.append((try XCTUnwrap(track.id), previous))
        }
        try database.recordTagEdits(edits, at: Date())
        try database.markForReread(trackIDs: edits.map(\.trackId), clearingCovers: false)
        _ = try await scanner.scan(root: root) { _ in }

        tracks = try await database.writer.read { db in try Track.order(Column("relativePath")).fetchAll(db) }
        XCTAssertEqual(tracks.map(\.album), ["Disco (Remaster)", "Disco (Remaster)"])
        XCTAssertEqual(tracks.map(\.year), [1991, 1991])
        XCTAssertEqual(tracks.first?.playCount, 7)
        XCTAssertEqual(tracks.first?.isFavorite, true)
        let albums = try await database.writer.read { db in try Album.fetchAll(db) }
        XCTAssertEqual(albums.map(\.title), ["Disco (Remaster)"], "el disco viejo vacío se elimina")
        XCTAssertEqual(albums.first?.year, 1991)
        XCTAssertNotEqual(albums.first?.id, originalAlbumID)

        // Deshacer el último lote.
        let batch = database.latestTagEditBatch()
        XCTAssertEqual(batch.count, 2)
        XCTAssertTrue(database.hasTagEdits)
        for record in batch {
            let track = try XCTUnwrap(tracks.first { $0.id == record.trackId })
            try ID3TagWriter.apply(record.previous, toFileAt: root.appendingPathComponent(track.relativePath))
        }
        try database.deleteTagEdits(batch.map(\.id))
        try database.markForReread(trackIDs: batch.map(\.trackId), clearingCovers: false)
        _ = try await scanner.scan(root: root) { _ in }

        tracks = try await database.writer.read { db in try Track.order(Column("relativePath")).fetchAll(db) }
        XCTAssertEqual(tracks.map(\.album), ["Disco", "Disco"])
        XCTAssertEqual(tracks.map(\.year), [1990, 1990])
        XCTAssertEqual(tracks.first?.playCount, 7)
        XCTAssertFalse(database.hasTagEdits)
    }
}

/// Escáner ante carpetas desconectadas, borrados masivos y archivos movidos (sobre carpetas temporales).
final class ScannerResilienceTests: XCTestCase {
    private func makeFile(_ url: URL, title: String, album: String = "Disco", frames: Int = 200) throws {
        var audio: [UInt8] = []
        for _ in 0..<frames { audio += [0xFF, 0xFB, 0x90, 0x64] + [UInt8](repeating: 0, count: 413) }
        let data = try ID3TagWriter.apply(TagChanges(text: [.title: title, .artist: "Banda", .album: album]), to: Data(audio))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("octava-scan-\(UUID().uuidString)")
    }

    func testMissingFolderKeepsLibrary() async throws {
        let root = tempRoot()
        try makeFile(root.appendingPathComponent("Banda/Disco/1.mp3"), title: "Uno")
        let database = try AppDatabase.makeEmpty()
        let scanner = LibraryScanner(database: database)
        _ = try await scanner.scan(root: root) { _ in }

        // "Se desconecta el disco".
        try FileManager.default.removeItem(at: root)
        do {
            _ = try await scanner.scan(root: root) { _ in }
            XCTFail("Debió avisar que la carpeta no está")
        } catch LibraryScanner.ScanError.folderUnavailable {
            // Esperado.
        }
        let count = try await database.writer.read { db in try Track.fetchCount(db) }
        XCTAssertEqual(count, 1, "la biblioteca no se toca")
    }

    func testMassRemovalNeedsConfirmation() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        for n in 1...30 { try makeFile(root.appendingPathComponent("Banda/A/\(n).mp3"), title: "A\(n)", frames: 20) }
        for n in 1...5 { try makeFile(root.appendingPathComponent("Banda/B/\(n).mp3"), title: "B\(n)", frames: 20) }
        let database = try AppDatabase.makeEmpty()
        let scanner = LibraryScanner(database: database)
        _ = try await scanner.scan(root: root) { _ in }

        try FileManager.default.removeItem(at: root.appendingPathComponent("Banda/A"))
        let summary = try await scanner.scan(root: root) { _ in }
        XCTAssertEqual(summary.withheldMissing, 30)
        XCTAssertEqual(summary.removed, 0)
        var count = try await database.writer.read { db in try Track.fetchCount(db) }
        XCTAssertEqual(count, 35)

        let confirmed = try await scanner.scan(root: root, allowMassRemoval: true) { _ in }
        XCTAssertEqual(confirmed.removed, 30)
        count = try await database.writer.read { db in try Track.fetchCount(db) }
        XCTAssertEqual(count, 5)

        XCTAssertFalse(LibraryScanner.isMassRemoval(missing: 3, known: 10), "pocas canciones: se quitan sin preguntar")
    }

    func testMovedFileKeepsStatistics() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeFile(root.appendingPathComponent("Banda/Disco/01 Uno.mp3"), title: "Uno")
        try makeFile(root.appendingPathComponent("Banda/Disco/02 Dos.mp3"), title: "Dos")
        let database = try AppDatabase.makeEmpty()
        let scanner = LibraryScanner(database: database)
        _ = try await scanner.scan(root: root) { _ in }
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE track SET playCount = 9, isFavorite = 1 WHERE title = 'Uno'")
        }

        // Se renombra la carpeta del disco y el archivo.
        try FileManager.default.moveItem(at: root.appendingPathComponent("Banda/Disco"),
                                         to: root.appendingPathComponent("Banda/Disco (1998)"))
        try FileManager.default.moveItem(at: root.appendingPathComponent("Banda/Disco (1998)/01 Uno.mp3"),
                                         to: root.appendingPathComponent("Banda/Disco (1998)/1-01 Uno.mp3"))
        let summary = try await scanner.scan(root: root) { _ in }
        XCTAssertEqual(summary.moved, 2)
        XCTAssertEqual(summary.added, 0)
        XCTAssertEqual(summary.removed, 0)

        let tracks = try await database.writer.read { db in try Track.order(Column("title")).fetchAll(db) }
        XCTAssertEqual(tracks.count, 2)
        let uno = try XCTUnwrap(tracks.first { $0.title == "Uno" })
        XCTAssertEqual(uno.relativePath, "Banda/Disco (1998)/1-01 Uno.mp3")
        XCTAssertEqual(uno.playCount, 9)
        XCTAssertTrue(uno.isFavorite)
    }
}

/// Cambio de carpeta raíz a la carpeta padre (caso real: "05 - Bootlegs" → "02 - Musica").
final class RootChangeTests: XCTestCase {
    func testChangingRootToParentKeepsEveryTrackAligned() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("octava-root-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let oldRoot = base.appendingPathComponent("05 - Bootlegs")
        var durations: [String: Int] = [:]
        for album in 1...3 {
            for n in 1...12 {
                let title = "Disco\(album) Tema \(n)"
                let frames = 40 + album * 13 + n * 7 // duraciones distintas
                durations[title] = frames
                var audio: [UInt8] = []
                for _ in 0..<frames { audio += [0xFF, 0xFB, 0x90, 0x64] + [UInt8](repeating: 0, count: 413) }
                let data = try ID3TagWriter.apply(TagChanges(text: [.title: title, .artist: "Banda", .album: "Disco \(album)",
                                                                    .trackNumber: "\(n)"]), to: Data(audio))
                let url = oldRoot.appendingPathComponent("Banda - Disco \(album)/CD 1/\(String(format: "%02d", n)) - \(title).mp3")
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url)
            }
        }
        // Otra música en la carpeta padre.
        let database = try AppDatabase.makeEmpty()
        let scanner = LibraryScanner(database: database)
        _ = try await scanner.scan(root: oldRoot) { _ in }
        try await database.writer.write { db in try db.execute(sql: "UPDATE track SET playCount = id") }
        let before = try await database.writer.read { db in try Track.fetchAll(db) }
        let playsByTitle = Dictionary(uniqueKeysWithValues: before.map { ($0.title, $0.playCount) })

        let summary = try await scanner.scan(root: base) { _ in }
        let after = try await database.writer.read { db in try Track.fetchAll(db) }
        XCTAssertEqual(summary.moved, 36)
        XCTAssertEqual(summary.withheldMissing, 0)
        XCTAssertEqual(after.count, 36)
        for track in after {
            XCTAssertTrue(track.relativePath.hasPrefix("05 - Bootlegs/"), track.relativePath)
            XCTAssertTrue(track.relativePath.contains(track.title), "\(track.relativePath) ≠ \(track.title)")
            XCTAssertEqual(track.playCount, playsByTitle[track.title], track.title)
        }
    }
}

/// Compilaciones: Artist = "Various Artists" y el intérprete en Album Artist → un solo disco.
final class CompilationGroupingTests: XCTestCase {
    func testCompilationIsOneAlbum() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("octava-va-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for (n, performer) in ["Clarence Carter", "Elton John", "The Seeds"].enumerated() {
            var audio: [UInt8] = []
            for _ in 0..<(30 + n * 5) { audio += [0xFF, 0xFB, 0x90, 0x64] + [UInt8](repeating: 0, count: 413) }
            let data = try ID3TagWriter.apply(TagChanges(text: [.title: "Tema \(n)", .artist: "Various Artists",
                                                                .albumArtist: performer, .album: "Almost Famous"]),
                                              to: Data(audio))
            let url = root.appendingPathComponent("VA/Almost Famous/\(n).mp3")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        let database = try AppDatabase.makeEmpty()
        _ = try await LibraryScanner(database: database).scan(root: root) { _ in }
        let albums = try await database.writer.read { db in try Album.fetchAll(db) }
        XCTAssertEqual(albums.map(\.albumArtist), ["Various Artists"])
        let tracks = try await database.writer.read { db in try Track.order(Column("title")).fetchAll(db) }
        XCTAssertEqual(tracks.map(\.performer), ["Clarence Carter", "Elton John", "The Seeds"])
    }
}
