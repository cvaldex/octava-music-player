import Foundation

/// Lee los frames de texto de usuario (TXXX) de la etiqueta ID3v2 de un MP3, por ejemplo
/// "REPLAYGAIN_TRACK_GAIN" = "-6.54 dB". AVFoundation no expone bien la descripción de estos frames,
/// así que se leen directamente. Soporta ID3v2.2, v2.3 y v2.4.
enum ID3UserTextReader {
    /// Límite de seguridad para el tamaño de la etiqueta (las carátulas grandes caben de sobra).
    static let maxTagSize = 64 * 1024 * 1024

    /// Devuelve descripción (en mayúsculas) → valor.
    static func read(url: URL) -> [String: String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [:] }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 10), header.count == 10 else { return [:] }
        let headerBytes = [UInt8](header)
        guard headerBytes[0] == 0x49, headerBytes[1] == 0x44, headerBytes[2] == 0x33 else { return [:] } // "ID3"
        let size = synchsafe(headerBytes[6], headerBytes[7], headerBytes[8], headerBytes[9])
        guard size > 0, size <= maxTagSize,
              let body = try? handle.read(upToCount: size) else { return [:] }
        return parse(tag: headerBytes + [UInt8](body))
    }

    /// Analiza una etiqueta completa (cabecera de 10 bytes + cuerpo). Expuesto para los tests.
    static func parse(tag: [UInt8]) -> [String: String] {
        guard tag.count >= 10, tag[0] == 0x49, tag[1] == 0x44, tag[2] == 0x33 else { return [:] }
        let major = tag[3]
        let flags = tag[5]
        let size = synchsafe(tag[6], tag[7], tag[8], tag[9])
        var body = Array(tag[10..<min(tag.count, 10 + size)])

        // Desincronización a nivel de etiqueta (v2.2 y v2.3): FF 00 → FF.
        if flags & 0x80 != 0 && major < 4 {
            body = removeUnsynchronization(body)
        }

        var offset = 0
        // Cabecera extendida.
        if flags & 0x40 != 0 && major >= 3 && body.count >= 4 {
            if major == 4 {
                offset = synchsafe(body[0], body[1], body[2], body[3])
            } else {
                offset = 4 + bigEndian(body[0], body[1], body[2], body[3])
            }
        }

        let idLength = major == 2 ? 3 : 4
        let headerLength = major == 2 ? 6 : 10
        let wanted = major == 2 ? "TXX" : "TXXX"
        var result: [String: String] = [:]

        while offset + headerLength <= body.count {
            let idBytes = body[offset..<(offset + idLength)]
            if idBytes.first == 0 { break } // relleno
            guard let id = String(bytes: idBytes, encoding: .isoLatin1) else { break }

            let frameSize: Int
            var frameFlags: UInt16 = 0
            if major == 2 {
                frameSize = (Int(body[offset + 3]) << 16) | (Int(body[offset + 4]) << 8) | Int(body[offset + 5])
            } else if major == 4 {
                frameSize = synchsafe(body[offset + 4], body[offset + 5], body[offset + 6], body[offset + 7])
                frameFlags = (UInt16(body[offset + 8]) << 8) | UInt16(body[offset + 9])
            } else {
                frameSize = bigEndian(body[offset + 4], body[offset + 5], body[offset + 6], body[offset + 7])
                frameFlags = (UInt16(body[offset + 8]) << 8) | UInt16(body[offset + 9])
            }

            let start = offset + headerLength
            let end = start + frameSize
            guard frameSize > 0, end <= body.count else { break }

            if id == wanted {
                var content = Array(body[start..<end])
                if major == 4 {
                    // Indicador de longitud de datos: 4 bytes extra al inicio.
                    if frameFlags & 0x0001 != 0, content.count > 4 { content.removeFirst(4) }
                    // Desincronización por frame.
                    if frameFlags & 0x0002 != 0 { content = removeUnsynchronization(content) }
                }
                if let (description, value) = decodeUserText(content) {
                    result[description.uppercased()] = value
                }
            }
            offset = end
        }
        return result
    }

    /// Contenido de un frame TXXX: codificación (1 byte), descripción terminada en nulo, valor.
    static func decodeUserText(_ content: [UInt8]) -> (String, String)? {
        guard let encodingByte = content.first else { return nil }
        let data = Array(content.dropFirst())
        let isWide = encodingByte == 1 || encodingByte == 2

        // Buscar el terminador de la descripción.
        var split: Int?
        if isWide {
            var i = 0
            while i + 1 < data.count {
                if data[i] == 0 && data[i + 1] == 0 { split = i; break }
                i += 2
            }
        } else {
            split = data.firstIndex(of: 0)
        }
        guard let split else { return nil }

        let terminatorLength = isWide ? 2 : 1
        let descriptionBytes = Array(data[..<split])
        let valueBytes = Array(data[min(data.count, split + terminatorLength)...])

        guard let description = decode(descriptionBytes, encoding: encodingByte),
              let value = decode(valueBytes, encoding: encodingByte) else { return nil }
        return (description, value)
    }

    private static func decode(_ bytes: [UInt8], encoding: UInt8) -> String? {
        let stringEncoding: String.Encoding
        switch encoding {
        case 0: stringEncoding = .isoLatin1
        case 1: stringEncoding = .utf16      // con BOM
        case 2: stringEncoding = .utf16BigEndian
        case 3: stringEncoding = .utf8
        default: return nil
        }
        if bytes.isEmpty { return "" }
        guard let text = String(bytes: bytes, encoding: stringEncoding) else { return nil }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: "\u{0}").union(.whitespacesAndNewlines))
    }

    static func synchsafe(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> Int {
        (Int(a & 0x7F) << 21) | (Int(b & 0x7F) << 14) | (Int(c & 0x7F) << 7) | Int(d & 0x7F)
    }

    static func bigEndian(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> Int {
        (Int(a) << 24) | (Int(b) << 16) | (Int(c) << 8) | Int(d)
    }

    private static func removeUnsynchronization(_ bytes: [UInt8]) -> [UInt8] {
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
