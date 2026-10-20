import Foundation

/// Importación de listas de reproducción de otros programas: XSPF (VLC, Clementine, Strawberry) y M3U/M3U8.
/// Las canciones se buscan en la biblioteca; el archivo de la lista no se modifica.
enum PlaylistImport {
    struct Entry: Equatable {
        var location: String?
        var title: String?
        var creator: String?
        var album: String?
    }

    struct Parsed: Equatable {
        var title: String?
        var entries: [Entry]
    }

    struct Match {
        var trackIDs: [Int64]
        /// Entradas que no se encontraron en la biblioteca, en el orden de la lista.
        var missing: [Entry]
    }

    static let fileExtensions = ["xspf", "m3u", "m3u8"]

    // MARK: Lectura

    static func parse(data: Data, fileExtension: String) -> Parsed {
        if fileExtension.lowercased() == "xspf" {
            return parseXSPF(data)
        }
        // M3U: UTF-8 (m3u8) o, en archivos viejos, Latin-1.
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        return parseM3U(text)
    }

    static func parseXSPF(_ data: Data) -> Parsed {
        let delegate = XSPFParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return Parsed(title: delegate.playlistTitle, entries: delegate.entries)
    }

    /// `#EXTINF:duración,Artista - Título` (opcional) seguido de la ruta.
    static func parseM3U(_ text: String) -> Parsed {
        var entries: [Entry] = []
        var title: String?
        var pending = Entry()
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\u{FEFF}", with: "")
            if line.isEmpty { continue }
            if line.hasPrefix("#PLAYLIST:") {
                title = String(line.dropFirst("#PLAYLIST:".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("#EXTINF:") {
                let info = line.dropFirst("#EXTINF:".count)
                if let comma = info.firstIndex(of: ",") {
                    let name = info[info.index(after: comma)...].trimmingCharacters(in: .whitespaces)
                    if let dash = name.range(of: " - ") {
                        pending.creator = String(name[..<dash.lowerBound])
                        pending.title = String(name[dash.upperBound...])
                    } else if !name.isEmpty {
                        pending.title = name
                    }
                }
            } else if !line.hasPrefix("#") {
                pending.location = line
                entries.append(pending)
                pending = Entry()
            }
        }
        return Parsed(title: title, entries: entries)
    }

    // MARK: Búsqueda en la biblioteca

    /// Busca cada entrada: primero por ruta (relativa a la carpeta de música), luego por el final de la ruta
    /// (listas hechas en otro computador) y por último por título y artista.
    static func match(_ entries: [Entry], tracks: [Track], musicFolder: URL?, playlistFolder: URL?) -> Match {
        var byPath: [String: Int64] = [:]
        var byTail2: [String: [Int64]] = [:]
        var byTail3: [String: [Int64]] = [:]
        var byTitle: [String: [Int64]] = [:]
        for track in tracks {
            guard let id = track.id else { continue }
            let key = normalized(track.relativePath)
            byPath[key] = id
            let parts = key.split(separator: "/")
            byTail2[parts.suffix(2).joined(separator: "/"), default: []].append(id)
            byTail3[parts.suffix(3).joined(separator: "/"), default: []].append(id)
            byTitle[normalized(track.title) + "\u{1}" + normalized(track.performer), default: []].append(id)
            byTitle[normalized(track.title) + "\u{1}" + normalized(track.artist), default: []].append(id)
        }
        let root = musicFolder.map { normalized($0.standardizedFileURL.path) }

        var ids: [Int64] = []
        var missing: [Entry] = []
        for entry in entries {
            if let id = find(entry, root: root, playlistFolder: playlistFolder,
                             byPath: byPath, byTail2: byTail2, byTail3: byTail3, byTitle: byTitle) {
                ids.append(id)
            } else {
                missing.append(entry)
            }
        }
        return Match(trackIDs: ids, missing: missing)
    }

    private static func find(_ entry: Entry, root: String?, playlistFolder: URL?,
                             byPath: [String: Int64], byTail2: [String: [Int64]],
                             byTail3: [String: [Int64]], byTitle: [String: [Int64]]) -> Int64? {
        if let location = entry.location, let path = filePath(from: location, relativeTo: playlistFolder) {
            let key = normalized(path)
            if let root, key.hasPrefix(root + "/"), let id = byPath[String(key.dropFirst(root.count + 1))] {
                return id
            }
            let parts = key.split(separator: "/")
            if parts.count >= 3, let ids = byTail3[parts.suffix(3).joined(separator: "/")], ids.count == 1 { return ids[0] }
            if parts.count >= 2, let ids = byTail2[parts.suffix(2).joined(separator: "/")], ids.count == 1 { return ids[0] }
        }
        if let title = entry.title, let creator = entry.creator {
            let ids = Set(byTitle[normalized(title) + "\u{1}" + normalized(creator)] ?? [])
            if ids.count == 1 { return ids.first }
        }
        return nil
    }

    /// "file:///Users/x/a%20b.mp3", "/Users/x/a b.mp3" o una ruta relativa a la lista → ruta absoluta.
    static func filePath(from location: String, relativeTo folder: URL?) -> String? {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("file:") {
            return URL(string: trimmed)?.standardizedFileURL.path
                ?? trimmed.dropFirst("file://".count).removingPercentEncoding
        }
        if trimmed.contains("://") { return nil } // radios y direcciones web
        let path = trimmed.replacingOccurrences(of: "\\", with: "/")
        if path.hasPrefix("/") { return path }
        // Windows ("D:/Musica/…"): vale para buscar por el final de la ruta.
        if path.count > 2, path.dropFirst().hasPrefix(":/") { return String(path.dropFirst(2)) }
        guard let folder else { return nil }
        return folder.appendingPathComponent(path).standardizedFileURL.path
    }

    /// Comparación sin mayúsculas y con la misma forma Unicode (macOS guarda las tildes descompuestas).
    static func normalized(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased()
    }
}

/// Lee `<playlist><title>` y cada `<track>` (location, title, creator, album) de un XSPF.
private final class XSPFParser: NSObject, XMLParserDelegate {
    var playlistTitle: String?
    var entries: [PlaylistImport.Entry] = []

    private var current: PlaylistImport.Entry?
    private var text = ""
    private var depth = 0

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        depth += 1
        text = ""
        if elementName == "track" { current = PlaylistImport.Entry() }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        defer { depth -= 1 }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""
        if elementName == "track", let entry = current {
            entries.append(entry)
            current = nil
            return
        }
        guard !value.isEmpty else { return }
        if current != nil {
            switch elementName {
            case "location": if current?.location == nil { current?.location = value }
            case "title": current?.title = value
            case "creator": current?.creator = value
            case "album": current?.album = value
            default: break
            }
        } else if elementName == "title", depth == 2 {
            playlistTitle = value
        }
    }
}
