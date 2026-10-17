import AppKit
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
    /// El escaneo en curso lleva más de un momento: recién ahí se muestra el aviso (los escaneos
    /// incrementales de la vigilancia de carpeta suelen durar menos de un segundo y no deben parpadear).
    private(set) var showsScanProgress = false
    var errorMessage: String?

    /// Al terminar la cola, seguir con una mezcla aleatoria de la colección.
    var continueWithMix: Bool {
        didSet { UserDefaults.standard.set(continueWithMix, forKey: SettingsKey.continueWithMix) }
    }

    /// Tamaño de las mezclas aleatorias (el shuffle inteligente con filtros llega en la fase 3).
    static let mixSize = 300

    @ObservationIgnored private var accessedFolder: URL?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    @ObservationIgnored private var folderWatcher: FolderWatcher?
    @ObservationIgnored private var pendingRescanTask: Task<Void, Never>?
    @ObservationIgnored private var rescanRequestedDuringScan = false

    private enum SettingsKey {
        static let continueWithMix = "continueWithMix"
        static let repeatMode = "repeatMode"
        static let normalization = "normalization"
        static let volume = "volume"
    }

    init() {
        do {
            database = try AppDatabase.makeShared()
        } catch {
            fatalError("No se pudo abrir la base de datos de Octava: \(error)")
        }
        library = LibraryStore(database: database)
        player = PlaybackEngine()

        let defaults = UserDefaults.standard
        continueWithMix = defaults.bool(forKey: SettingsKey.continueWithMix)
        player.repeatMode = RepeatMode(rawValue: defaults.string(forKey: SettingsKey.repeatMode) ?? "") ?? .off
        player.normalization = NormalizationMode(rawValue: defaults.string(forKey: SettingsKey.normalization) ?? "") ?? .auto
        if defaults.object(forKey: SettingsKey.volume) != nil {
            player.setVolume(defaults.float(forKey: SettingsKey.volume))
        }

        player.onTrackFinished = { [weak self] track in
            self?.library.markPlayed(track)
        }
        player.onQueueFinished = { [weak self] in
            self?.continuationTracks()
        }
        player.onStateChanged = { [weak self] in
            self?.savePlaybackState()
        }
        player.artworkProvider = { [weak self] track in
            guard let path = self?.library.album(id: track.albumId)?.coverCachePath else { return nil }
            return NSImage(contentsOfFile: path)
        }

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.savePlaybackState() }
        }

        if let folder = FolderAccess.restoreFolder() {
            activate(folder: folder)
        }
        library.reload()
        restorePlaybackState()

        // Escaneo incremental al abrir: solo relee lo nuevo o modificado.
        if musicFolder != nil {
            Task { await rescan() }
        }
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

        // Vigilar la carpeta: los cambios hechos fuera de la app (discos nuevos, borrados, tags editados
        // en otro programa) se incorporan solos con un escaneo incremental.
        folderWatcher?.stop()
        folderWatcher = FolderWatcher(url: folder) { [weak self] in
            MainActor.assumeIsolated { self?.folderDidChange() }
        }
    }

    /// Cambio detectado en la carpeta: esperar a que se calme (copiar un disco genera muchos eventos) y re-escanear.
    private func folderDidChange() {
        pendingRescanTask?.cancel()
        pendingRescanTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.rescan()
        }
    }

    // MARK: Escaneo

    func rescan() async {
        guard let folder = musicFolder else { return }
        guard !isScanning else {
            // Llegaron cambios durante un escaneo: repetir al terminar.
            rescanRequestedDuringScan = true
            return
        }
        isScanning = true
        scanProgress = nil
        let progressDelay = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.showsScanProgress = true
        }

        let scanner = LibraryScanner(database: database)
        do {
            let summary = try await scanner.scan(root: folder) { [weak self] progress in
                Task { @MainActor in self?.scanProgress = progress }
            }
            if summary.added + summary.updated + summary.removed > 0 || library.albums.isEmpty {
                library.reload()
            }
        } catch {
            errorMessage = "No se pudo escanear la carpeta: \(error.localizedDescription)"
        }

        progressDelay.cancel()
        showsScanProgress = false
        isScanning = false

        if rescanRequestedDuringScan {
            rescanRequestedDuringScan = false
            await rescan()
        }
    }

    // MARK: Reproducción

    func play(album: Album, startingAt index: Int = 0) {
        let tracks = library.tracks(for: album)
        guard !tracks.isEmpty else { return }
        player.play(tracks: tracks, startAt: index, source: .album)
    }

    /// Reproduce una lista de canciones (tablas de canciones, favoritos, género, búsqueda) desde una posición.
    func play(tracks: [Track], startingAt index: Int = 0) {
        guard !tracks.isEmpty else { return }
        player.play(tracks: tracks, startAt: index, source: .mix)
    }

    func playShuffled(tracks: [Track]) {
        let mix = Array(tracks.shuffled().prefix(Self.mixSize))
        guard !mix.isEmpty else { return }
        player.play(tracks: mix, source: .mix)
    }

    /// Discografía de un artista, disco por disco (la ganancia de disco se respeta en modo automático).
    func play(artist name: String) {
        let tracks = library.tracks(byArtist: name)
        guard !tracks.isEmpty else { return }
        player.play(tracks: tracks, source: .album)
    }

    func playShuffled(album: Album) {
        let tracks = library.tracks(for: album).shuffled()
        guard !tracks.isEmpty else { return }
        player.play(tracks: tracks, source: .mix)
    }

    /// Mezcla básica de la colección. El shuffle inteligente (sin artistas seguidos ni repetidos recientes) es de la fase 3.
    func playShuffledLibrary() {
        let tracks = Array(library.allTracks().shuffled().prefix(Self.mixSize))
        guard !tracks.isEmpty else { return }
        player.play(tracks: tracks, source: .mix)
    }

    func playNext(_ tracks: [Track]) {
        player.playNext(tracks)
    }

    func addToQueue(_ tracks: [Track]) {
        player.addToQueue(tracks)
    }

    func playNext(album: Album) {
        player.playNext(library.tracks(for: album))
    }

    func addToQueue(album: Album) {
        player.addToQueue(library.tracks(for: album))
    }

    // MARK: Ajustes de reproducción

    func setRepeatMode(_ mode: RepeatMode) {
        player.repeatMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: SettingsKey.repeatMode)
    }

    func cycleRepeatMode() {
        setRepeatMode(player.repeatMode.next)
    }

    func setNormalization(_ mode: NormalizationMode) {
        player.normalization = mode
        UserDefaults.standard.set(mode.rawValue, forKey: SettingsKey.normalization)
    }

    func setVolume(_ value: Float) {
        player.setVolume(value)
        UserDefaults.standard.set(player.volume, forKey: SettingsKey.volume)
    }

    /// Canciones para seguir cuando termina la cola, si el ajuste está activo.
    private func continuationTracks() -> [Track]? {
        guard continueWithMix else { return nil }
        let justPlayedAlbum = player.currentTrack?.albumId
        let candidates = library.allTracks().filter { $0.albumId == nil || $0.albumId != justPlayedAlbum }
        let mix = Array(candidates.shuffled().prefix(Self.mixSize))
        return mix.isEmpty ? nil : mix
    }

    // MARK: Reanudar al abrir

    private func savePlaybackState() {
        let queue = player.queue
        guard let index = queue.currentIndex, !queue.isEmpty else {
            database.savePlaybackSnapshot(nil)
            return
        }
        let ids = queue.items.compactMap { $0.track.id }
        guard ids.count == queue.items.count else { return }
        database.savePlaybackSnapshot(PlaybackSnapshot(trackIDs: ids,
                                                       currentIndex: index,
                                                       position: player.currentTime,
                                                       source: player.source.rawValue))
    }

    private func restorePlaybackState() {
        guard musicFolder != nil, let snapshot = database.loadPlaybackSnapshot() else { return }
        let found = library.tracks(ids: snapshot.trackIDs)
        guard !found.isEmpty else { return }

        // Si se borraron pistas, mantener la actual si sigue existiendo.
        let currentID = snapshot.trackIDs.indices.contains(snapshot.currentIndex) ? snapshot.trackIDs[snapshot.currentIndex] : nil
        var index = min(snapshot.currentIndex, found.count - 1)
        var position = snapshot.position
        if found.count != snapshot.trackIDs.count {
            if let currentID, let newIndex = found.firstIndex(where: { $0.id == currentID }) {
                index = newIndex
            } else {
                position = 0
            }
        }
        player.prepare(tracks: found,
                       index: index,
                       position: position,
                       source: QueueSource(rawValue: snapshot.source) ?? .mix)
    }
}
