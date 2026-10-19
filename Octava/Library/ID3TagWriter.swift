import Foundation

/// Campos editables de una canción.
enum TagField: String, Codable, CaseIterable, Sendable {
    case title, artist, albumArtist, album, trackNumber, discNumber, year, genre

    var label: String {
        switch self {
        case .title: "Título"
        case .artist: "Artista"
        case .albumArtist: "Artista del álbum"
        case .album: "Álbum"
        case .trackNumber: "Pista"
        case .discNumber: "Disco"
        case .year: "Año"
        case .genre: "Género"
        }
    }

    /// Nombre en minúscula para frases ("Se escribirá el año…").
    var phrase: String {
        switch self {
        case .title: "el título"
        case .artist: "el artista"
        case .albumArtist: "el artista del álbum"
        case .album: "el álbum"
        case .trackNumber: "el número de pista"
        case .discNumber: "el número de disco"
        case .year: "el año"
        case .genre: "el género"
        }
    }
}

/// Cambios a escribir en un MP3. Un texto vacío borra el campo; un campo ausente no se toca.
struct TagChanges: Codable, Equatable, Sendable {
    struct Artwork: Codable, Equatable, Sendable {
        /// Vacío = quitar la carátula.
        var data: Data
        var mimeType: String
    }

    var text: [TagField: String] = [:]
    var artwork: Artwork?

    var isEmpty: Bool { text.isEmpty && artwork == nil }
}

