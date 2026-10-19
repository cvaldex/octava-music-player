import SwiftUI

enum SidebarItem: Hashable, Identifiable {
    case albums, artists, songs, genres, favorites
    case mostPlayed, forgotten
    /// Lista guardada (id en la base de datos).
    case playlist(Int64)

    var id: String {
        switch self {
        case .playlist(let id): "playlist-\(id)"
        default: title
        }
    }

    var title: String {
        switch self {
        case .albums: "Álbumes"
        case .artists: "Artistas"
        case .songs: "Canciones"
        case .genres: "Géneros"
        case .favorites: "Favoritos"
        case .mostPlayed: "Más escuchadas"
        case .forgotten: "Hace tiempo sin oír"
        case .playlist: "Lista"
        }
    }

    var systemImage: String {
        switch self {
        case .albums: "square.grid.2x2"
        case .artists: "music.mic"
        case .songs: "music.note"
        case .genres: "guitars"
        case .favorites: "heart"
        case .mostPlayed: "chart.bar"
        case .forgotten: "clock.arrow.circlepath"
        case .playlist: "music.note.list"
        }
    }

    static let library: [SidebarItem] = [.albums, .artists, .songs, .genres, .favorites]
    static let smartLists: [SidebarItem] = [.mostPlayed, .forgotten]
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: SidebarItem

    var body: some View {
        let playlists = model.playlists.playlists
        List(selection: Binding<SidebarItem?>(get: { selection }, set: { if let value = $0 { selection = value } })) {
            Section("Biblioteca") {
                ForEach(SidebarItem.library) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                }
            }
            Section("Listas") {
                ForEach(SidebarItem.smartLists) { item in
                    Label {
                        Text(item.title)
                    } icon: {
                        Image(systemName: item.systemImage).foregroundStyle(Theme.accent)
                    }
                    .tag(item)
                    .help("Lista que se actualiza sola")
                }
                ForEach(playlists) { playlist in
                    if let id = playlist.id {
                        Label(playlist.name, systemImage: "music.note.list")
                            .lineLimit(1)
                            .tag(SidebarItem.playlist(id))
                            .contextMenu {
                                Button("Reproducir") { model.play(tracks: model.tracks(inPlaylist: id)) }
                                Button("Mezclar") { model.playShuffled(tracks: model.tracks(inPlaylist: id)) }
                                Divider()
                                Button("Renombrar…") { model.renamePlaylistPrompting(playlist) }
                                Button("Eliminar lista…") {
                                    if model.deletePlaylistConfirming(playlist), selection == .playlist(id) {
                                        selection = .albums
                                    }
                                }
                            }
                    }
                }
                Button {
                    if let id = model.createPlaylistPrompting() {
                        selection = .playlist(id)
                    }
                } label: {
                    Label("Nueva lista", systemImage: "plus")
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            statusCard
                .padding(12)
        }
    }

    private var lastFMTitle: String {
        let scrobbler = model.scrobbler
        if let username = scrobbler.username {
            return scrobbler.isEnabled ? "Last.fm · \(username)" : "Last.fm en pausa"
        }
        return scrobbler.isAuthorizing ? "Conectando Last.fm…" : "Last.fm sin conectar"
    }

    private var lastFMDotColor: Color {
        let scrobbler = model.scrobbler
        guard scrobbler.isConnected, scrobbler.isEnabled else { return Theme.mutedIcon }
        return scrobbler.lastError == nil ? Theme.ok : Theme.accent
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsLink {
                HStack(spacing: 8) {
                    Circle()
                        .fill(lastFMDotColor)
                        .frame(width: 8, height: 8)
                    Text(lastFMTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.scrobbler.lastError ?? "Ajustes de Last.fm")

            if model.scrobbler.pendingCount > 0 {
                Text(countLabel(model.scrobbler.pendingCount, singular: "scrobble pendiente", plural: "scrobbles pendientes"))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.accentText)
            }

            if model.showsScanProgress, let progress = model.scanProgress {
                Text("Leyendo \(progress.processed) de \(progress.total)")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("\(model.library.trackCount.formatted()) canciones · \(model.library.albums.count.formatted()) discos")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.secondaryText)
            }

            if let folder = model.musicFolder {
                Text(folder.abbreviatingWithTildeInPath)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xDCDDE2)))
    }
}

private extension URL {
    var abbreviatingWithTildeInPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
