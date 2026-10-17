import SwiftUI

/// Pantalla "Álbumes": grilla de carátulas agrupadas por artista del álbum.
struct AlbumGridView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if model.showsScanProgress {
                    ScanBanner(progress: model.scanProgress)
                }

                if model.library.albums.isEmpty && !model.isScanning {
                    emptyState
                } else {
                    AlbumGrid(albums: model.library.albums)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 32)
        }
        .background(Theme.surface)
        .navigationTitle("Octava")
    }

    private var header: some View {
        let library = model.library

        return HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Álbumes")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(library.sort == .artist ? "Agrupados por artista del álbum" : "Ordenados por \(library.sort.rawValue.lowercased())")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 16)
            Picker("Ordenar por", selection: Binding(get: { library.sort }, set: { library.setSort($0) })) {
                ForEach(AlbumSort.allCases) { sort in
                    Text(sort.rawValue).tag(sort)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Button {
                model.playShuffledLibrary()
            } label: {
                Label("Mezcla aleatoria", systemImage: "shuffle")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(AccentButtonStyle())
            .disabled(model.library.trackCount == 0)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Tu biblioteca está vacía", systemImage: "music.note.list")
        } description: {
            Text("No encontramos MP3 en la carpeta elegida. Puedes volver a escanear o elegir otra carpeta.")
        } actions: {
            Button("Volver a escanear") { Task { await model.rescan() } }
            Button("Elegir otra carpeta…") { model.chooseFolder() }
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}

/// Un disco en la grilla.
struct AlbumTile: View {
    let album: Album
    let isPlaying: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AlbumCoverView(album: album)
                .shadow(color: Theme.ink.opacity(0.14), radius: 1.5, y: 1)
                .overlay(alignment: .bottomLeading) {
                    if isPlaying {
                        HStack(spacing: 6) {
                            PlayingBars()
                            Text("Sonando")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.accentText)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.94), in: Capsule())
                        .padding(8)
                    }
                }
                .overlay {
                    if isPlaying {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(Theme.accent, lineWidth: 2)
                            .padding(-3)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(album.albumArtist)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                if let year = album.year {
                    Text(String(year))
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Aviso de escaneo en curso con barra de avance.
struct ScanBanner: View {
    let progress: LibraryScanner.Progress?

    var body: some View {
        HStack(spacing: 12) {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(Theme.accent)
                .frame(maxWidth: 240)
            Text(label)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(12)
        .background(Theme.sidebar, in: RoundedRectangle(cornerRadius: 8))
    }

    private var fraction: Double {
        guard let progress, progress.total > 0 else { return 0 }
        return Double(progress.processed) / Double(progress.total)
    }

    private var label: String {
        guard let progress else { return "Buscando archivos…" }
        return "Leyendo \(progress.processed.formatted()) de \(progress.total.formatted()) archivos nuevos o modificados"
    }
}
