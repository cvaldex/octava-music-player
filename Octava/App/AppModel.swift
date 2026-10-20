import UniformTypeIdentifiers
import AppKit
import Foundation
import Observation

/// Estado global de la app: base de datos, biblioteca, reproductor y carpeta de música.
@MainActor
@Observable
final class AppModel {
    let database: AppDatabase
    let library: LibraryStore
    let playlists: PlaylistStore
    let player: PlaybackEngine
    let scrobbler: Scrobbler

    private(set) var musicFolder: URL?
    private(set) var isScanning = false
    private(set) var scanProgress: LibraryScanner.Progress?
    /// El escaneo en curso lleva más de un momento: recién ahí se muestra el aviso (los escaneos
    /// incrementales de la vigilancia de carpeta suelen durar menos de un segundo y no deben parpadear).
    private(set) var showsScanProgress = false
    var errorMessage: String?
    /// La carpeta de música no está disponible (disco desconectado, permiso perdido). La biblioteca se conserva.
    private(set) var folderUnavailable = false
    /// Canciones que faltan en la carpeta y no se quitaron porque eran demasiadas: se pide confirmación.
    private(set) var withheldMissingCount = 0
    /// Pedido de mostrar el disco de la canción actual (⌘L); la vista raíz lo observa.
    private(set) var revealCurrentRequest = 0
    /// Lista recién creada que la vista raíz debe abrir (por ejemplo, al importar).
    private(set) var showPlaylistRequest: Int64?

    /// Al terminar la cola, seguir con una mezcla aleatoria de la colección.
    var continueWithMix: Bool {
        didSet { UserDefaults.standard.set(continueWithMix, forKey: SettingsKey.continueWithMix) }
    }

    /// Mezcla activa: mientras exista, la cola se rellena sola para tener siempre
    /// `MixBuilder.targetLength` canciones por delante, con las mismas reglas.
    private(set) var activeMix: MixRule? {
        didSet { saveActiveMix() }
    }

    /// Muestra la ventana para crear una mezcla con filtros.
    var showsMixBuilder = false

    /// Canciones abiertas en el editor de tags (la hoja se muestra mientras exista).
    var tagEditTarget: TagEditTarget?
    /// Se están escribiendo tags (o deshaciendo una edición).
    private(set) var isSavingTags = false
    /// Hay una edición de tags que se puede deshacer.
    private(set) var canUndoTagEdit = false

    /// Canciones ya reproducidas que se conservan en la cola (para "anterior"); las más antiguas se descartan
    /// para que una mezcla que se rellena durante horas no crezca sin límite.
    static let queueHistoryLength = 50

    @ObservationIgnored private var accessedFolder: URL?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    @ObservationIgnored private var folderWatcher: FolderWatcher?
    @ObservationIgnored private var pendingRescanTask: Task<Void, Never>?
    @ObservationIgnored private var rescanRequestedDuringScan = false
    @ObservationIgnored private var isRefillingMix = false
    @ObservationIgnored private var mountObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var keyMonitor: Any?
    /// Faltantes que el usuario decidió mantener (no se vuelve a preguntar por la misma cantidad).
    @ObservationIgnored private var keptMissingCount = 0

    private enum SettingsKey {
        static let continueWithMix = "continueWithMix"
        static let repeatMode = "repeatMode"
        static let normalization = "normalization"
        static let volume = "volume"
        static let activeMix = "activeMix"
    }

