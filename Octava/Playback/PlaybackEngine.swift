import AppKit
import AVFoundation
import Observation

/// Motor de reproducción: AVAudioEngine con  AVAudioPlayerNode → AVAudioUnitEQ (ganancia ReplayGain) → mezclador.
///
/// Gapless: unos segundos antes de que termine la pista actual se programa la siguiente en el mismo
/// AVAudioPlayerNode, de modo que suena sin silencio entre ambas (requiere el mismo formato de audio,
/// que es lo normal dentro de un disco). Cada tramo programado tiene un id: el callback de fin de tramo
/// solo se atiende si corresponde al tramo actual y a la "generación" vigente (ver `generation`).
@MainActor
@Observable
final class PlaybackEngine {
    private(set) var queue = PlayQueue()
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var volume: Float = 0.8
    private(set) var source: QueueSource = .mix
    /// Entrada de la cola tras la cual se detiene la reproducción ("Detener al terminar esta canción").
    /// Va atada a esa entrada: si se cambia de canción a mano, deja de aplicar.
    private(set) var stopAfterEntryID: UUID?
    var lastError: String?

    var repeatMode: RepeatMode = .off {
        didSet { if oldValue != repeatMode { queueDidChange() } }
    }

    var normalization: NormalizationMode = .auto {
        didSet { applyGain() }
    }

    var currentTrack: Track? { queue.current }
    var duration: TimeInterval { currentTrack?.duration ?? 0 }

    /// Carpeta raíz de la colección (las pistas guardan rutas relativas).
    @ObservationIgnored var rootURL: URL?
    /// Una pista terminó de sonar completa (estadísticas; en la fase 5, scrobble).
    @ObservationIgnored var onTrackFinished: ((Track) -> Void)?
    /// La cola terminó. Puede devolver más canciones para seguir (mezcla aleatoria).
    @ObservationIgnored var onQueueFinished: (() -> [Track]?)?
    /// Algo cambió y conviene guardar el estado para reanudar al abrir.
    @ObservationIgnored var onStateChanged: (() -> Void)?
    /// Cada cuarto de segundo mientras suena (para el scrobbler).
    @ObservationIgnored var onTick: (() -> Void)?
    /// Carátula de una pista para el Centro de Control.
    @ObservationIgnored var artworkProvider: ((Track) -> NSImage?)?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private let gainUnit = AVAudioUnitEQ(numberOfBands: 0)
    @ObservationIgnored private var nowPlaying: NowPlayingCenter?

    @ObservationIgnored private var currentFile: AVAudioFile?
    @ObservationIgnored private var connectedFormat: AVAudioFormat?
    /// Cuadro del archivo desde el que empezó el tramo actual (distinto de 0 tras un salto).
    @ObservationIgnored private var startFrame: AVAudioFramePosition = 0
    /// Tiempo del reproductor (en cuadros) en que empezó el tramo actual; crece con cada transición gapless.
    @ObservationIgnored private var baseSampleTime: AVAudioFramePosition = 0
    @ObservationIgnored private var currentSegmentID = 0
    @ObservationIgnored private var currentSegmentFrames: AVAudioFramePosition = 0
    @ObservationIgnored private var segmentCounter = 0
    /// Se incrementa con cada stop/seek/cambio de pista para invalidar callbacks pendientes.
    @ObservationIgnored private var generation = 0
    /// La pista está cargada (al reanudar o tras un salto en pausa) pero aún no programada en el reproductor.
    @ObservationIgnored private var needsSchedule = false
    @ObservationIgnored private var prescheduled: Prescheduled?
    @ObservationIgnored private var prescheduleAttemptedSegment = -1
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private var configurationObserver: NSObjectProtocol?

    /// Segundos antes del final en que se programa la pista siguiente.
    private static let prescheduleLeadTime: TimeInterval = 10

    private struct Prescheduled {
        let entryID: UUID
        let file: AVAudioFile
        let segmentID: Int
        let frames: AVAudioFramePosition
    }

