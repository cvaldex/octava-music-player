import SwiftUI

/// Tabla de canciones reutilizable (Canciones, Favoritos, Género, Búsqueda).
/// Columnas ordenables con clic en el encabezado; doble clic o Enter reproduce desde la canción;
/// clic derecho para la cola, ir al disco o al artista y favoritos. Admite selección múltiple.
///
/// Importante: las celdas de una `Table` se dibujan en vistas propias de AppKit que no heredan el entorno
/// de SwiftUI de forma fiable. Ninguna vista dentro de una celda debe usar `@Environment(...)`: los datos se
/// pasan explícitamente (con `@Environment` dentro de la celda, la app se cerraba al desplazar la tabla).
struct TrackTable: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    let tracks: [Track]

    @State private var sortOrder: [KeyPathComparator<Track>] = []
    @State private var selection = Set<Track.ID>()

    /// Al reproducir desde una tabla muy larga, la cola toma como máximo esta cantidad de canciones.
    private static let maxQueueLength = 1000

    /// Filas en el orden elegido. Se calcula al dibujar (ordenar miles de filas toma milisegundos) para que,
    /// al cambiar el orden, la tabla reconstruida nazca ya ordenada y no anime movimientos.
    private var rows: [Track] {
        sortOrder.isEmpty ? tracks : tracks.sorted(using: sortOrder)
    }

    var body: some View {
        let rows = self.rows
        let currentID = model.player.currentTrack?.id
        let library = model.library

        Table(of: Track.self, selection: $selection, sortOrder: $sortOrder) {
            // Ícono fijo: una animación dentro de la tabla la obligaba a actualizarse completa muchas veces por
            // segundo y, con miles de filas, la app dejaba de responder.
            TableColumn("") { (track: Track) in
                if track.id != nil && track.id == currentID {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.accent)
                        .accessibilityLabel("Sonando")
                }
            }
            .width(16)

            TableColumn("Título", value: \Track.title) { (track: Track) in
                let isCurrent = track.id != nil && track.id == currentID
                Text(track.title)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundStyle(isCurrent ? Theme.accentText : Theme.ink)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 170)

            TableColumn("Artista", value: \Track.performer) { (track: Track) in
                Text(track.performer).foregroundStyle(Theme.navText).lineLimit(1)
            }
            .width(min: 70, ideal: 110)

            TableColumn("Álbum", value: \Track.album) { (track: Track) in
                Text(track.album).foregroundStyle(Theme.navText).lineLimit(1)
            }
            .width(min: 70, ideal: 130)

            TableColumn("Año", value: \Track.sortYear) { (track: Track) in
                Text(track.year.map(String.init) ?? "")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.secondaryText)
            }
            .width(min: 40, ideal: 48)

            TableColumn("Género", value: \Track.sortGenre) { (track: Track) in
                Text(track.genre ?? "").foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
            .width(min: 50, ideal: 70)

            TableColumn("Escuchas", value: \Track.playCount) { (track: Track) in
                Text(String(track.playCount))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 52, ideal: 56)

            TableColumn("") { (track: Track) in
                FavoriteToggle(track: track, library: library)
            }
            .width(24)

            TableColumn("Duración", value: \Track.duration) { (track: Track) in
                Text(formatDuration(track.duration))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 52, ideal: 56)
        } rows: {
            // Cada fila se puede arrastrar a la cola (con varias seleccionadas, se arrastran todas).
            ForEach(rows) { track in
                TableRow(track)
                    .itemProvider { TrackDrag.provider(for: [track]) }
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .font(.system(size: 13))
        // Al cambiar el orden se reconstruye la tabla en vez de animar el movimiento de miles de filas
        // (con 2.400 filas, la animación de reordenar dejaba la app sin responder).
        .id(sortIdentity)
        .contextMenu(forSelectionType: Track.ID.self) { ids in
            menu(for: ids, rows: rows)
        } primaryAction: { ids in
            play(ids, rows: rows)
        }
    }

    private var sortIdentity: String {
        sortOrder.map { "\($0.keyPath)-\($0.order == .forward)" }.joined(separator: "|")
    }


    @ViewBuilder
    private func menu(for ids: Set<Track.ID>, rows: [Track]) -> some View {
        let selected = rows.filter { ids.contains($0.id) }
        // Clic derecho sobre una fila no seleccionada: queda seleccionada (gris), como con el clic izquierdo.
        let _ = selectLater(ids)
        if !selected.isEmpty {
            Button(selected.count == 1 ? "Reproducir" : "Reproducir desde aquí") { play(ids, rows: rows) }
            TrackActionsMenu(tracks: { selected }, model: model, navigator: navigator, count: selected.count)
        }
    }

    private func selectLater(_ ids: Set<Track.ID>) {
        guard !ids.isEmpty, !ids.isSubset(of: selection) else { return }
        DispatchQueue.main.async { selection = ids }
    }

    /// Reproduce la tabla (en el orden visible) desde la primera canción seleccionada.
    private func play(_ ids: Set<Track.ID>, rows: [Track]) {
        guard let start = rows.firstIndex(where: { ids.contains($0.id) }) else { return }
        let end = min(rows.count, start + Self.maxQueueLength)
        model.play(tracks: Array(rows[start..<end]))
    }
}

/// Corazón de favorito para filas de tablas y listas. Recibe la biblioteca explícitamente (ver nota de TrackTable).
struct FavoriteToggle: View {
    let track: Track
    let library: LibraryStore

    var body: some View {
        let isFavorite = library.isFavorite(track)
        Button {
            library.toggleFavorite(track)
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 12))
                .foregroundStyle(isFavorite ? Theme.accent : Theme.mutedIcon)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFavorite ? "Quitar de favoritos" : "Agregar a favoritos")
    }
}
