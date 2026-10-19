import SwiftUI

/// Detalle de un disco: carátula, datos, botones y lista de canciones.
struct AlbumDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
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
                          },
                          model: model,
                          navigator: navigator)
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
                Divider()
                AddToPlaylistMenu(tracks: model.library.tracks(for: album), model: model)
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
                model.editTags(album: album)
            } label: {
                secondaryLabel("Editar tags", systemImage: "pencil", compact: compact)
            }
            .buttonStyle(OutlineButtonStyle())
            .disabled(model.isSavingTags)
            .help("Editar los tags de todo el disco")
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
/// Clic: selecciona (⌘ suma o quita, ⇧ selecciona un rango) · doble clic o Enter: reproduce desde ahí ·
/// ↑/↓: mueve la selección · clic derecho: selecciona y abre el menú · arrastrar: lleva las canciones a la cola.
struct TrackList: View {
    let tracks: [Track]
    let currentTrackId: Int64?
    let onPlay: (Int) -> Void
    let onPlayNext: (Track) -> Void
    let onAddToQueue: (Track) -> Void
    let onToggleFavorite: (Track) -> Void
    /// Para los menús (se pasa explícito; ver nota de TrackTable).
    let model: AppModel
    var navigator: Navigator?

    @State private var selection = Set<Int64>()
    @State private var anchorIndex: Int?
    @State private var hoveredID: Int64?
    @State private var rightClick = RightClickWatcher()
    @FocusState private var isFocused: Bool

    /// Índice de la última fila seleccionada (para el teclado).
    private var focusIndex: Int? {
        if let anchorIndex, tracks.indices.contains(anchorIndex) { return anchorIndex }
        return tracks.firstIndex { $0.id.map(selection.contains) ?? false }
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
                         isSelected: track.id.map(selection.contains) ?? false,
                         onToggleFavorite: { onToggleFavorite(track) })
                    .onTapGesture(count: 2) { onPlay(index) }
                    .simultaneousGesture(TapGesture().onEnded { click(index) })
                    .onHover { inside in
                        if inside { hoveredID = track.id } else if hoveredID == track.id { hoveredID = nil }
                    }
                    .onDrag { TrackDrag.provider(for: targets(for: track)) }
                    .contextMenu {
                        let count = targets(for: track).count
                        if count == 1 {
                            Button("Reproducir desde aquí") { onPlay(index) }
                        }
                        TrackActionsMenu(tracks: { targets(for: track) }, model: model, navigator: navigator, count: count)
                    }
            }
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { moveSelection(by: -1) }
        .onKeyPress(.downArrow) { moveSelection(by: 1) }
        .onKeyPress(.return) {
            guard let index = focusIndex else { return .ignored }
            onPlay(index)
            return .handled
        }
        .onAppear {
            rightClick.onRightClick = { [self] in
                // Clic derecho sobre una fila que no está seleccionada: pasa a ser la selección (gris).
                guard let id = hoveredID, !selection.contains(id) else { return }
                selection = [id]
                anchorIndex = tracks.firstIndex { $0.id == id }
            }
            rightClick.start()
        }
        .onDisappear { rightClick.stop() }
    }

    /// Las canciones sobre las que actúa el menú o el arrastre: la selección si incluye la fila; si no, solo la fila.
    private func targets(for track: Track) -> [Track] {
        guard let id = track.id, selection.contains(id), selection.count > 1 else { return [track] }
        return tracks.filter { $0.id.map(selection.contains) ?? false }
    }

    private func click(_ index: Int) {
        guard let id = tracks[index].id else { return }
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            anchorIndex = index
        } else if flags.contains(.shift), let anchor = anchorIndex {
            let range = min(anchor, index)...max(anchor, index)
            selection = Set(tracks[range].compactMap(\.id))
        } else {
            selection = [id]
            anchorIndex = index
        }
        isFocused = true
    }

    private func moveSelection(by delta: Int) -> KeyPress.Result {
        guard !tracks.isEmpty else { return .ignored }
        let next: Int
        if let index = focusIndex {
            next = min(max(0, index + delta), tracks.count - 1)
        } else {
            next = delta > 0 ? 0 : tracks.count - 1
        }
        selection = tracks[next].id.map { [$0] } ?? []
        anchorIndex = next
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

            // En compilaciones (o canciones con invitados) se muestra también quién la interpreta.
            HStack(spacing: 6) {
                Text(track.title)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Theme.accentText : Theme.ink)
                    .lineLimit(1)
                if track.performer != track.groupingArtist {
                    Text("· \(track.performer)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }
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