    /// La app corre como anfitrión de los tests: no debe tocar la biblioteca real.
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init() {
        ScanSelfTest.runIfRequested()
        // Una sola Octava a la vez: dos copias (por ejemplo la de Aplicaciones y la de Xcode) comparten la base de
        // datos y, escaneando al mismo tiempo, la desordenan.
        if !Self.isRunningTests {
            Self.exitIfAnotherInstanceIsRunning()
        }
        do {
            database = Self.isRunningTests ? try AppDatabase.makeEmpty() : try AppDatabase.makeShared()
        } catch {
            fatalError("No se pudo abrir la base de datos de Octava: \(error)")
        }
        library = LibraryStore(database: database)
        playlists = PlaylistStore(database: database)
        player = PlaybackEngine()
        scrobbler = Scrobbler(database: database)

        let defaults = UserDefaults.standard
        continueWithMix = defaults.bool(forKey: SettingsKey.continueWithMix)
        player.repeatMode = RepeatMode(rawValue: defaults.string(forKey: SettingsKey.repeatMode) ?? "") ?? .off
        player.normalization = NormalizationMode(rawValue: defaults.string(forKey: SettingsKey.normalization) ?? "") ?? .auto
        if defaults.object(forKey: SettingsKey.volume) != nil {
            player.setVolume(defaults.float(forKey: SettingsKey.volume))
        }
        if let data = defaults.data(forKey: SettingsKey.activeMix) {
            activeMix = try? JSONDecoder().decode(MixRule.self, from: data)
        }

        player.onTrackFinished = { [weak self] track in
            self?.library.markPlayed(track)
            self?.scrobbler.trackFinished()
        }
        player.onQueueFinished = { [weak self] in
            self?.continuationTracks()
        }
        player.onStateChanged = { [weak self] in
            self?.updateScrobbler()
            self?.refillMixIfNeeded()
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

        if !Self.isRunningTests, let folder = FolderAccess.restoreFolder() {
            activate(folder: folder)
        }
        library.reload()
        playlists.reload()
        canUndoTagEdit = database.hasTagEdits
        restorePlaybackState()

        player.onTick = { [weak self] in
            self?.updateScrobbler()
        }
        library.onFavoriteChanged = { [weak self] track, loved in
            self?.scrobbler.setLoved(loved, track: track)
        }
        guard !Self.isRunningTests else { return }
        observeVolumes()
        installKeyMonitor()

        // Scrobbles que quedaron pendientes de otra sesión.
        Task { [scrobbler] in await scrobbler.flush() }

        // Escaneo incremental al abrir: solo relee lo nuevo o modificado.
        if musicFolder != nil {
            Task { await rescan() }
        }
    }

    // MARK: Una sola instancia

    private static func exitIfAnotherInstanceIsRunning() {
        let me = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier ?? "local.octava.Octava"
        guard let other = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { $0.processIdentifier != me && !$0.isTerminated }) else { return }

        let alert = NSAlert()
        alert.messageText = "Octava ya está abierta"
        alert.informativeText = "Hay otra copia de Octava funcionando\(other.bundleURL.map { " (\($0.path))" } ?? ""). "
            + "Dos copias a la vez pueden desordenar la biblioteca, así que esta se cerrará. "
            + "Si quieres usar esta copia, cierra primero la otra."
        alert.addButton(withTitle: "Ir a la Octava abierta")
        alert.runModal()
        other.activate()
        exit(0)
    }

    // MARK: Carpeta de música

    func chooseFolder() {
        guard let folder = FolderAccess.chooseFolder(current: musicFolder) else { return }
        guard folder.standardizedFileURL != musicFolder?.standardizedFileURL else { return }
        // Al cambiar de carpeta se vuelve a escanear: las canciones conocidas (misma ruta, o mismo título, artista y
        // duración) conservan sus estadísticas; si faltan muchas de la carpeta anterior, se pide confirmación.
        withheldMissingCount = 0
        keptMissingCount = 0
        activate(folder: folder)
        Task { await rescan() }
    }

    /// Pedido del usuario (fase 7): preguntar una vez, al abrir, por la carpeta de música, para poder elegir otra.
    /// Si se cancela, se mantiene la actual.
    private static let folderPromptKey = "askedForMusicFolderOnLaunchV1"

