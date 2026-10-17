import SwiftUI

/// Detalle de un disco: carátula, datos, botones, lista de canciones y panel "A continuación".
struct AlbumDetailView: View {
    @Environment(AppModel.self) private var model
    let album: Album

    @State private var tracks: [Track] = []

    private var totalMinutes: Int {
        Int((tracks.reduce(0) { $0 + $1.duration } / 60).rounded())
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    TrackList(tracks: tracks,
                              currentTrackId: model.player.currentTrack?.id,
                              onPlay: { index in model.play(album: album, startingAt: index) },
                              onToggleFavorite: { track in
                                  model.library.toggleFavorite(track)
                              })
                }
                .padding(.horizontal, 32)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity)

            Divider().overlay(Theme.separator)

            QueuePanel()
                .frame(width: 280)
        }
        .background(Theme.surface)
        .navigationTitle(album.title)
        .task(id: model.library.revision) {
            tracks = model.library.tracks(for: album)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 28) {
            AlbumCoverView(album: album, cornerRadius: 8)
                .frame(width: 220, height: 220)
                .shadow(color: Theme.ink.opacity(0.18), radius: 12, y: 8)

            VStack(alignment: .leading, spacing: 0) {
                Text(album.year.map { "ÁLBUM · \(String($0))" } ?? "ÁLBUM")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(Theme.tertiaryText)
                Text(album.title)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .padding(.top, 6)
                Text(album.albumArtist)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.navText)
                    .padding(.top, 8)
                Text("\(tracks.count) canciones · \(totalMinutes) min · MP3")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 10)

                HStack(spacing: 10) {
                    Button {
                        model.play(album: album)
                    } label: {
                        Label("Reproducir disco", systemImage: "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(AccentButtonStyle())

                    Button {
                        model.playShuffled(album: album)
                    } label: {
                        Label("Aleatorio", systemImage: "shuffle")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(OutlineButtonStyle())

                    Button {
                        // Fase 4: editor de tags por lote.
                    } label: {
                        Label("Editar tags", systemImage: "pencil")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(OutlineButtonStyle())
                    .disabled(true)
                    .help("La edición de tags llega en la fase 4")
                }
                .padding(.top, 20)
            }
        }
    }
}

/// Lista de canciones de un disco. Doble clic en una fila reproduce desde ahí.
struct TrackList: View {
    let tracks: [Track]
    let currentTrackId: Int64?
    let onPlay: (Int) -> Void
    let onToggleFavorite: (Track) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("#").frame(width: 40, alignment: .trailing)
                Text("TÍTULO").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12)
                Text("ESCUCHAS").frame(width: 90, alignment: .trailing).padding(.trailing, 12)
                Color.clear.frame(width: 40)
                Text("DURACIÓN").frame(width: 72, alignment: .trailing).padding(.trailing, 8)
            }
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.tertiaryText)
            .padding(.bottom, 10)

            Divider().overlay(Theme.separator)

            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                TrackRow(number: track.trackNumber ?? index + 1,
                         track: track,
                         isCurrent: track.id == currentTrackId,
                         onToggleFavorite: { onToggleFavorite(track) })
                    .onTapGesture(count: 2) { onPlay(index) }
                    .contextMenu {
                        Button("Reproducir desde aquí") { onPlay(index) }
                        Button(track.isFavorite ? "Quitar de favoritos" : "Agregar a favoritos") { onToggleFavorite(track) }
                    }
            }
        }
    }
}

struct TrackRow: View {
    let number: Int
    let track: Track
    let isCurrent: Bool
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if isCurrent {
                    PlayingBars()
                } else {
                    Text(String(number))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            .frame(width: 40, alignment: .trailing)

            Text(track.title)
                .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? Theme.accentText : Theme.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)

            Text(String(track.playCount))
                .font(Theme.mono(12))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 90, alignment: .trailing)
                .padding(.trailing, 12)

            Button(action: onToggleFavorite) {
                Image(systemName: track.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 13))
                    .foregroundStyle(track.isFavorite ? Theme.accent : Theme.mutedIcon)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 40)
            .accessibilityLabel(track.isFavorite ? "Quitar de favoritos" : "Agregar a favoritos")

            Text(formatDuration(track.duration))
                .font(Theme.mono(12))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 72, alignment: .trailing)
                .padding(.trailing, 8)
        }
        .frame(height: 40)
        .background(isCurrent ? Theme.accentTint : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}

/// Panel lateral con lo que viene en la cola.
struct QueuePanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let upcoming = Array(model.player.queue.upcoming.prefix(8))
        let remaining = model.player.queue.upcoming.count - upcoming.count

        VStack(alignment: .leading, spacing: 14) {
            Text("A continuación")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.ink)

            if upcoming.isEmpty {
                Text("La cola está vacía. Reproduce un disco o una mezcla aleatoria.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(upcoming.enumerated()), id: \.offset) { _, track in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(track.title)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                Text(track.artist)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.secondaryText)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Text(formatDuration(track.duration))
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.tertiaryText)
                        }
                        .padding(.vertical, 6)
                    }
                }
                if remaining > 0 {
                    Text("y \(remaining) canciones más")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            Spacer()
            // Fase 2: interruptor "Al terminar el disco, seguir con una mezcla aleatoria" y edición de la cola.
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.queuePanel)
    }
}
