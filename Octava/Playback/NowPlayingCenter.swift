import AppKit
import MediaPlayer

/// Integración con macOS: canción en el Centro de Control / widget "Ahora suena"
/// y teclas multimedia (▶︎ ⏭ ⏮) a través de MPRemoteCommandCenter.
@MainActor
final class NowPlayingCenter {
    struct Handlers {
        var play: () -> Void
        var pause: () -> Void
        var toggle: () -> Void
        var next: () -> Void
        var previous: () -> Void
        var stop: () -> Void
        var seek: (TimeInterval) -> Void
    }

    private let handlers: Handlers
    private var artworkTrackID: Int64?
    private var artwork: MPMediaItemArtwork?

    init(handlers: Handlers) {
        self.handlers = handlers
        registerCommands()
    }

    private func registerCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.handlers.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.handlers.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.handlers.toggle() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.handlers.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.handlers.previous() }
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.handlers.stop() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self?.handlers.seek(position) }
            return .success
        }

        // Sin funciones que la app aún no tiene.
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.changeRepeatModeCommand.isEnabled = false
        center.changeShuffleModeCommand.isEnabled = false
    }

    /// Publica el estado actual. Llamar en cambios de pista, play/pausa y saltos de posición;
    /// el sistema extrapola el tiempo transcurrido a partir de la velocidad.
    func update(track: Track?, elapsed: TimeInterval, duration: TimeInterval, isPlaying: Bool, artworkImage: () -> NSImage?) {
        let info = MPNowPlayingInfoCenter.default()
        guard let track else {
            info.nowPlayingInfo = nil
            info.playbackState = .stopped
            artworkTrackID = nil
            artwork = nil
            return
        }

        var values: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.performer,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        values[MPMediaItemPropertyAlbumArtist] = track.groupingArtist
        if let number = track.trackNumber { values[MPMediaItemPropertyAlbumTrackNumber] = number }

        // La carátula se crea una vez por canción.
        if artworkTrackID != track.id {
            artworkTrackID = track.id
            if let image = artworkImage() {
                artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            } else {
                artwork = nil
            }
        }
        if let artwork { values[MPMediaItemPropertyArtwork] = artwork }

        info.nowPlayingInfo = values
        info.playbackState = isPlaying ? .playing : .paused
    }
}