    func promptForFolderOnLaunchIfNeeded() {
        // Al correr los tests la app es solo el anfitrión: nada de diálogos.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.folderPromptKey) else { return }
        defaults.set(true, forKey: Self.folderPromptKey)
        guard musicFolder != nil else { return } // Sin carpeta ya se muestra la bienvenida.
        chooseFolder()
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

    func rescan(allowMassRemoval: Bool = false) async {
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
            let summary = try await scanner.scan(root: folder, allowMassRemoval: allowMassRemoval) { [weak self] progress in
                Task { @MainActor in self?.scanProgress = progress }
            }
            folderUnavailable = false
            withheldMissingCount = summary.withheldMissing == keptMissingCount ? 0 : summary.withheldMissing
            if summary.added + summary.updated + summary.removed + summary.moved > 0 || library.albums.isEmpty {
                library.reload()
                // Los datos de la cola (títulos, discos) se actualizan sin cortar el audio.
                let library = self.library
                player.refreshTracks { library.tracks(ids: [$0]).first }
            }
        } catch LibraryScanner.ScanError.folderUnavailable {
            folderUnavailable = true
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

    /// Confirmado por el usuario: quitar de la biblioteca las canciones que ya no están en la carpeta.
    func removeMissingTracks() async {
        withheldMissingCount = 0
        await rescan(allowMassRemoval: true)
    }

    /// Mantenerlas (por ejemplo, porque falta un disco que se reconectará): no volver a preguntar por las mismas.
    func keepMissingTracks() {
        keptMissingCount = withheldMissingCount
        withheldMissingCount = 0
    }

    /// Al conectar o desconectar un disco, revisar la carpeta (vuelve sola cuando se reconecta el disco).
    private func observeVolumes() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            mountObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.musicFolder != nil else { return }
                    Task { await self.rescan() }
                }
            })
        }
    }

    // MARK: Reproducción

    func play(album: Album, startingAt index: Int = 0) {
        let tracks = library.tracks(for: album)
        guard !tracks.isEmpty else { return }
        activeMix = nil
        player.play(tracks: tracks, startAt: index, source: .album)
    }

    /// Reproduce una lista de canciones (tablas, listas guardadas, búsqueda) desde una posición.
    func play(tracks: [Track], startingAt index: Int = 0) {
        guard !tracks.isEmpty else { return }
        activeMix = nil
        player.play(tracks: tracks, startAt: index, source: .mix)
    }

    /// Mezcla fija de un conjunto de canciones (una lista guardada, las más escuchadas), con shuffle inteligente.
    func playShuffled(tracks: [Track]) {
        let mix = MixBuilder.build(from: tracks, count: tracks.count)
        guard !mix.isEmpty else { return }
        activeMix = nil
        player.play(tracks: mix, source: .mix)
    }

    /// Discografía de un artista, disco por disco (la ganancia de disco se respeta en modo automático).
    func play(artist name: String) {
        let tracks = library.tracks(byArtist: name)
        guard !tracks.isEmpty else { return }
        activeMix = nil
        player.play(tracks: tracks, source: .album)
    }

    func playShuffled(album: Album) {
        let tracks = MixBuilder.spread(library.tracks(for: album).shuffled())
        guard !tracks.isEmpty else { return }
        activeMix = nil
        player.play(tracks: tracks, source: .mix)
    }

    /// Mezcla de toda la colección (se rellena sola).
    func playShuffledLibrary() {
        startMix(MixRule())
    }

    func playNext(_ tracks: [Track]) {
        player.playNext(tracks)
    }

    func addToQueue(_ tracks: [Track]) {
        player.addToQueue(tracks)
    }

    /// Canciones soltadas en la cola: se insertan en esa posición de "A continuación".
    func insertInQueue(trackIDs: [Int64], at offset: Int) {
        player.insertUpcoming(library.tracks(ids: trackIDs), at: offset)
    }

    func playNext(album: Album) {
        player.playNext(library.tracks(for: album))
    }

    func addToQueue(album: Album) {
        player.addToQueue(library.tracks(for: album))
    }

    // MARK: Mezclas

    /// Canciones disponibles para una regla (para mostrar el conteo en la ventana de mezclas).
    func mixCandidates(for rule: MixRule) -> [Track] {
        MixBuilder.candidates(for: rule, in: library.tracks, favoriteIDs: library.favoriteIDs)
    }

    /// Empieza una mezcla que se rellena sola.
    func startMix(_ rule: MixRule) {
        let tracks = MixBuilder.build(from: mixCandidates(for: rule), count: MixBuilder.targetLength)
        guard !tracks.isEmpty else {
            errorMessage = "No hay canciones que calcen con esa mezcla."
            return
        }
        activeMix = rule
        player.play(tracks: tracks, source: .mix)
    }

    /// Deja de rellenar la cola (lo que ya está en la cola se mantiene).
    func stopMix() {
        activeMix = nil
    }

    /// Mantiene `MixBuilder.targetLength` canciones por delante mientras haya una mezcla activa.
    private func refillMixIfNeeded() {
        guard let rule = activeMix, !isRefillingMix else { return }
        isRefillingMix = true
        defer { isRefillingMix = false }

        player.trimHistory(keeping: Self.queueHistoryLength)
        let queue = player.queue
        let missing = MixBuilder.targetLength - queue.upcoming.count
        guard missing > 0, !queue.isEmpty else { return }

        // No repetir lo que ya está por sonar (ni la actual).
        var excluded = Set(queue.upcoming.compactMap(\.track.id))
        if let currentID = queue.current?.id { excluded.insert(currentID) }
        let previousArtist = queue.upcoming.last?.track.performer ?? queue.current?.performer
        let more = MixBuilder.build(from: mixCandidates(for: rule), count: missing,
                                    excluding: excluded, previousArtist: previousArtist)
        if !more.isEmpty {
            player.addToQueue(more)
        }
    }

    private func saveActiveMix() {
        let defaults = UserDefaults.standard
        if let activeMix, let data = try? JSONEncoder().encode(activeMix) {
            defaults.set(data, forKey: SettingsKey.activeMix)
        } else {
            defaults.removeObject(forKey: SettingsKey.activeMix)
        }
    }

    // MARK: Listas guardadas

    func tracks(inPlaylist id: Int64) -> [Track] {
        library.tracks(ids: playlists.trackIDs(for: id))
    }

    /// Crea una lista con un nombre y canciones. Devuelve su id.
    @discardableResult
    func createPlaylist(named name: String, tracks: [Track] = []) -> Int64? {
        playlists.create(name: name, trackIDs: tracks.compactMap(\.id))
    }

    /// Pide un nombre y crea la lista. Devuelve su id, o nil si se canceló.
    @discardableResult
    func createPlaylistPrompting(with tracks: [Track] = [], suggestedName: String = "Nueva lista") -> Int64? {
        guard let name = TextPrompt.ask(title: "Nueva lista",
                                        message: tracks.isEmpty ? "Ponle un nombre a la lista." : "Se creará con \(countLabel(tracks.count, singular: "canción", plural: "canciones")).",
                                        defaultValue: suggestedName,
                                        confirmTitle: "Crear") else { return nil }
        return createPlaylist(named: name, tracks: tracks)
    }

    func addToPlaylist(_ id: Int64, tracks: [Track]) {
        playlists.append(trackIDs: tracks.compactMap(\.id), to: id)
    }

    /// Guarda la cola completa (lo que ya sonó en esta sesión, la actual y lo que viene) como lista.
    @discardableResult
    func saveQueueAsPlaylist() -> Int64? {
        let tracks = player.queue.items.map(\.track)
        guard !tracks.isEmpty else { return nil }
        let suggested = activeMix?.title ?? player.queue.current.map { "\($0.performer) y más" } ?? "Mi lista"
        return createPlaylistPrompting(with: tracks, suggestedName: suggested)
    }

    /// Importa una lista .xspf, .m3u o .m3u8 de otro programa: busca sus canciones en la biblioteca,
    /// pide el nombre y abre la lista creada. Avisa qué canciones no se encontraron.
    func importPlaylist() {
        let panel = NSOpenPanel()
        panel.title = "Importar lista"
        panel.message = "Elige una lista de reproducción (.xspf, .m3u o .m3u8)."
        panel.prompt = "Importar"
        panel.allowedContentTypes = PlaylistImport.fileExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "No se pudo leer “\(url.lastPathComponent)”."
            return
        }
        let parsed = PlaylistImport.parse(data: data, fileExtension: url.pathExtension)
        let match = PlaylistImport.match(parsed.entries, tracks: library.tracks, musicFolder: musicFolder,
                                         playlistFolder: url.deletingLastPathComponent())
        guard !match.trackIDs.isEmpty else {
            errorMessage = parsed.entries.isEmpty
                ? "“\(url.lastPathComponent)” no tiene canciones."
                : "Ninguna de las \(parsed.entries.count) canciones de “\(url.lastPathComponent)” está en tu biblioteca."
            return
        }

        let suggested = parsed.title ?? url.deletingPathExtension().lastPathComponent
        let found = countLabel(match.trackIDs.count, singular: "canción", plural: "canciones")
        let message = match.missing.isEmpty
            ? "Se encontraron las \(found) en tu biblioteca."
            : "Se encontraron \(found) de \(parsed.entries.count). Las demás no están en tu biblioteca."
        guard let name = TextPrompt.ask(title: "Importar lista", message: message,
                                        defaultValue: suggested, confirmTitle: "Crear lista"),
              let id = playlists.create(name: name, trackIDs: match.trackIDs) else { return }
        showPlaylistRequest = id

        if !match.missing.isEmpty {
            let names = match.missing.prefix(15).map { entry -> String in
                let label = [entry.creator, entry.title].compactMap { $0 }.joined(separator: " – ")
                if !label.isEmpty { return label }
                return entry.location.map { ($0 as NSString).lastPathComponent } ?? "Sin nombre"
            }
            let more = match.missing.count > 15 ? "\n… y \(match.missing.count - 15) más." : ""
            TextPrompt.inform(title: "\(countLabel(match.missing.count, singular: "canción no se encontró", plural: "canciones no se encontraron"))",
                              message: names.joined(separator: "\n") + more)
        }
    }

    func renamePlaylistPrompting(_ playlist: Playlist) {
        guard let name = TextPrompt.ask(title: "Renombrar lista", message: nil,
                                        defaultValue: playlist.name, confirmTitle: "Renombrar"),
              let id = playlist.id else { return }
        playlists.rename(id, to: name)
    }

    /// Pide confirmación y borra la lista. Devuelve true si se borró.
    @discardableResult
    func deletePlaylistConfirming(_ playlist: Playlist) -> Bool {
        guard let id = playlist.id,
              TextPrompt.confirm(title: "¿Eliminar la lista “\(playlist.name)”?",
                                 message: "Las canciones no se borran de tu colección.",
                                 confirmTitle: "Eliminar") else { return false }
        playlists.delete(id)
        return true
    }

    // MARK: Edición de tags

    /// Abre el editor de tags con estas canciones.
    func editTags(_ tracks: [Track]) {
        let tracks = tracks.filter { $0.id != nil }
        guard !tracks.isEmpty, musicFolder != nil else { return }
        tagEditTarget = TagEditTarget(tracks: tracks)
    }

    func editTags(album: Album) {
        editTags(library.tracks(for: album))
    }

    /// Escribe los cambios en los MP3 y, si funciona, actualiza la base (relee esos archivos).
    /// Devuelve false si algún archivo no se pudo escribir (el mensaje queda en `errorMessage`).
    @discardableResult
    func saveTagEdit(_ changes: TagChanges, to tracks: [Track]) async -> Bool {
        guard !changes.isEmpty, !isSavingTags else { return true }
        let jobs = fileJobs(for: tracks).map { ($0.trackID, $0.url, changes) }
        let result = await writeTags(jobs)

        if !result.done.isEmpty {
            do {
                try database.recordTagEdits(result.done.map { ($0.trackID, $0.previous) }, at: Date())
            } catch {
                print("Octava: no se pudo guardar el historial de tags: \(error)")
            }
            canUndoTagEdit = database.hasTagEdits
            await reread(trackIDs: result.done.map(\.trackID), coverChanged: changes.artwork != nil)
        }
        return report(failures: result.failed, total: jobs.count)
    }

    /// Pide confirmación y deshace el último lote de ediciones.
    func undoLastTagEditConfirming() async {
        let count = database.latestTagEditBatch().count
        guard count > 0 else {
            canUndoTagEdit = false
            return
        }
        guard TextPrompt.confirm(title: "¿Deshacer la última edición de tags?",
                                 message: "Se volverán a escribir los valores anteriores en \(countLabel(count, singular: "archivo MP3", plural: "archivos MP3")).",
                                 confirmTitle: "Deshacer") else { return }
        await undoLastTagEdit()
    }

    /// Deshace el último lote de ediciones: vuelve a escribir los valores anteriores.
    func undoLastTagEdit() async {
        guard !isSavingTags else { return }
        let batch = database.latestTagEditBatch()
        guard !batch.isEmpty else {
            canUndoTagEdit = false
            return
        }
        let byTrack = Dictionary(batch.map { ($0.trackId, $0.previous) }, uniquingKeysWith: { first, _ in first })
        let tracks = library.tracks(ids: batch.map(\.trackId))
        let jobs = fileJobs(for: tracks).compactMap { job in byTrack[job.trackID].map { (job.trackID, job.url, $0) } }
        let result = await writeTags(jobs)

        // Se borra del historial lo que se deshizo (y lo que ya no existe en la colección).
        let undone = Set(result.done.map(\.trackID))
        let missing = Set(batch.map(\.trackId)).subtracting(tracks.compactMap(\.id))
        try? database.deleteTagEdits(batch.filter { undone.contains($0.trackId) || missing.contains($0.trackId) }.map(\.id))
        canUndoTagEdit = database.hasTagEdits

        if !result.done.isEmpty {
            let coverChanged = batch.contains { $0.previous.artwork != nil }
            await reread(trackIDs: Array(undone), coverChanged: coverChanged)
        }
        report(failures: result.failed, total: jobs.count)
    }

    private func fileJobs(for tracks: [Track]) -> [(trackID: Int64, url: URL)] {
        guard let root = musicFolder else { return [] }
        return tracks.compactMap { track in
            track.id.map { ($0, root.appendingPathComponent(track.relativePath)) }
        }
    }

    /// Escribe en segundo plano (un disco son decenas de MB). Cada archivo es independiente: si uno falla, los demás siguen.
    private func writeTags(_ jobs: [(Int64, URL, TagChanges)]) async
        -> (done: [(trackID: Int64, previous: TagChanges)], failed: [String]) {
        isSavingTags = true
        defer { isSavingTags = false }
        return await Task.detached(priority: .userInitiated) {
            var done: [(trackID: Int64, previous: TagChanges)] = []
            var failed: [String] = []
            for (trackID, url, changes) in jobs {
                do {
                    let previous = try ID3TagWriter.apply(changes, toFileAt: url)
                    done.append((trackID, previous))
                } catch {
                    failed.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            return (done, failed)
        }.value
    }

    /// Hace que el escáner relea esos archivos: así se reagrupan los discos y se actualizan carátulas y años.
    private func reread(trackIDs: [Int64], coverChanged: Bool) async {
        do {
            try database.markForReread(trackIDs: trackIDs, clearingCovers: coverChanged)
        } catch {
            print("Octava: no se pudo marcar para releer: \(error)")
        }
        await rescan()
    }

    @discardableResult
    private func report(failures: [String], total: Int) -> Bool {
        guard !failures.isEmpty else { return true }
        let list = failures.prefix(5).joined(separator: "\n")
        let more = failures.count > 5 ? "\n… y \(failures.count - 5) más." : ""
        errorMessage = "No se pudieron escribir \(failures.count) de \(total) archivos:\n\(list)\(more)"
        return false
    }

    // MARK: Listas dinámicas

    /// Las 100 canciones con más reproducciones.
    var mostPlayedTracks: [Track] {
        Array(library.tracks
            .filter { $0.playCount > 0 }
            .sorted { ($0.playCount, $0.lastPlayedAt ?? .distantPast) > ($1.playCount, $1.lastPlayedAt ?? .distantPast) }
            .prefix(100))
    }

    /// Canciones no escuchadas en más de 6 meses (o nunca), de la más olvidada a la menos.
    var forgottenTracks: [Track] {
        let now = Date()
        return library.tracks
            .filter { MixBuilder.isForgotten($0, now: now) }
            .sorted { ($0.lastPlayedAt ?? .distantPast) < ($1.lastPlayedAt ?? .distantPast) }
    }

    // MARK: Atajos

    /// Avanza o retrocede unos segundos en la canción actual.
    func skip(by seconds: TimeInterval) {
        guard player.currentTrack != nil else { return }
        player.seek(to: max(0, min(player.duration - 1, player.currentTime + seconds)))
    }

    func changeVolume(by delta: Float) {
        setVolume(player.volume + delta)
    }

    /// Muestra el disco de la canción que suena (⌘L).
    func revealCurrentTrack() {
        guard player.currentTrack != nil else { return }
        revealCurrentRequest += 1
    }

    /// Barra espaciadora: reproducir o pausar, salvo que se esté escribiendo en un campo o haya una hoja abierta.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, Self.isPlainSpace(event), Self.spaceIsFree(in: event.window) else { return event }
                self.player.togglePlayPause()
                return nil
            }
        }
    }

    private static func isPlainSpace(_ event: NSEvent) -> Bool {
        event.keyCode == 49 && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
    }

    private static func spaceIsFree(in window: NSWindow?) -> Bool {
        guard let window, window.attachedSheet == nil, window.sheetParent == nil, !window.isModalPanel else { return false }
        // Escribiendo en un campo de texto (búsqueda, editor de tags, nombre de lista): el espacio es un espacio.
        if window.firstResponder is NSText || window.firstResponder is NSTextField { return false }
        // Con el teclado sobre un botón, interruptor o deslizador, el espacio lo activa (acceso con teclado completo).
        if window.firstResponder is NSButton || window.firstResponder is NSSlider
            || window.firstResponder is NSSegmentedControl { return false }
        return window.title != "Ajustes"
    }

    // MARK: Last.fm

    private func updateScrobbler() {
        scrobbler.update(entryID: player.queue.currentEntry?.id,
                         track: player.currentTrack,
                         isPlaying: player.isPlaying,
                         position: player.currentTime)
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

    /// Canciones para seguir cuando termina la cola, si el ajuste está activo: empieza una mezcla de toda la
    /// colección (que se rellena sola), sin el disco que acaba de terminar.
    private func continuationTracks() -> [Track]? {
        guard continueWithMix else { return nil }
        let justPlayedAlbum = player.currentTrack?.albumId
        let candidates = mixCandidates(for: MixRule()).filter { $0.albumId == nil || $0.albumId != justPlayedAlbum }
        let mix = MixBuilder.build(from: candidates, count: MixBuilder.targetLength,
                                   previousArtist: player.currentTrack?.performer)
        guard !mix.isEmpty else { return nil }
        activeMix = MixRule()
        return mix
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

/// Canciones abiertas en el editor de tags.
struct TagEditTarget: Identifiable {
    let id = UUID()
    let tracks: [Track]
}
