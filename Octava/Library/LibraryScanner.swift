import Foundation
import GRDB

/// Recorre la carpeta de música, lee los tags de los MP3 nuevos o modificados y actualiza la base de datos.
/// Corre fuera del hilo principal para no congelar la interfaz.
actor LibraryScanner {
    struct Progress: Sendable {
        var processed: Int
        var total: Int
    }

    struct Summary: Sendable {
        var added = 0
        var updated = 0
        var removed = 0
        var failed = 0
    }

    /// Resultado de leer un archivo, listo para guardar.
    private struct ParsedFile {
        var relativePath: String
        var modifiedAt: Date
        var folderRelativePath: String
        var folderURL: URL
        var tags: TrackTags
    }

    private let database: AppDatabase
    private let batchSize = 100

    init(database: AppDatabase) {
        self.database = database
    }

    /// Cantidad de archivos cuyos tags se leen en paralelo.
    private let concurrency = 8

    func scan(root: URL, progress: @escaping @Sendable (Progress) -> Void) async throws -> Summary {
        let rootPath = root.standardizedFileURL.path
        let files = try Self.listMP3Files(in: root)
        var summary = Summary()

        // Pistas ya conocidas: ruta relativa → fecha de modificación guardada.
        let known: [String: Date] = try await database.writer.read { db in
            var result: [String: Date] = [:]
            let rows = try Row.fetchAll(db, sql: "SELECT relativePath, fileModifiedAt FROM track")
            for row in rows {
                let path: String = row["relativePath"]
                let modified: Date = row["fileModifiedAt"]
                result[path] = modified
            }
            return result
        }

        // Solo se leen los archivos nuevos o modificados desde el último escaneo.
        var seen = Set<String>()
        var changed: [(file: FoundFile, relative: String, isNew: Bool)] = []
        for file in files {
            let relative = Self.relativePath(of: file.url, rootPath: rootPath)
            seen.insert(relative)
            if let stored = known[relative] {
                if abs(stored.timeIntervalSince(file.modifiedAt)) > 1 {
                    changed.append((file, relative, false))
                }
            } else {
                changed.append((file, relative, true))
            }
        }

        progress(Progress(processed: 0, total: changed.count))
        var pending: [ParsedFile] = []
        var processed = 0

        // Lectura en paralelo por tandas: la lectura de tags es sobre todo espera de disco.
        for chunkStart in stride(from: 0, to: changed.count, by: concurrency) {
            try Task.checkCancellation()
            let chunk = Array(changed[chunkStart..<min(chunkStart + concurrency, changed.count)])
            let results = await withTaskGroup(of: (Int, Result<TrackTags, Error>).self) { group in
                for (offset, item) in chunk.enumerated() {
                    let url = item.file.url
                    group.addTask {
                        do { return (offset, .success(try await TagReader.read(url: url))) }
                        catch { return (offset, .failure(error)) }
                    }
                }
                var collected: [(Int, Result<TrackTags, Error>)] = []
                for await result in group { collected.append(result) }
                return collected.sorted { $0.0 < $1.0 }
            }

            for (offset, result) in results {
                let item = chunk[offset]
                switch result {
                case .success(let tags):
                    let folderURL = item.file.url.deletingLastPathComponent()
                    pending.append(ParsedFile(
                        relativePath: item.relative,
                        modifiedAt: item.file.modifiedAt,
                        folderRelativePath: Self.relativePath(of: folderURL, rootPath: rootPath),
                        folderURL: folderURL,
                        tags: tags))
                    if item.isNew { summary.added += 1 } else { summary.updated += 1 }
                case .failure(let error):
                    summary.failed += 1
                    print("Octava: no se pudieron leer los tags de \(item.relative): \(error)")
                }
            }

            processed += chunk.count
            if pending.count >= batchSize {
                try await save(pending)
                pending.removeAll(keepingCapacity: true)
            }
            progress(Progress(processed: processed, total: changed.count))
        }
        if !pending.isEmpty {
            try await save(pending)
        }

        summary.removed = try await removeMissing(seen: seen)
        return summary
    }

    // MARK: Guardado

    private func save(_ files: [ParsedFile]) async throws {
        // Discos que quedaron sin carátula en caché y de dónde sacarla.
        struct CoverJob { var albumId: Int64; var artwork: Data?; var folderURL: URL }

        let coverJobs: [CoverJob] = try await database.writer.write { db in
            var jobs: [Int64: CoverJob] = [:]
            for file in files {
                let tags = file.tags
                let artistForGrouping = Self.nonEmpty(tags.albumArtist) ?? Self.nonEmpty(tags.artist) ?? "Artista desconocido"
                let albumTitle = Self.nonEmpty(tags.album) ?? file.folderURL.lastPathComponent

                let album = try Self.findOrCreateAlbum(db: db,
                                                       title: albumTitle,
                                                       albumArtist: artistForGrouping,
                                                       year: tags.year,
                                                       folderPath: file.folderRelativePath)

                var track = try Track.filter(Track.Columns.relativePath == file.relativePath).fetchOne(db)
                    ?? Track(relativePath: file.relativePath,
                             fileModifiedAt: file.modifiedAt,
                             title: "",
                             artist: "",
                             album: "",
                             duration: 0)
                track.fileModifiedAt = file.modifiedAt
                track.title = Self.nonEmpty(tags.title) ?? Self.titleFromFileName(file.relativePath)
                track.artist = Self.nonEmpty(tags.artist) ?? artistForGrouping
                track.albumArtist = Self.nonEmpty(tags.albumArtist)
                track.album = albumTitle
                track.trackNumber = tags.trackNumber
                track.discNumber = tags.discNumber
                track.year = tags.year
                track.genre = tags.genre
                track.duration = tags.duration
                track.replayGainTrack = tags.replayGainTrack
                track.replayGainAlbum = tags.replayGainAlbum
                track.bitrate = tags.bitrate
                track.albumId = album.id
                try track.save(db)

                if let albumId = album.id, album.coverCachePath == nil {
                    var job = jobs[albumId] ?? CoverJob(albumId: albumId, artwork: nil, folderURL: file.folderURL)
                    if job.artwork == nil { job.artwork = tags.artwork }
                    jobs[albumId] = job
                }
            }
            return Array(jobs.values)
        }

        // Miniaturas fuera de la transacción.
        for job in coverJobs {
            var path: String?
            if let artwork = job.artwork {
                path = try? CoverCache.storeThumbnail(from: artwork, albumId: job.albumId)
            }
            if path == nil, let folderCover = CoverCache.findFolderCover(in: job.folderURL) {
                path = try? CoverCache.storeThumbnail(fromFile: folderCover, albumId: job.albumId)
            }
            if let path {
                try await database.writer.write { db in
                    try db.execute(sql: "UPDATE album SET coverCachePath = ? WHERE id = ?", arguments: [path, job.albumId])
                }
            }
        }
    }

    private static func findOrCreateAlbum(db: Database, title: String, albumArtist: String, year: Int?, folderPath: String) throws -> Album {
        if var existing = try Album
            .filter(Album.Columns.albumArtist == albumArtist && Album.Columns.title == title)
            .fetchOne(db) {
            if existing.year == nil, let year {
                existing.year = year
                try existing.update(db)
            }
            return existing
        }
        var album = Album(title: title, albumArtist: albumArtist, year: year, folderPath: folderPath)
        try album.insert(db)
        return album
    }

    /// Borra las pistas cuyos archivos ya no existen y los discos que quedaron vacíos.
    private func removeMissing(seen: Set<String>) async throws -> Int {
        try await database.writer.write { db in
            let stored = try String.fetchAll(db, sql: "SELECT relativePath FROM track")
            let missing = stored.filter { !seen.contains($0) }
            for path in missing {
                try db.execute(sql: "DELETE FROM track WHERE relativePath = ?", arguments: [path])
            }
            try db.execute(sql: "DELETE FROM album WHERE id NOT IN (SELECT DISTINCT albumId FROM track WHERE albumId IS NOT NULL)")
            return missing.count
        }
    }

    // MARK: Archivos

    struct FoundFile: Sendable { var url: URL; var modifiedAt: Date }

    private static func listMP3Files(in root: URL) throws -> [FoundFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(at: root,
                                                              includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return []
        }
        var result: [FoundFile] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "mp3" {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { continue }
            result.append(FoundFile(url: url, modifiedAt: values.contentModificationDate ?? .distantPast))
        }
        return result.sorted { $0.url.path < $1.url.path }
    }

    static func relativePath(of url: URL, rootPath: String) -> String {
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return path }
        var relative = String(path.dropFirst(rootPath.count))
        if relative.hasPrefix("/") { relative.removeFirst() }
        return relative
    }

    static func titleFromFileName(_ relativePath: String) -> String {
        let name = (relativePath as NSString).lastPathComponent
        return (name as NSString).deletingPathExtension
    }

    static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }
}
