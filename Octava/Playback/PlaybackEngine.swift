import AVFoundation
import Observation

/// Motor de reproducción con AVAudioEngine + AVAudioPlayerNode.
///
/// Fase 0: reproducción secuencial de la cola (la pista siguiente se programa al terminar la actual).
/// Fase 2: gapless real (programar la pista siguiente antes de que termine la actual),
/// normalización ReplayGain, teclas multimedia y Centro de Control (MPNowPlayingInfoCenter).
@MainActor
@Observable
final class PlaybackEngine {
    private(set) var queue = PlayQueue()
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    var lastError: String?

    private(set) var volume: Float = 0.8

    var currentTrack: Track? { queue.current }
    var duration: TimeInterval { currentTrack?.duration ?? 0 }

    /// Carpeta raíz de la colección (las pistas guardan rutas relativas).
    @ObservationIgnored var rootURL: URL?
    /// Se llama cuando una pista termina de sonar completa (estadísticas; en la fase 5, scrobble).
    @ObservationIgnored var onTrackFinished: ((Track) -> Void)?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private var currentFile: AVAudioFile?
    @ObservationIgnored private var startFrame: AVAudioFramePosition = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var timer: Timer?

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)
        engine.mainMixerNode.outputVolume = 0.8
    }

    // MARK: Control

    func setVolume(_ value: Float) {
        volume = min(1, max(0, value))
        engine.mainMixerNode.outputVolume = volume
    }

    func play(tracks: [Track], startAt index: Int = 0) {
        queue.replace(with: tracks, startAt: index)
        startCurrent()
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
            isPlaying = false
            stopTimer()
        } else if currentFile != nil {
            do {
                try startEngineIfNeeded()
                player.play()
                isPlaying = true
                startTimer()
            } catch {
                lastError = "No se pudo reanudar el audio: \(error.localizedDescription)"
            }
        } else if queue.current != nil {
            startCurrent()
        }
    }

    func next() {
        guard queue.advance() != nil else {
            stop()
            return
        }
        startCurrent()
    }

    func previous() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard queue.goBack() != nil else { return }
        startCurrent()
    }

    func stop() {
        generation += 1
        player.stop()
        isPlaying = false
        currentTime = 0
        currentFile = nil
        stopTimer()
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
        let token = generation
        player.stop()
        startFrame = frame
        player.scheduleSegment(file,
                               startingFrame: frame,
                               frameCount: AVAudioFrameCount(file.length - frame),
                               at: nil,
                               completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.handleCompletion(token: token) }
        }
        if isPlaying {
            player.play()
        }
        currentTime = time
    }

    // MARK: Interno

    private func startCurrent() {
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
            let token = generation

            player.stop()
            // Reconectar con el formato del archivo; el mezclador convierte la frecuencia de muestreo si hace falta.
            engine.disconnectNodeOutput(player)
            engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)

            currentFile = file
            startFrame = 0
            player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in self?.handleCompletion(token: token) }
            }
            try startEngineIfNeeded()
            player.play()
            isPlaying = true
            currentTime = 0
            lastError = nil
            startTimer()
        } catch {
            lastError = "No se pudo abrir \(track.title): \(error.localizedDescription)"
            // Saltar a la siguiente pista en vez de detener todo.
            if queue.advance() != nil {
                startCurrent()
            } else {
                stop()
            }
        }
    }

    private func handleCompletion(token: Int) {
        // Ignorar finales provocados por stop(), seek() o un cambio de pista.
        guard token == generation else { return }
        if let finished = queue.current {
            onTrackFinished?(finished)
        }
        if queue.advance() != nil {
            startCurrent()
        } else {
            stop()
        }
    }

    private func startEngineIfNeeded() throws {
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateCurrentTime()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateCurrentTime() {
        guard isPlaying,
              let file = currentFile,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else { return }
        let seconds = Double(startFrame + playerTime.sampleTime) / file.processingFormat.sampleRate
        currentTime = min(max(0, seconds), duration > 0 ? duration : seconds)
    }
}

/// Regla de scrobble de Last.fm: la pista dura más de 30 s y se escuchó la mitad o 4 minutos, lo que ocurra primero.
/// Devuelve el segundo en que la pista califica, o nil si nunca califica.
func scrobbleThreshold(forDuration duration: TimeInterval) -> TimeInterval? {
    guard duration > 30 else { return nil }
    return min(duration / 2, 240)
}