    init() {
        engine.attach(player)
        engine.attach(gainUnit)
        engine.connect(player, to: gainUnit, format: nil)
        engine.connect(gainUnit, to: engine.mainMixerNode, format: nil)
        engine.mainMixerNode.outputVolume = volume

        nowPlaying = NowPlayingCenter(handlers: .init(
            play: { [weak self] in self?.resume() },
            pause: { [weak self] in self?.pause() },
            toggle: { [weak self] in self?.togglePlayPause() },
            next: { [weak self] in self?.next() },
            previous: { [weak self] in self?.previous() },
            stop: { [weak self] in self?.stopPlayback() },
            seek: { [weak self] in self?.seek(to: $0) }
        ))

        // La salida de audio cambió (audífonos, otro dispositivo, cambio de frecuencia): el motor se detiene solo.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recoverStoppedEngine() }
        }
    }

    // MARK: Reproducción

    func play(tracks: [Track], startAt index: Int = 0, source: QueueSource) {
        queue.replace(with: tracks, startAt: index)
        self.source = source
        consecutiveFailures = 0
        startCurrent(autoplay: true)
    }

    /// Carga una cola sin reproducir, en una posición (para reanudar al abrir la app).
    func prepare(tracks: [Track], index: Int, position: TimeInterval, source: QueueSource) {
        queue.replace(with: tracks, startAt: index)
        self.source = source
        startCurrent(autoplay: false, at: position)
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func pause() {
        guard isPlaying else { return }
        player.pause()
        isPlaying = false
        stopTimer()
        updateCurrentTimeFromPlayer()
        publishNowPlaying()
        onStateChanged?()
    }

    func resume() {
        guard !isPlaying else { return }
        guard currentFile != nil else {
            if queue.current != nil { startCurrent(autoplay: true) }
            return
        }
        if needsSchedule {
            scheduleCurrentSegment(from: startFrame)
        }
        guard startPlayer() else { return }
        publishNowPlaying()
    }

    func next() {
        consecutiveFailures = 0
        if let index = queue.indexAfterCurrent(repeatMode: repeatMode, automatic: false) {
            queue.select(index)
            startCurrent(autoplay: true)
        } else {
            finishQueue()
        }
    }

    func previous() {
        consecutiveFailures = 0
        if currentTime > 3 {
            seek(to: 0)
        } else if queue.goBack() {
            startCurrent(autoplay: true)
        } else {
            seek(to: 0)
        }
    }

    func seek(to time: TimeInterval) {
        guard let file = currentFile else { return }
        let sampleRate = file.processingFormat.sampleRate
        let frame = AVAudioFramePosition(max(0, time) * sampleRate)
        guard frame < file.length else {
            next()
            return
        }
        generation += 1
        player.stop()
        prescheduled = nil
        if isPlaying {
            scheduleCurrentSegment(from: frame)
            startPlayer()
        } else {
            startFrame = frame
            needsSchedule = true
        }
        currentTime = Double(frame) / sampleRate
        publishNowPlaying()
        onStateChanged?()
    }

    func setVolume(_ value: Float) {
        volume = min(1, max(0, value))
        engine.mainMixerNode.outputVolume = volume
    }

    /// ¿Se detendrá al terminar la canción actual?
    var stopsAfterCurrent: Bool {
        stopAfterEntryID != nil && stopAfterEntryID == queue.currentEntry?.id
    }

    /// Activa o desactiva "Detener al terminar esta canción".
    func setStopAfterCurrent(_ enabled: Bool) {
        guard let entry = queue.currentEntry else {
            stopAfterEntryID = nil
            return
        }
        stopAfterEntryID = enabled ? entry.id : nil
        if enabled, prescheduled != nil {
            // La siguiente ya estaba programada (gapless): descartarla reprogramando la actual desde donde va.
            updateCurrentTimeFromPlayer()
            seek(to: currentTime)
            prescheduleAttemptedSegment = -1
        }
        onStateChanged?()
    }

    func toggleStopAfterCurrent() {
        setStopAfterCurrent(!stopsAfterCurrent)
    }

    /// Botón Stop: detiene el audio y deja la canción actual al principio, en pausa. La cola se mantiene.
    func stopPlayback() {
        stopAfterEntryID = nil
        guard currentFile != nil else { return }
        generation += 1
        player.stop()
        prescheduled = nil
        isPlaying = false
        stopTimer()
        startFrame = 0
        needsSchedule = true
        currentTime = 0
        publishNowPlaying()
        onStateChanged?()
    }

    func stop() {
        generation += 1
        player.stop()
        isPlaying = false
        currentTime = 0
        currentFile = nil
        prescheduled = nil
        needsSchedule = false
        stopTimer()
        publishNowPlaying()
    }

    // MARK: Edición de la cola

    func playNext(_ tracks: [Track]) {
        let wasEmpty = queue.isEmpty
        queue.playNext(tracks)
        if wasEmpty { startCurrent(autoplay: true) } else { queueDidChange() }
    }

    func addToQueue(_ tracks: [Track]) {
        let wasEmpty = queue.isEmpty
        queue.append(tracks)
        if wasEmpty { startCurrent(autoplay: true) } else { queueDidChange() }
    }

    func jump(to entryID: UUID) {
        guard let index = queue.index(ofEntry: entryID) else { return }
        queue.select(index)
        consecutiveFailures = 0
        startCurrent(autoplay: true)
    }

    func removeEntry(_ entryID: UUID) {
        queue.remove(entryID: entryID)
        queueDidChange()
    }

    func removeUpcoming(atOffsets offsets: IndexSet) {
        queue.removeUpcoming(atOffsets: offsets)
        queueDidChange()
    }

    func moveUpcoming(fromOffsets source: IndexSet, toOffset destination: Int) {
        queue.moveUpcoming(fromOffsets: source, toOffset: destination)
        queueDidChange()
    }

    func clearUpcoming() {
        queue.clearUpcoming()
        queueDidChange()
    }

    /// Actualiza los datos de las canciones de la cola (títulos, carátula…) sin cortar el audio.
    func refreshTracks(_ lookup: (Int64) -> Track?) {
        if queue.refreshTracks(lookup) {
            publishNowPlaying()
        }
    }

    /// Descarta historial antiguo de la cola. No afecta a la pista actual ni a la siguiente ya programada.
    func trimHistory(keeping: Int) {
        queue.trimHistory(keeping: keeping)
    }

    // MARK: Interno: carga y programación

    private func startCurrent(autoplay: Bool, at position: TimeInterval = 0) {
        guard let track = queue.current else {
            stop()
            return
        }
        guard let root = rootURL else {
            lastError = "No hay carpeta de música seleccionada."
            return
        }
        let url = root.appendingPathComponent(track.relativePath)

        do {
            let file = try AVAudioFile(forReading: url)
            generation += 1
            player.stop()
            prescheduled = nil
            connect(format: file.processingFormat)
            currentFile = file

            let sampleRate = file.processingFormat.sampleRate
            let frame = min(max(0, AVAudioFramePosition(position * sampleRate)), max(0, file.length - 1))
            if autoplay {
                scheduleCurrentSegment(from: frame)
                startPlayer()
            } else {
                startFrame = frame
                needsSchedule = true
                isPlaying = false
                stopTimer()
            }
            currentTime = Double(frame) / sampleRate
            consecutiveFailures = 0
            lastError = nil
            applyGain()
            publishNowPlaying()
            onStateChanged?()
        } catch {
            lastError = "No se pudo abrir “\(track.title)”: \(error.localizedDescription)"
            consecutiveFailures += 1
            // Saltar a la siguiente (sin repetir, para no entrar en un bucle si fallan todas).
            if consecutiveFailures < queue.items.count, queue.advance() != nil {
                startCurrent(autoplay: autoplay)
            } else {
                consecutiveFailures = 0
                stop()
            }
        }
    }

    /// Programa la pista actual desde un cuadro. El reproductor debe estar detenido.
    private func scheduleCurrentSegment(from frame: AVAudioFramePosition) {
        guard let file = currentFile else { return }
        let frames = max(0, file.length - frame)
        segmentCounter += 1
        let segmentID = segmentCounter
        let token = generation
        player.scheduleSegment(file,
                               startingFrame: frame,
                               frameCount: AVAudioFrameCount(frames),
                               at: nil,
                               completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.segmentFinished(segmentID, token: token) }
        }
        currentSegmentID = segmentID
        currentSegmentFrames = frames
        startFrame = frame
        baseSampleTime = 0
        needsSchedule = false
    }

    /// Fin de un tramo programado.
    private func segmentFinished(_ segmentID: Int, token: Int) {
        guard token == generation, segmentID == currentSegmentID else { return }
        if let finished = queue.current {
            onTrackFinished?(finished)
        }

        // "Detener al terminar esta canción": pasar a la siguiente, pero en pausa y al principio.
        if stopsAfterCurrent {
            stopAfterEntryID = nil
            prescheduled = nil
            if let index = queue.indexAfterCurrent(repeatMode: repeatMode, automatic: true) {
                queue.select(index)
            }
            startCurrent(autoplay: false)
            return
        }

        // Transición gapless: la siguiente ya está sonando.
        if let next = prescheduled, let index = queue.index(ofEntry: next.entryID) {
            queue.select(index)
            baseSampleTime += currentSegmentFrames
            startFrame = 0
            currentFile = next.file
            currentSegmentID = next.segmentID
            currentSegmentFrames = next.frames
            prescheduled = nil
            currentTime = 0
            applyGain()
            publishNowPlaying()
            onStateChanged?()
            return
        }

        prescheduled = nil
        if let index = queue.indexAfterCurrent(repeatMode: repeatMode, automatic: true) {
            queue.select(index)
            startCurrent(autoplay: true)
        } else {
            finishQueue()
        }
    }

    /// Se acabó la cola: seguir con lo que proponga la app (mezcla) o volver al principio en pausa.
    private func finishQueue() {
        if let more = onQueueFinished?(), !more.isEmpty {
            play(tracks: more, source: .mix)
            return
        }
        guard !queue.isEmpty else {
            stop()
            return
        }
        queue.rewind()
        startCurrent(autoplay: false)
    }

    /// Programa la siguiente pista unos segundos antes del final (gapless).
    private func prescheduleNextIfNeeded() {
        guard isPlaying,
              !stopsAfterCurrent,
              prescheduled == nil,
              prescheduleAttemptedSegment != currentSegmentID,
              let file = currentFile,
              let format = connectedFormat,
              let root = rootURL else { return }

        let remaining = Double(file.length) / file.processingFormat.sampleRate - currentTime
        guard remaining <= Self.prescheduleLeadTime else { return }
        prescheduleAttemptedSegment = currentSegmentID

        guard let index = queue.indexAfterCurrent(repeatMode: repeatMode, automatic: true) else { return }
        let entry = queue.items[index]
        guard let nextFile = try? AVAudioFile(forReading: root.appendingPathComponent(entry.track.relativePath)),
              Self.formatsMatch(nextFile.processingFormat, format) else {
            // Formato distinto: la transición será normal (con un corte mínimo).
            return
        }

        segmentCounter += 1
        let segmentID = segmentCounter
        let token = generation
        player.scheduleFile(nextFile, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.segmentFinished(segmentID, token: token) }
        }
        prescheduled = Prescheduled(entryID: entry.id, file: nextFile, segmentID: segmentID, frames: nextFile.length)
    }

    /// Tras editar la cola o cambiar la repetición: si la pista ya programada dejó de ser la siguiente,
    /// se reprograma la actual desde donde va (descarta la programada).
    private func queueDidChange() {
        if let scheduled = prescheduled {
            let plannedID = queue.indexAfterCurrent(repeatMode: repeatMode, automatic: true).map { queue.items[$0].id }
            if plannedID != scheduled.entryID {
                updateCurrentTimeFromPlayer()
                seek(to: currentTime)
                prescheduleAttemptedSegment = -1
            }
        }
        onStateChanged?()
    }

    /// Conecta los nodos con el formato del archivo. Si cambia el formato (otra frecuencia de muestreo o canales),
    /// hay que detener el motor antes: reconectar con el motor encendido lo deja detenido sin aviso.
    private func connect(format: AVAudioFormat) {
        if let connectedFormat, Self.formatsMatch(connectedFormat, format) { return }
        if engine.isRunning {
            engine.stop()
        }
        engine.disconnectNodeOutput(player)
        engine.disconnectNodeOutput(gainUnit)
        engine.connect(player, to: gainUnit, format: format)
        engine.connect(gainUnit, to: engine.mainMixerNode, format: format)
        connectedFormat = format
        engine.prepare()
    }

    /// Arranca el reproductor asegurándose de que el motor esté encendido.
    /// Nunca se llama a `player.play()` con el motor apagado: AVAudioEngine lanza una excepción que cierra la app.
    @discardableResult
    private func startPlayer() -> Bool {
        do {
            try startEngineIfNeeded()
        } catch {
            lastError = "No se pudo iniciar el audio: \(error.localizedDescription)"
            isPlaying = false
            stopTimer()
            publishNowPlaying()
            return false
        }
        player.play()
        isPlaying = true
        startTimer()
        return true
    }

    /// El motor se detuvo por su cuenta (cambio de salida de audio): reprogramar la pista desde donde iba
    /// y seguir sonando si estaba sonando.
    private func recoverStoppedEngine() {
        guard let file = currentFile else { return }
        let wasPlaying = isPlaying
        generation += 1
        player.stop()
        prescheduled = nil
        prescheduleAttemptedSegment = -1
        isPlaying = false
        stopTimer()
        let sampleRate = file.processingFormat.sampleRate
        startFrame = min(max(0, AVAudioFramePosition(currentTime * sampleRate)), max(0, file.length - 1))
        needsSchedule = true
        if wasPlaying {
            resume()
        } else {
            publishNowPlaying()
        }
    }

    private static func formatsMatch(_ a: AVAudioFormat, _ b: AVAudioFormat) -> Bool {
        a.sampleRate == b.sampleRate && a.channelCount == b.channelCount
    }

    private func applyGain() {
        gainUnit.globalGain = Float(ReplayGain.gain(for: currentTrack, mode: normalization, source: source))
    }

    private func startEngineIfNeeded() throws {
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    private func publishNowPlaying() {
        let track = currentTrack
        nowPlaying?.update(track: track,
                           elapsed: currentTime,
                           duration: duration,
                           isPlaying: isPlaying,
                           artworkImage: { [artworkProvider] in track.flatMap { artworkProvider?($0) } })
    }

    // MARK: Reloj

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        // Red de seguridad: si el motor se detuvo mientras "sonaba", recuperarlo.
        if isPlaying && !engine.isRunning {
            recoverStoppedEngine()
            return
        }
        updateCurrentTimeFromPlayer()
        prescheduleNextIfNeeded()
        onTick?()
        ticks += 1
        if ticks % 40 == 0 { // cada 10 s
            onStateChanged?()
        }
    }

    private func updateCurrentTimeFromPlayer() {
        guard isPlaying,
              let file = currentFile,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else { return }
        let sampleRate = file.processingFormat.sampleRate
        let frames = playerTime.sampleTime - baseSampleTime + startFrame
        let seconds = Double(frames) / sampleRate
        let length = Double(file.length) / sampleRate
        currentTime = min(max(0, seconds), length)
    }
}

/// Regla de scrobble de Last.fm: la pista dura más de 30 s y se escuchó la mitad o 4 minutos, lo que ocurra primero.
/// Devuelve el segundo en que la pista califica, o nil si nunca califica.
func scrobbleThreshold(forDuration duration: TimeInterval) -> TimeInterval? {
    guard duration > 30 else { return nil }
    return min(duration / 2, 240)
}
