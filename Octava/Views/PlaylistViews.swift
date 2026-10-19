import SwiftUI

// MARK: - Menú "Agregar a lista"

/// Submenú "Agregar a lista" para menús contextuales: las listas guardadas y "Nueva lista…".
/// Recibe el modelo explícitamente (los menús contextuales no heredan bien el entorno; ver nota de TrackTable).
struct AddToPlaylistMenu: View {
    let tracks: [Track]
    let model: AppModel

    var body: some View {
        Menu("Agregar a lista") {
            Button("Nueva lista…") {
                let suggested = tracks.count == 1 ? tracks[0].title : "Nueva lista"
                model.createPlaylistPrompting(with: tracks, suggestedName: suggested)
            }
            let playlists = model.playlists.playlists
            if !playlists.isEmpty {
                Divider()
                ForEach(playlists) { playlist in
                    Button(playlist.name) {
                        if let id = playlist.id { model.addToPlaylist(id, tracks: tracks) }
                    }
                }
            }
        }
        .disabled(tracks.isEmpty)
    }
}

// MARK: - Lista guardada

/// Una lista guardada: canciones en orden, arrastrar para reordenar, suprimir para quitar.
struct PlaylistView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    let id: Int64
    /// Se llama al borrar la lista (para volver a otra sección de la barra lateral).
    let onDeleted: () -> Void

    @State private var selection = Set<Int>()

    var body: some View {
        // `revision` hace que la vista se vuelva a dibujar cuando cambia el contenido de cualquier lista.
        let _ = model.playlists.revision
        let playlist = model.playlists.playlist(id: id)
        let tracks = model.tracks(inPlaylist: id)
        let currentID = model.player.currentTrack?.id
        let duration = tracks.reduce(0) { $0 + $1.duration }

        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: playlist?.name ?? "Lista",
                       subtitle: tracks.isEmpty ? "Vacía" : "\(countLabel(tracks.count, singular: "canción", plural: "canciones")) · \(formatLongDuration(duration))") {
                Button {
                    model.play(tracks: tracks)
                } label: {
                    Label("Reproducir", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(tracks.isEmpty)

                Button {
                    model.playShuffled(tracks: tracks)
                } label: {
                    Label("Mezclar", systemImage: "shuffle").font(.system(size: 13))
                }
                .buttonStyle(OutlineButtonStyle())
                .disabled(tracks.isEmpty)

                if let playlist {
                    Menu {
                        Button("Renombrar…") { model.renamePlaylistPrompting(playlist) }
                        Button("Eliminar lista…") {
                            if model.deletePlaylistConfirming(playlist) { onDeleted() }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13))
                            .frame(width: 20)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.controlBorder))
                    .help("Más acciones")
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)

            if tracks.isEmpty {
                ContentUnavailableView("Lista vacía",
                                       systemImage: "music.note.list",
                                       description: Text("Agrega canciones con clic derecho → Agregar a lista, desde cualquier tabla, disco o la cola."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                        PlaylistRow(number: index + 1, track: track,
                                    isCurrent: track.id != nil && track.id == currentID,
                                    library: model.library)
                            .tag(index)
                    }
                    .onMove { source, destination in
                        model.playlists.moveItems(fromOffsets: source, toOffset: destination, in: id)
                        selection.removeAll()
                    }
                    .onDelete { offsets in
                        model.playlists.removeItems(atOffsets: offsets, from: id)
                        selection.removeAll()
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 16)
                .contextMenu(forSelectionType: Int.self) { indices in
                    rowMenu(indices: indices, tracks: tracks)
                } primaryAction: { indices in
                    if let first = indices.min() { model.play(tracks: tracks, startingAt: first) }
                }
                .onDeleteCommand {
                    guard !selection.isEmpty else { return }
                    model.playlists.removeItems(atOffsets: IndexSet(selection), from: id)
                    selection.removeAll()
                }
            }
        }
        .background(Theme.surface)
        .navigationTitle(playlist?.name ?? "Lista")
    }

    @ViewBuilder
    private func rowMenu(indices: Set<Int>, tracks: [Track]) -> some View {
        let indices = indices.sorted().filter { tracks.indices.contains($0) }
        let selected = indices.map { tracks[$0] }
        if let first = indices.first {
        Button(indices.count == 1 ? "Reproducir" : "Reproducir desde aquí") { model.play(tracks: tracks, startingAt: first) }
        Button("Reproducir a continuación") { model.playNext(selected) }
        Button("Agregar al final de la cola") { model.addToQueue(selected) }
        AddToPlaylistMenu(tracks: selected, model: model)
        Button(selected.count == 1 ? "Editar tags…" : "Editar tags de \(selected.count) canciones…") {
            model.editTags(selected)
        }
        if selected.count == 1, let track = selected.first, let album = model.library.album(id: track.albumId) {
            Divider()
            Button("Ir al disco") { navigator.show(.album(album)) }
            Button("Ir al artista") { navigator.show(.artist(album.albumArtist)) }
        }
        Divider()
        Button(indices.count == 1 ? "Quitar de la lista" : "Quitar \(indices.count) canciones de la lista") {
            model.playlists.removeItems(atOffsets: IndexSet(indices), from: id)
            selection.removeAll()
        }
        }
    }
}

