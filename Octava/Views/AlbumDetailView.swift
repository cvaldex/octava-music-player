import SwiftUI

/// Detalle de un disco: carátula, datos, botones y lista de canciones.
struct AlbumDetailView: View {
    @Environment(AppModel.self) private var model
    let album: Album

    @State private var tracks: [Track] = []

    private var totalMinutes: Int {
        Int((tracks.reduce(0) { $0 + $1.duration } / 60).rounded())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                TrackList(tracks: tracks,
                          currentTrackId: model.player.currentTrack?.id,
                          onPlay: { index in model.play(album: album, startingAt: index) },
                          onPlayNext: { track in model.playNext([track]) },
                          onAddToQueue: { track in model.addToQueue([track]) },
                          onToggleFavorite: { track in
                              model.library.toggleFavorite(track)
                          })
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .navigationTitle(album.title)
        .task(id: model.library.revision) {
            tracks = model.library.tracks(for: album)
        }
    }

    /// El encabezado se adapta al ancho disponible (por ejemplo, con el panel de la cola abierto):
    /// carátula grande al lado → carátula chica al lado con botones de solo ícono → carátula arriba.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 28) {
                cover(size: 220)
                info(compact: false)
                    .frame(minWidth: 300, idealWidth: 560, alignment: .leading)
            }
            HStack(alignment: .bottom, spacing: 20) {
                cover(size: 160)
                info(compact: true)
                    .frame(minWidth: 260, idealWidth: 360, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 20) {
                cover(size: 160)
                info(compact: true)
            }
        }
    }

    private func cover(size: CGFloat) -> some View {
        AlbumCoverView(album: album, cornerRadius: 8)
            .frame(width: size, height: size)
            .shadow(color: Theme.ink.opacity(0.18), radius: 12, y: 8)
    }

    private func info(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(album.year.map { "ÁLBUM · \(String($0))" } ?? "ÁLBUM")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(Theme.tertiaryText)
            Text(album.title)
                .font(.system(size: compact ? 30 : 40, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .padding(.top, 6)
            Text(album.albumArtist)
                .font(.system(size: 17))
                .foregroundStyle(Theme.navText)
                .lineLimit(1)
                .padding(.top, 8)
            Text(["\(tracks.count) canciones", "\(totalMinutes) min", "MP3", LibraryIndex.bitrateLabel(for: tracks)]
                    .compactMap { $0 }
                    .joined(separator: " · "))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 10)

            actionButtons(compact: compact)
                .padding(.top, 20)
        }
    }

    /// Botones del disco. En modo compacto los secundarios muestran solo el ícono (con descripción emergente).
    private func actionButtons(compact: Bool) -> some View {
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
                secondaryLabel("Aleatorio", systemImage: "shuffle", compact: compact)
            }
            .buttonStyle(OutlineButtonStyle())
            .help("Reproducir el disco en orden aleatorio")

            Menu {
                Button("Reproducir a continuación") { model.playNext(album: album) }
                Button("Agregar al final de la cola") { model.addToQueue(album: album) }
            } label: {
                secondaryLabel("Cola", systemImage: "text.line.first.and.arrowtriangle.forward", compact: compact)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.horizontal, compact ? 10 : 16)
            .frame(height: 34)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.controlBorder))
            .help("Agregar el disco a la cola")

            Button {
                // Fase 4: editor de tags por lote.
            } label: {
                secondaryLabel("Editar tags", systemImage: "pencil", compact: compact)
            }
            .buttonStyle(OutlineButtonStyle())
            .disabled(true)
            .help("La edición de tags llega en la fase 4")
        }
        .fixedSize()
    }

    @ViewBuilder
    private func secondaryLabel(_ title: String, systemImage: String, compact: Bool) -> some View {
        if compact {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .accessibilityLabel(title)
        } else {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13))
        }
    }
}

/// Lista de canciones de un disco.
/// Clic: selecciona · doble clic o Enter: reproduce desde ahí · ↑/↓: mueve la selección.
struct TrackList: View {
    let tracks: [Track]
    let currentTrackId: Int64?
    let onPlay: (Int) -> Void
    let onPlayNext: (Track) -> Void
    let onAddToQueue: (Track) -> Void
    let onToggleFavorite: (Track) -> Void

    @State private var selectedID: Int64?
    @FocusState private var isFocused: Bool

    private var selectedIndex: Int? {
        tracks.firstIndex { $0.id != nil && $0.id == selectedID }
    }

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
                         isSelected: track.id != nil && track.id == selectedID,
                         onToggleFavorite: { onToggleFavorite(track) })
                    .onTapGesture(count: 2) { onPlay(index) }
                    .simultaneousGesture(TapGesture().onEnded {
                        selectedID = track.id
                        isFocused = true
                    })
                    .contextMenu {
                        Button("Reproducir desde aquí") { onPlay(index) }
                        Button("Reproducir a continuación") { onPlayNext(track) }
                        Button("Agregar al final de la cola") { onAddToQueue(track) }
                        Divider()
                        Button(track.isFavorite ? "Quitar de favoritos" : "Agregar a favoritos") { onToggleFavorite(track) }
                    }
            }
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { moveSelection(by: -1) }
        .onKeyPress(.downArrow) { moveSelection(by: 1) }
        .onKeyPress(.return) {
            guard let index = selectedIndex else { return .ignored }
            onPlay(index)
            return .handled
        }
    }

    private func moveSelection(by delta: Int) -> KeyPress.Result {
        guard !tracks.isEmpty else { return .ignored }
        let next: Int
        if let index = selectedIndex {
            next = min(max(0, index + delta), tracks.count - 1)
        } else {
            next = delta > 0 ? 0 : tracks.count - 1
        }
        selectedID = tracks[next].id
        return .handled
    }
}

struct TrackRow: View {
    private var rowBackground: Color {
        if isCurrent { return Theme.accentTint }
        if isSelected { return Theme.selection }
        return .clear
    }

    let number: Int
    let track: Track
    let isCurrent: Bool
    var isSelected = false
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
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            if isSelected && isCurrent {
                RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