/// Escritura de tags ID3 propia, pensada para no perder nada:
/// - Solo se reemplazan los frames de los campos editados; el resto (ReplayGain en TXXX, comentarios, letras,
///   otras imágenes, frames desconocidos) se copia byte a byte, igual que el audio.
/// - Se conserva la versión de la etiqueta (v2.3 o v2.4). Un archivo sin etiqueta recibe una v2.4.
/// - Si el archivo trae también una etiqueta ID3v1 al final, se actualiza para que coincida.
/// - El archivo se escribe completo en un temporal de la misma carpeta y reemplaza al original de forma atómica;
///   antes de reemplazar se verifica que la etiqueta nueva se pueda leer y que el audio quedó idéntico.
enum ID3TagWriter {
    enum Failure: LocalizedError, Equatable {
        case unsupportedVersion(Int)
        case unsupportedFlags
        case damagedTag
        case verificationFailed

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version):
                "La etiqueta es ID3v2.\(version), que Octava no sabe escribir."
            case .unsupportedFlags:
                "La etiqueta usa una codificación especial (desincronización ID3v2.4) que Octava no sabe escribir."
            case .damagedTag:
                "La etiqueta ID3 del archivo está dañada; no se modificó para no perder datos."
            case .verificationFailed:
                "La verificación del archivo nuevo falló; el original no se modificó."
            }
        }
    }

    /// Relleno que se deja al final de la etiqueta (permite a otros programas editar sin reescribir el archivo).
    static let padding = 2048

    // MARK: Archivo

    /// Aplica los cambios al archivo y devuelve los valores anteriores de esos campos (para deshacer).
    @discardableResult
    static func apply(_ changes: TagChanges, toFileAt url: URL) throws -> TagChanges {
        let original = try Data(contentsOf: url, options: .mappedIfSafe)
        let previous = try previousValues(for: changes, in: original)
        let updated = try apply(changes, to: original)
        guard updated != original else { return previous }

        let folder = url.deletingLastPathComponent()
        let temporary = folder.appendingPathComponent(".octava-\(UUID().uuidString).tmp")
        do {
            try updated.write(to: temporary, options: .withoutOverwriting)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        return previous
    }

    // MARK: Datos (lógica pura, testeada)

    /// Devuelve el contenido del archivo con los cambios aplicados.
    static func apply(_ changes: TagChanges, to file: Data) throws -> Data {
        let bytes = [UInt8](file)
        let located = try locateTag(in: bytes)
        var tag = located.tag ?? ID3Tag(major: 4, frames: [])

        for field in TagField.allCases {
            guard let value = changes.text[field] else { continue }
            tag.setText(value, for: field)
        }
        if let artwork = changes.artwork {
            tag.setArtwork(artwork)
        }

        var audio = Array(bytes[located.audioStart...])
        if hasID3v1(audio) {
            updateID3v1(&audio, with: changes)
        }

        let newTag = tag.serialized(padding: padding)
        let result = newTag + audio

        // Verificación antes de tocar el disco: la etiqueta nueva se lee y el audio quedó idéntico.
        guard let check = try? locateTag(in: result), check.tag != nil,
              result.count - check.audioStart == audio.count else {
            throw Failure.verificationFailed
        }
        return Data(result)
    }

    /// Valores actuales de los campos que se van a cambiar, en el formato de `TagChanges`.
    static func previousValues(for changes: TagChanges, in file: Data) throws -> TagChanges {
        let tag = try locateTag(in: [UInt8](file)).tag
        var previous = TagChanges()
        for field in changes.text.keys {
            previous.text[field] = tag?.text(for: field) ?? ""
        }
        if changes.artwork != nil {
            previous.artwork = tag?.frontCover() ?? TagChanges.Artwork(data: Data(), mimeType: "")
        }
        return previous
    }

    /// Lee los campos de texto de la etiqueta (para los tests y diagnósticos).
    static func readText(from file: Data) throws -> [TagField: String] {
        guard let tag = try locateTag(in: [UInt8](file)).tag else { return [:] }
        var result: [TagField: String] = [:]
        for field in TagField.allCases {
            if let value = tag.text(for: field) { result[field] = value }
        }
        return result
    }

    // MARK: Lectura de la etiqueta

    struct Located {
        var tag: ID3Tag?
        /// Dónde empieza lo que no es la etiqueta (el audio).
        var audioStart: Int
    }

    static func locateTag(in bytes: [UInt8]) throws -> Located {
        guard bytes.count >= 10, bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 else {
            return Located(tag: nil, audioStart: 0)
        }
        let major = bytes[3]
        let flags = bytes[5]
        guard bytes[6] < 0x80, bytes[7] < 0x80, bytes[8] < 0x80, bytes[9] < 0x80 else { throw Failure.damagedTag }
        let size = synchsafe(bytes[6], bytes[7], bytes[8], bytes[9])
        let hasFooter = major == 4 && flags & 0x10 != 0
        let audioStart = 10 + size + (hasFooter ? 10 : 0)
        guard audioStart <= bytes.count else { throw Failure.damagedTag }

        guard major == 3 || major == 4 else { throw Failure.unsupportedVersion(Int(major)) }
        if major == 4 && flags & 0x80 != 0 { throw Failure.unsupportedFlags }

        var body = Array(bytes[10..<(10 + size)])
        if major == 3 && flags & 0x80 != 0 {
            body = removeUnsynchronization(body)
        }

        var offset = 0
        if flags & 0x40 != 0, body.count >= 4 {
            // Cabecera extendida: se descarta al reescribir.
            offset = major == 4
                ? synchsafe(body[0], body[1], body[2], body[3])
                : 4 + bigEndian(body[0], body[1], body[2], body[3])
            guard offset <= body.count else { throw Failure.damagedTag }
        }

        var frames: [ID3Frame] = []
        while offset + 10 <= body.count {
            let idBytes = Array(body[offset..<(offset + 4)])
            if idBytes[0] == 0 {
                // Relleno: todo lo que sigue debería ser cero.
                guard body[offset...].allSatisfy({ $0 == 0 }) else { throw Failure.damagedTag }
                break
            }
            guard idBytes.allSatisfy(isFrameIDByte), let id = String(bytes: idBytes, encoding: .ascii) else {
                throw Failure.damagedTag
            }
            let sizeBytes = Array(body[(offset + 4)..<(offset + 8)])
            let size = frameSize(sizeBytes, major: major, body: body, frameStart: offset)
            let start = offset + 10
            let end = start + size
            guard end <= body.count else { throw Failure.damagedTag }
            frames.append(ID3Frame(id: id,
                                   flags: [body[offset + 8], body[offset + 9]],
                                   content: Array(body[start..<end])))
            offset = end
        }
        return Located(tag: ID3Tag(major: major, frames: frames), audioStart: audioStart)
    }

    /// Tamaño de un frame. En v2.4 debe ser "synchsafe", pero algunos programas (iTunes antiguo) escribían
    /// el tamaño normal: se usa el que deja un frame válido (u otro relleno o el final) a continuación.
    private static func frameSize(_ b: [UInt8], major: UInt8, body: [UInt8], frameStart: Int) -> Int {
        let plain = bigEndian(b[0], b[1], b[2], b[3])
        guard major == 4 else { return plain }
        guard b.allSatisfy({ $0 < 0x80 }) else { return plain }
        let safe = synchsafe(b[0], b[1], b[2], b[3])
        if safe == plain { return safe }
        func looksValid(_ size: Int) -> Bool {
            let next = frameStart + 10 + size
            if next == body.count { return true }
            guard next < body.count else { return false }
            if body[next] == 0 { return true }
            guard next + 4 <= body.count else { return false }
            return body[next..<(next + 4)].allSatisfy(isFrameIDByte)
        }
        if looksValid(safe) { return safe }
        if looksValid(plain) { return plain }
        return safe
    }

    private static func isFrameIDByte(_ byte: UInt8) -> Bool {
        (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x30 && byte <= 0x39)
    }

    // MARK: ID3v1

    static func hasID3v1(_ audio: [UInt8]) -> Bool {
        audio.count >= 128 && audio[audio.count - 128] == 0x54 && audio[audio.count - 127] == 0x41 && audio[audio.count - 126] == 0x47
    }

    /// Actualiza la etiqueta ID3v1 (últimos 128 bytes) con los campos que existen en ella.
    static func updateID3v1(_ audio: inout [UInt8], with changes: TagChanges) {
        let base = audio.count - 128
        func write(_ text: String, at offset: Int, length: Int) {
            let data = [UInt8](text.data(using: .isoLatin1, allowLossyConversion: true) ?? Data())
            for i in 0..<length {
                audio[base + offset + i] = i < data.count ? data[i] : 0
            }
        }
        if let title = changes.text[.title] { write(title, at: 3, length: 30) }
        if let artist = changes.text[.artist] { write(artist, at: 33, length: 30) }
        if let album = changes.text[.album] { write(album, at: 63, length: 30) }
        if let year = changes.text[.year] { write(String(year.prefix(4)), at: 93, length: 4) }
        if let track = changes.text[.trackNumber], audio[base + 125] == 0 {
            // ID3v1.1: el número de pista va en el último byte del comentario.
            let number = TagReader.leadingNumber(track) ?? 0
            audio[base + 126] = UInt8(clamping: number)
        }
        if let genre = changes.text[.genre] {
            let index = TagReader.id3v1Genres.firstIndex { $0.caseInsensitiveCompare(genre) == .orderedSame }
            audio[base + 127] = index.map { UInt8($0) } ?? 255
        }
    }

    // MARK: Ayudas

    static func synchsafe(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> Int {
        (Int(a & 0x7F) << 21) | (Int(b & 0x7F) << 14) | (Int(c & 0x7F) << 7) | Int(d & 0x7F)
    }

    static func bigEndian(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> Int {
        (Int(a) << 24) | (Int(b) << 16) | (Int(c) << 8) | Int(d)
    }

    static func synchsafeBytes(_ value: Int) -> [UInt8] {
        [UInt8((value >> 21) & 0x7F), UInt8((value >> 14) & 0x7F), UInt8((value >> 7) & 0x7F), UInt8(value & 0x7F)]
    }

    static func bigEndianBytes(_ value: Int) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    static func removeUnsynchronization(_ bytes: [UInt8]) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count)
        var previousWasFF = false
        for byte in bytes {
            if previousWasFF && byte == 0 {
                previousWasFF = false
                continue
            }
            result.append(byte)
            previousWasFF = byte == 0xFF
        }
        return result
    }
}

