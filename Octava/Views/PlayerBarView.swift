import SwiftUI

/// Barra de reproducción inferior: canción actual, controles, progreso con punto de scrobble y volumen.
struct PlayerBarView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showQueue") private var showQueue = true

    var body: some View {
        let player = model.player

        HStack(spacing: 28) {
            nowPlaying(player.currentTrack)
                .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                controls
                SeekBar(current: player.currentTime,
                        duration: player.duration,
                        scrobbleAt: scrobbleThreshold(forDuration: player.duration),
                        onSeek: { player.seek(to: $0) })
                    .frame(maxWidth: 560)
            }
            .frame(minWidth: 340, maxWidth: .infinity)

            trailing
                .frame(minWidth: 220, maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.playerBar)
    }

    @ViewBuilder
    private func nowPlaying(_ track: Track?) -> some View {
        HStack(spacing: 12) {
            if let track, let coverAlbum = album(for: track) {
                AlbumCoverView(album: coverAlbum, cornerRadius: 5)
                    .frame(width: 48, height: 48)
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Theme.control)
                    .frame(width: 48, height: 48)
                    .overlay(Image(systemName: "music.note").foregroundStyle(Theme.mutedIcon))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(track?.title ?? "Nada sonando")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(track == nil ? Theme.secondaryText : Theme.ink)
                    .lineLimit(1)
                if let track {
                    Text("\(track.artist) — \(track.album)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }

            if let track {
                let isFavorite = model.library.isFavorite(track)
                Button {
                    model.library.toggleFavorite(track)
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 15))
                }
                .buttonStyle(IconButtonStyle(tint: isFavorite ? Theme.accent : Theme.secondaryText))
                .accessibilityLabel(isFavorite ? "Quitar de favoritos" : "Agregar a favoritos")
            }
        }
    }

    private var controls: some View {
        let player = model.player
        return HStack(spacing: 14) {
            Button { model.playShuffledLibrary() } label: {
                Image(systemName: "shuffle").font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(IconButtonStyle())
            .help("Mezcla aleatoria de toda la colección")
            .accessibilityLabel("Mezcla aleatoria")

            Button { player.previous() } label: {
                Image(systemName: "backward.end.fill").font(.system(size: 15))
            }
            .buttonStyle(IconButtonStyle(tint: Theme.ink))
            .accessibilityLabel("Anterior")

            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.ink, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(player.currentTrack == nil)
            .accessibilityLabel(player.isPlaying ? "Pausar" : "Reproducir")

            Button { player.next() } label: {
                Image(systemName: "forward.end.fill").font(.system(size: 15))
            }
            .buttonStyle(IconButtonStyle(tint: Theme.ink))
            .accessibilityLabel("Siguiente")

            StopButton(player: player)

            Button { model.cycleRepeatMode() } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 14, weight: player.repeatMode == .off ? .medium : .semibold))
            }
            .buttonStyle(IconButtonStyle(tint: player.repeatMode == .off ? Theme.secondaryText : Theme.accent))
            .help(player.repeatMode.title)
            .accessibilityLabel("Repetir")
            .accessibilityValue(player.repeatMode.title)
        }
    }

    private var trailing: some View {
        let player = model.player
        let threshold = scrobbleThreshold(forDuration: player.duration)
        let remaining = threshold.map { max(0, $0 - player.currentTime) }

        return HStack(spacing: 12) {
            if player.currentTrack != nil, let threshold, let remaining {
                HStack(spacing: 7) {
                    ScrobbleRing(fraction: 1 - remaining / threshold)
                    Text(remaining > 0 ? "scrobble en \(formatDuration(remaining))" : "listo para scrobble")
                        .font(Theme.mono(11))
                }
                .foregroundStyle(Theme.accentText)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Theme.accent.opacity(0.09), in: Capsule())
                .help("El envío a Last.fm llega en la fase 5")
            }

            Button { showQueue.toggle() } label: {
                Image(systemName: "list.bullet").font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(IconButtonStyle(isActive: showQueue))
            .help(showQueue ? "Ocultar la cola" : "Mostrar la cola")
            .accessibilityLabel("Cola de reproducción")

            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
            Slider(value: Binding(get: { player.volume }, set: { model.setVolume($0) }), in: 0...1)
                .frame(width: 90)
                .tint(Theme.ink)
                .accessibilityLabel("Volumen")
        }
    }

    private func album(for track: Track) -> Album? {
        model.library.albums.first { $0.id == track.albumId }
    }
}

