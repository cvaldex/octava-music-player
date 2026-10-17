import SwiftUI

/// Grilla de discos reutilizable (biblioteca, artista, búsqueda). Clic abre el disco; clic derecho, acciones de cola.
struct AlbumGrid: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    let albums: [Album]
    var minimumTileWidth: CGFloat = 160

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: minimumTileWidth, maximum: minimumTileWidth * 1.5), spacing: 22, alignment: .top)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
            ForEach(albums) { album in
                NavigationLink(value: LibraryRoute.album(album)) {
                    AlbumTile(album: album,
                              isPlaying: album.id != nil && model.player.currentTrack?.albumId == album.id)
                }
                .buttonStyle(.plain)
                .contextMenu { AlbumContextMenu(album: album, model: model, navigator: navigator) }
            }
        }
    }
}

/// Acciones de un disco (clic derecho).
/// Recibe el modelo y el navegador explícitamente: los menús contextuales se dibujan aparte y no conviene
/// depender del entorno de SwiftUI dentro de ellos (ver nota de TrackTable).
struct AlbumContextMenu: View {
    let album: Album
    let model: AppModel
    let navigator: Navigator
    var showsArtistLink = true

    var body: some View {
        Button("Reproducir") { model.play(album: album) }
        Button("Reproducir en orden aleatorio") { model.playShuffled(album: album) }
        Divider()
        Button("Reproducir a continuación") { model.playNext(album: album) }
        Button("Agregar al final de la cola") { model.addToQueue(album: album) }
        if showsArtistLink {
            Divider()
            Button("Ir al artista") { navigator.show(.artist(album.albumArtist)) }
        }
    }
}