// MARK: - Etiqueta en memoria

struct ID3Frame: Equatable {
    var id: String
    var flags: [UInt8]
    /// Contenido tal como está en el archivo.
    var content: [UInt8]
}

struct ID3Tag: Equatable {
    var major: UInt8
    var frames: [ID3Frame]

    /// Frame que guarda cada campo en esta versión.
    func frameID(for field: TagField) -> String {
        switch field {
        case .title: "TIT2"
        case .artist: "TPE1"
        case .albumArtist: "TPE2"
        case .album: "TALB"
        case .trackNumber: "TRCK"
        case .discNumber: "TPOS"
        case .year: major == 4 ? "TDRC" : "TYER"
        case .genre: "TCON"
        }
    }

    /// Frames equivalentes de la otra versión que se quitan al escribir (para no dejar dos años distintos).
    private func alternateIDs(for field: TagField) -> [String] {
        field == .year ? (major == 4 ? ["TYER"] : ["TDRC"]) : []
    }

    // MARK: Texto

    func text(for field: TagField) -> String? {
        for id in [frameID(for: field)] + alternateIDs(for: field) {
            if let frame = frames.first(where: { $0.id == id }), let value = decodeText(frame) {
                return value
            }
        }
        return nil
    }

    mutating func setText(_ value: String, for field: TagField) {
        let id = frameID(for: field)
        var value = value.trimmingCharacters(in: .whitespacesAndNewlines)

        // Pista y disco: si solo se cambió el número, conservar el total ("3/12" → "5/12").
        if (field == .trackNumber || field == .discNumber), !value.isEmpty, !value.contains("/"),
           let old = text(for: field), let slash = old.firstIndex(of: "/") {
            value += old[slash...]
        }

        let removed = Set([id] + alternateIDs(for: field))
        let firstIndex = frames.firstIndex { removed.contains($0.id) }
        frames.removeAll { removed.contains($0.id) }
        guard !value.isEmpty else { return }

        let frame = ID3Frame(id: id, flags: [0, 0], content: encodeText(value))
        frames.insert(frame, at: min(firstIndex ?? frames.count, frames.count))
    }