private struct PlaylistRow: View {
    let number: Int
    let track: Track
    let isCurrent: Bool
    let library: LibraryStore

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.accent)
                } else {
                    Text("\(number)")
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            .frame(width: 30, alignment: .trailing)

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Theme.accentText : Theme.ink)
                    .lineLimit(1)
                Text("\(track.performer) · \(track.album)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            FavoriteToggle(track: track, library: library)
            Text(formatDuration(track.duration))
                .font(Theme.mono(12))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

/// "1 h 12 min" / "42 min"
func formatLongDuration(_ seconds: TimeInterval) -> String {
    let minutes = Int((seconds / 60).rounded())
    if minutes >= 60 {
        return "\(minutes / 60) h \(minutes % 60) min"
    }
    return "\(minutes) min"
}

// MARK: - Listas dinámicas

/// "Más escuchadas": las 100 canciones con más reproducciones.
struct MostPlayedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let tracks = model.mostPlayedTracks
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Más escuchadas", subtitle: "Las \(tracks.count) canciones que más has escuchado") {
                Button {
                    model.play(tracks: tracks)
                } label: {
                    Label("Reproducir", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(tracks.isEmpty)
                Button {
                    model.playShuffled(tracks: tracks)
                } label: {
                    Label("Mezclar", systemImage: "shuffle").font(.system(size: 13))
                }
                .buttonStyle(OutlineButtonStyle())
                .disabled(tracks.isEmpty)
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)

            if tracks.isEmpty {
                ContentUnavailableView("Aún no hay escuchas",
                                       systemImage: "chart.bar",
                                       description: Text("Una canción cuenta como escuchada al pasar la mitad (o 4 minutos)."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TrackTable(tracks: tracks)
            }
        }
        .background(Theme.surface)
    }
}

/// "Hace tiempo sin oír": no escuchadas en más de 6 meses, o nunca.
struct ForgottenView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let tracks = model.forgottenTracks
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Hace tiempo sin oír",
                       subtitle: "\(countLabel(tracks.count, singular: "canción", plural: "canciones")) sin escuchar en 6 meses o más") {
                ShuffleButton { model.startMix(MixRule(source: .forgotten)) }
                    .disabled(tracks.isEmpty)
                    .help("Mezcla que se rellena sola con canciones olvidadas")
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)

            if tracks.isEmpty {
                ContentUnavailableView("Todo al día",
                                       systemImage: "clock.arrow.circlepath",
                                       description: Text("Has escuchado toda tu colección en los últimos 6 meses."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TrackTable(tracks: tracks)
            }
        }
        .background(Theme.surface)
    }
}
