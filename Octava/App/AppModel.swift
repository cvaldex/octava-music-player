import Foundation
import Observation

/// Estado global de la app: base de datos, biblioteca, reproductor y carpeta de música.
@MainActor
@Observable
final class AppModel {
    let database: AppDatabase
    let library: LibraryStore
    let player: PlaybackEngine

    private(set) var musicFolder: URL?
    private(set) var isScanning = false
    private(set) var scanProgress: LibraryScanner.Progress?
    var errorMessage: String?

    @ObservationIgnored private var accessedFolder: URL?

    init() {
        do {
            database = try AppDatabase.makeShared()
        } catch {
            fatalError("No se pudo abrir la base de datos de Octava: \(error)")
        }
        library = LibraryStore(database: database)
        player = PlaybackEngine()

        // Cada pista que termina suma una reproducción (la base para estadísticas y, en la fase 5, el scrobbling).
        player.onTrackFinished = { [weak self] track in
            self?.library.markPlayed(track)
        }

        if let folder = FolderAccess.restoreFolder() {
            activate(folder: folder)
        }
        library.reload()
    }

    // MARK: Carpeta de música

    func chooseFolder() {
        guard let folder = FolderAccess.chooseFolder() else { return }
        activate(folder: folder)
        Task { await rescan() }
    }

    private func activate(folder: URL) {
        if let previous = accessedFolder {
            previous.stopAccessingSecurityScopedResource()
        }
        // El acceso se mantiene abierto durante toda la sesión: lo necesitan el escáner y el reproductor.
        _ = folder.startAccessingSecurityScopedResource()
        accessedFolder = folder
        musicFolder = folder
        player.rootURL = folder
    }

    // MARK: Escaneo

    func rescan() async {
        guard let folder = musicFolder, !isScanning else { return }
        isScanning = true
        scanProgress = nil
        defer { isScanning = false }

        let scanner = LibraryScanner(database: database)
        do {
            _ = try await scanner.scan(root: folder) { [weak self] progress in
                Task { @MainActor in self?.scanProgress = progress }
            }
            library.reload()
        } catch {
            errorMessage = "No se pudo escanear la carpeta: \(error.localizedDescription)"
        }
    }

    // MARK: Reproducción

    func play(album: Album, startingAt index: Int = 0) {
        let tracks = library.tracks(for: album)
        guard !tracks.isEmpty else { return }
        player.play(tracks: tracks, startAt: index)
    }

    func playShuffled(album: Album) {
        let tracks = library.tracks(for: album).shuffled()
        guard !tracks.isEmpty else { return }
        player.play(tracks: tracks)
    }

    /// Mezcla básica de toda la colección. El shuffle inteligente (sin artistas seguidos ni repetidos recientes) es de la fase 3.
    func playShuffledLibrary() {
        let tracks = library.allTracks().shuffled()
        guard !tracks.isEmpty else { return }
        player.play(tracks: tracks)
    }
}