    private func decodeText(_ frame: ID3Frame) -> String? {
        guard let content = Self.decodedContent(frame, major: major), let encoding = content.first else { return nil }
        var data = Array(content.dropFirst())
        // Varios valores (v2.4) separados por nulo: se toma el primero.
        let isWide = encoding == 1 || encoding == 2
        if isWide {
            var i = 0
            while i + 1 < data.count {
                if data[i] == 0 && data[i + 1] == 0 { data = Array(data[..<i]); break }
                i += 2
            }
        } else if let zero = data.firstIndex(of: 0) {
            data = Array(data[..<zero])
        }
        let string: String?
        switch encoding {
        case 0: string = String(bytes: data, encoding: .isoLatin1)
        case 1: string = String(bytes: data, encoding: .utf16)
        case 2: string = String(bytes: data, encoding: .utf16BigEndian)
        case 3: string = String(bytes: data, encoding: .utf8)
        default: string = nil
        }
        return string?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Contenido sin los agregados de v2.4 (indicador de longitud, desincronización por frame).
    /// Devuelve nil si el frame está comprimido o cifrado.
    static func decodedContent(_ frame: ID3Frame, major: UInt8) -> [UInt8]? {
        var content = frame.content
        let flags = frame.flags.count == 2 ? frame.flags[1] : 0
        if major == 4 {
            if flags & 0x08 != 0 || flags & 0x04 != 0 { return nil } // comprimido o cifrado
            if flags & 0x40 != 0, !content.isEmpty { content.removeFirst() } // identidad de grupo
            if flags & 0x01 != 0 { content = Array(content.dropFirst(4)) }
            if flags & 0x02 != 0 { content = ID3TagWriter.removeUnsynchronization(content) }
        } else {
            if flags & 0x80 != 0 || flags & 0x40 != 0 { return nil }
            if flags & 0x20 != 0, !content.isEmpty { content.removeFirst() }
        }
        return content
    }

    /// v2.4: UTF-8. v2.3: Latin-1 si alcanza, si no UTF-16 con BOM.
    private func encodeText(_ value: String) -> [UInt8] {
        if major == 4 {
            return [0x03] + Array(value.utf8)
        }
        if value.unicodeScalars.allSatisfy({ $0.value <= 0xFF }),
           let latin1 = value.data(using: .isoLatin1) {
            return [0x00] + [UInt8](latin1)
        }
        var bytes: [UInt8] = [0x01, 0xFF, 0xFE]
        for unit in value.utf16 {
            bytes.append(UInt8(unit & 0xFF))
            bytes.append(UInt8(unit >> 8))
        }
        return bytes
    }

    // MARK: Carátula

    /// Tipo de imagen de un APIC (3 = portada, 0 = otra).
    static func pictureType(_ frame: ID3Frame, major: UInt8) -> UInt8? {
        guard frame.id == "APIC", let content = decodedContent(frame, major: major), content.count > 2 else { return nil }
        guard let mimeEnd = content[1...].firstIndex(of: 0), mimeEnd + 1 < content.count else { return nil }
        return content[mimeEnd + 1]
    }

    static func isCover(_ frame: ID3Frame, major: UInt8) -> Bool {
        guard frame.id == "APIC" else { return false }
        let type = pictureType(frame, major: major)
        return type == 3 || type == 0 || type == nil
    }

    func frontCover() -> TagChanges.Artwork? {
        let major = self.major
        let covers = frames.filter { Self.isCover($0, major: major) }
        guard let frame = covers.first(where: { Self.pictureType($0, major: major) == 3 }) ?? covers.first,
              let content = Self.decodedContent(frame, major: major), let encoding = content.first,
              let mimeEnd = content[1...].firstIndex(of: 0) else { return nil }
        let mime = String(bytes: content[1..<mimeEnd], encoding: .isoLatin1) ?? "image/jpeg"
        // Tras el tipo viene la descripción terminada en nulo (1 o 2 bytes según la codificación).
        var index = mimeEnd + 2
        let isWide = encoding == 1 || encoding == 2
        if isWide {
            while index + 1 < content.count, !(content[index] == 0 && content[index + 1] == 0) { index += 2 }
            index += 2
        } else {
            while index < content.count, content[index] != 0 { index += 1 }
            index += 1
        }
        guard index <= content.count else { return nil }
        return TagChanges.Artwork(data: Data(content[index...]), mimeType: mime)
    }

    /// Reemplaza la portada (y las imágenes sin tipo útil); conserva contraportadas y otras imágenes.
    mutating func setArtwork(_ artwork: TagChanges.Artwork) {
        let major = self.major
        let firstIndex = frames.firstIndex { Self.isCover($0, major: major) }
        frames.removeAll { Self.isCover($0, major: major) }
        guard !artwork.data.isEmpty else { return }
        let mime = artwork.mimeType.isEmpty ? "image/jpeg" : artwork.mimeType
        let content: [UInt8] = [0x00] + Array(mime.utf8) + [0x00, 0x03, 0x00] + [UInt8](artwork.data)
        frames.insert(ID3Frame(id: "APIC", flags: [0, 0], content: content), at: min(firstIndex ?? frames.count, frames.count))
    }

    // MARK: Serialización

    func serialized(padding: Int) -> [UInt8] {
        var body: [UInt8] = []
        for frame in frames {
            body += Array(frame.id.utf8)
            body += major == 4 ? ID3TagWriter.synchsafeBytes(frame.content.count) : ID3TagWriter.bigEndianBytes(frame.content.count)
            body += frame.flags.count == 2 ? frame.flags : [0, 0]
            body += frame.content
        }
        body += [UInt8](repeating: 0, count: padding)
        return [0x49, 0x44, 0x33, major, 0x00, 0x00] + ID3TagWriter.synchsafeBytes(body.count) + body
    }
}
