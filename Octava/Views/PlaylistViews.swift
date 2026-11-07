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
    @State private var filter = ""

    var body: some View {
        // `revision` hace que la vista se vuelva a dibujar cuando cambia el contenido de cualquier lista.
        let _ = model.playlists.revision
        let playlist = model.playlists.playlist(id: id)
        let tracks = model.tracks(inPlaylist: id)
        // Con filtro: solo las que calzan, cada una con su posición en la lista completa.
        let shown = Array(tracks.enumerated()).filter { ListFilter.matches($0.element, query: filter) }
        let shownTracks = shown.map(\.element)
        let isFiltering = shown.count != tracks.count
        let currentID = model.player.currentTrack?.id
        let duration = shownTracks.reduce(0) { $0 + $1.duration }

        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: playlist?.name ?? "Lista",
                       subtitle: tracks.isEmpty ? "Vacía" : "\(ListFilter.countLabel(shown: shown.count, total: tracks.count)) · \(formatLongDuration(duration))") {
                Button {
                    model.play(tracks: shownTracks)
                } label: {
                    Label("Reproducir", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(shownTracks.isEmpty)

                Button {
                    model.playShuffled(tracks: shownTracks)
                } label: {
                    Label("Mezclar", systemImage: "shuffle").font(.system(size: 13))
                }
                .buttonStyle(OutlineButtonStyle())
                .disabled(shownTracks.isEmpty)

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

            if !tracks.isEmpty {
                FilterField(text: $filter).padding(.horizontal, 32)
            }

            if tracks.isEmpty {
                ContentUnavailableView("Lista vacía",
                                       systemImage: "music.note.list",
                                       description: Text("Agrega canciones con clic derecho → Agregar a lista, desde cualquier tabla, disco o la cola."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shown.isEmpty {
                NoFilterMatches(query: filter)
            } else {
                List(selection: $selection) {
                    // La etiqueta (tag) es siempre la posición en la lista completa: el menú, quitar y la
                    // selección funcionan igual con o sin filtro.
                    ForEach(shown, id: \.offset) { index, track in
                        PlaylistRow(number: index + 1, track: track,
                                    isCurrent: track.id != nil && track.id == currentID,
                                    library: model.library,
                                    highlight: filter)
                            .tag(index)
                    }
                    // Con filtro no se reordena: no se ven todas las posiciones.
                    .onMove(perform: isFiltering ? nil : { source, destination in
                        model.playlists.moveItems(fromOffsets: source, toOffset: destination, in: id)
                        selection.removeAll()
                    })
                    .onDelete { offsets in
                        model.playlists.removeItems(atOffsets: IndexSet(offsets.map { shown[$0].offset }), from: id)
                        selection.removeAll()
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 16)
                .contextMenu(forSelectionType: Int.self) { indices in
                    rowMenu(indices: indices, tracks: tracks)
                } primaryAction: { indices in
                    guard let first = indices.min() else { return }
                    if isFiltering {
                        // Doble clic con filtro: suenan las filtradas, desde la elegida.
                        model.play(tracks: shownTracks, startingAt: shown.firstIndex { $0.offset == first } ?? 0)
                    } else {
                        model.play(tracks: tracks, startingAt: first)
                    }
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
    var highlight = ""

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
                Text(ListFilter.highlighted(track.title, query: highlight))
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Theme.accentText : Theme.ink)
                    .lineLimit(1)
                Text(ListFilter.highlighted("\(track.performer) · \(track.album)", query: highlight))
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
    @State private var filter = ""

    var body: some View {
        let all = model.mostPlayedTracks
        let tracks = ListFilter.apply(all, query: filter)
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Más escuchadas",
                       subtitle: tracks.count == all.count ? "Las \(all.count) canciones que más has escuchado"
                                                           : ListFilter.countLabel(shown: tracks.count, total: all.count)) {
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

            if !all.isEmpty {
                FilterField(text: $filter).padding(.horizontal, 32)
            }

            if tracks.isEmpty && !filter.isEmpty {
                NoFilterMatches(query: filter)
            } else if tracks.isEmpty {
                ContentUnavailableView("Aún no hay escuchas",
                                       systemImage: "chart.bar",
                                       description: Text("Una canción cuenta como escuchada al pasar la mitad (o 4 minutos)."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TrackTable(tracks: tracks, highlight: filter)
            }
        }
        .background(Theme.surface)
    }
}

/// "Hace tiempo sin oír": no escuchadas en más de 6 meses, o nunca.
struct ForgottenView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ""

    var body: some View {
        let all = model.forgottenTracks
        let tracks = ListFilter.apply(all, query: filter)
        let isFiltering = tracks.count != all.count
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Hace tiempo sin oír",
                       subtitle: "\(ListFilter.countLabel(shown: tracks.count, total: all.count)) sin escuchar en 6 meses o más") {
                ShuffleButton {
                    if isFiltering { model.playShuffled(tracks: tracks) } else { model.startMix(MixRule(source: .forgotten)) }
                }
                .disabled(tracks.isEmpty)
                .help(isFiltering ? "Mezclar las canciones filtradas" : "Mezcla que se rellena sola con canciones olvidadas")
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)

            if !all.isEmpty {
                FilterField(text: $filter).padding(.horizontal, 32)
            }

            if tracks.isEmpty && !filter.isEmpty {
                NoFilterMatches(query: filter)
            } else if tracks.isEmpty {
                ContentUnavailableView("Todo al día",
                                       systemImage: "clock.arrow.circlepath",
                                       description: Text("Has escuchado toda tu colección en los últimos 6 meses."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TrackTable(tracks: tracks, highlight: filter)
            }
        }
        .background(Theme.surface)
    }
}

// MARK: - Canciones cortas

/// Regla de la lista fija "Canciones cortas": más de 30 s (el mínimo para que Last.fm cuente la escucha) y menos
/// de 211 s, sin "07 - Drumless Tracks". Se calcula cada vez desde la biblioteca, así que se actualiza sola.
/// Orden: por fecha de agregado, lo más nuevo al final (y dentro de un mismo momento, por ruta: el orden del disco).
enum ShortSongs {
    static let minimumDuration: TimeInterval = 30
    static let maximumDuration: TimeInterval = 211
    static let excludedFolders = ["07 - Drumless Tracks/"]
    static let ruleDescription = "canciones de más de 30 segundos y menos de 3:31, sin Drumless Tracks"

    static func matches(_ track: Track) -> Bool {
        track.duration > minimumDuration && track.duration < maximumDuration
            && !excludedFolders.contains { track.relativePath.hasPrefix($0) }
    }

    static func tracks(in library: [Track]) -> [Track] {
        library.filter(matches).sorted { a, b in
            let dateA = a.addedAt ?? .distantPast
            let dateB = b.addedAt ?? .distantPast
            if dateA != dateB { return dateA < dateB }
            return a.relativePath.localizedStandardCompare(b.relativePath) == .orderedAscending
        }
    }
}

struct ShortSongsView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ""

    var body: some View {
        let all = model.shortSongs
        let tracks = ListFilter.apply(all, query: filter)
        let duration = tracks.reduce(0) { $0 + $1.duration }
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Canciones cortas",
                       subtitle: "\(ListFilter.countLabel(shown: tracks.count, total: all.count)) · \(formatLongDuration(duration)) · \(ShortSongs.ruleDescription)") {
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

            if !all.isEmpty {
                FilterField(text: $filter).padding(.horizontal, 32)
            }

            if tracks.isEmpty && !filter.isEmpty {
                NoFilterMatches(query: filter)
            } else if tracks.isEmpty {
                ContentUnavailableView("Sin canciones cortas",
                                       systemImage: "timer",
                                       description: Text("Aquí aparecen las \(ShortSongs.ruleDescription)."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TrackTable(tracks: tracks, highlight: filter)
            }
        }
        .background(Theme.surface)
    }
}