/// Anillo que se completa a medida que la pista se acerca al punto de scrobble.
struct ScrobbleRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(Theme.accent.opacity(0.25), lineWidth: 2)
            Circle()
                .trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }
}

/// Barra de progreso arrastrable, con la marca del punto de scrobble.
struct SeekBar: View {
    let current: Double
    let duration: Double
    let scrobbleAt: Double?
    let onSeek: (Double) -> Void

    @State private var dragFraction: Double?

    var body: some View {
        let fraction = dragFraction ?? (duration > 0 ? min(1, current / duration) : 0)

        HStack(spacing: 10) {
            Text(formatDuration(dragFraction.map { $0 * duration } ?? current))
                .frame(width: 40, alignment: .trailing)
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.control).frame(height: 4)
                    Capsule().fill(Theme.ink).frame(width: width * fraction, height: 4)
                    if let scrobbleAt, duration > 0 {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Theme.accent)
                            .frame(width: 2, height: 12)
                            .offset(x: width * (scrobbleAt / duration) - 1)
                            .help("Punto de scrobble")
                    }
                }
                .frame(height: 16)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0, width > 0 else { return }
                            dragFraction = min(1, max(0, value.location.x / width))
                        }
                        .onEnded { value in
                            guard duration > 0, width > 0 else { return }
                            let target = min(1, max(0, value.location.x / width)) * duration
                            dragFraction = nil
                            onSeek(target)
                        }
                )
            }
            .frame(height: 16)
            Text(formatDuration(duration))
                .frame(width: 40, alignment: .leading)
        }
        .font(Theme.mono(11))
        .foregroundStyle(Theme.secondaryText)
        .accessibilityElement()
        .accessibilityLabel("Progreso")
        .accessibilityValue("\(formatDuration(current)) de \(formatDuration(duration))")
    }
}

/// Botón Stop. Clic: detiene y vuelve al principio de la canción (la cola se mantiene).
/// Clic derecho: "Detener al terminar esta canción". Mientras esa opción está activa, el botón se ve terracota
/// con un punto. Recibe el reproductor explícitamente (el menú contextual no hereda bien el entorno).
private struct StopButton: View {
    let player: PlaybackEngine

    var body: some View {
        let stopsAfter = player.stopsAfterCurrent
        Button { player.stopPlayback() } label: {
            Image(systemName: "stop.fill")
                .font(.system(size: 13))
                .overlay(alignment: .topTrailing) {
                    if stopsAfter {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 6, height: 6)
                            .offset(x: 5, y: -4)
                    }
                }
        }
        .buttonStyle(IconButtonStyle(tint: stopsAfter ? Theme.accent : Theme.ink))
        .disabled(player.currentTrack == nil)
        .help(stopsAfter ? "Se detendrá al terminar esta canción (clic derecho para cancelar)"
                         : "Detener (clic derecho: detener al terminar esta canción)")
        .accessibilityLabel("Detener")
        .accessibilityValue(stopsAfter ? "Se detendrá al terminar esta canción" : "")
        .contextMenu {
            Button("Detener ahora") { player.stopPlayback() }
            Toggle("Detener al terminar esta canción",
                   isOn: Binding(get: { player.stopsAfterCurrent }, set: { player.setStopAfterCurrent($0) }))
        }
    }
}
