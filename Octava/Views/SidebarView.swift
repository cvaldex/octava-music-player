import SwiftUI

enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
    case albums, artists, songs, genres, favorites
    case mostPlayed, forgotten

    var id: String { rawValue }

    var title: String {
        switch self {
        case .albums: "Álbumes"
        case .artists: "Artistas"
        case .songs: "Canciones"
        case .genres: "Géneros"
        case .favorites: "Favoritos"
        case .mostPlayed: "Más escuchadas"
        case .forgotten: "Hace tiempo sin oír"
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
        }
    }

    static let library: [SidebarItem] = [.albums, .artists, .songs, .genres, .favorites]
    static let smartLists: [SidebarItem] = [.mostPlayed, .forgotten]
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: SidebarItem

    var body: some View {
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
                        Image(systemName: "shuffle").foregroundStyle(Theme.accent)
                    }
                    .tag(item)
                }
                Button {
                    // Fase 3: listas guardadas.
                } label: {
                    Label("Nueva lista", systemImage: "plus")
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
                .disabled(true)
                .help("Las listas guardadas llegan en la fase 3")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            statusCard
                .padding(12)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.mutedIcon)
                    .frame(width: 8, height: 8)
                Text("Last.fm sin conectar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            .help("El scrobbling llega en la fase 5")

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
