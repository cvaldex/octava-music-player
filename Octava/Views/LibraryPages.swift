import SwiftUI

// MARK: - Canciones

/// Todas las canciones en una tabla ordenable.
struct SongsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let tracks = model.library.tracks
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Canciones", subtitle: countLabel(tracks.count, singular: "canción", plural: "canciones")) {
                ShuffleButton { model.startMix(MixRule()) }
                    .disabled(tracks.isEmpty)
                    .help("Mezcla de toda la colección que se rellena sola")
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)

            TrackTable(tracks: tracks)
        }
        .background(Theme.surface)
    }
}

// MARK: - Favoritos

struct FavoritesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let tracks = model.library.favoriteTracks
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Favoritos", subtitle: countLabel(tracks.count, singular: "canción", plural: "canciones")) {
                ShuffleButton { model.startMix(MixRule(source: .favorites)) }
                    .disabled(tracks.isEmpty)
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)

            if tracks.isEmpty {
                ContentUnavailableView("Aún no tienes favoritos",
                                       systemImage: "heart",
                                       description: Text("Marca el corazón de una canción para encontrarla aquí."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TrackTable(tracks: tracks)
            }
        }
        .background(Theme.surface)
    }
}

// MARK: - Artistas

/// Lista de artistas (del álbum) con su carátula representativa.
struct ArtistsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let artists = model.library.artists
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Artistas", subtitle: countLabel(artists.count, singular: "artista", plural: "artistas"))
                .padding(.horizontal, 32)
                .padding(.top, 28)

            List(artists) { artist in
                NavigationLink(value: LibraryRoute.artist(artist.name)) {
                    HStack(spacing: 12) {
                        Group {
                            if let album = artist.coverAlbum {
                                AlbumCoverView(album: album, cornerRadius: 20)
                            } else {
                                Circle().fill(Theme.control)
                            }
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(artist.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Text(countLabel(artist.albumCount, singular: "disco", plural: "discos"))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .contextMenu {
                    Button("Reproducir discografía") { model.play(artist: artist.name) }
                    Button("Mezclar canciones") { model.startMix(MixRule(artists: [artist.name])) }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 16)
        }
        .background(Theme.surface)
    }
}

/// Discos de un artista.
struct ArtistDetailView: View {
    @Environment(AppModel.self) private var model
    let name: String

    var body: some View {
        let albums = model.library.albums(byArtist: name)
        let trackCount = albums.reduce(0) { $0 + model.library.tracks(for: $1).count }

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: name,
                           subtitle: "\(countLabel(albums.count, singular: "disco", plural: "discos")) · \(countLabel(trackCount, singular: "canción", plural: "canciones"))") {
                    Button {
                        model.play(artist: name)
                    } label: {
                        Label("Reproducir todo", systemImage: "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(AccentButtonStyle())
                    Button {
                        model.startMix(MixRule(artists: [name]))
                    } label: {
                        Label("Mezclar", systemImage: "shuffle").font(.system(size: 13))
                    }
                    .buttonStyle(OutlineButtonStyle())
                }

                AlbumGrid(albums: albums)
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 32)
        }
        .background(Theme.surface)
        .navigationTitle(name)
    }
}

// MARK: - Géneros

struct GenresView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let genres = model.library.genres
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Géneros", subtitle: countLabel(genres.count, singular: "género", plural: "géneros"))
                .padding(.horizontal, 32)
                .padding(.top, 28)

            if genres.isEmpty {
                ContentUnavailableView("Sin géneros",
                                       systemImage: "guitars",
                                       description: Text("Tus MP3 no tienen el tag de género. Podrás completarlo con el editor de tags (fase 4)."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(genres) { genre in
                    NavigationLink(value: LibraryRoute.genre(genre.name)) {
                        HStack {
                            Text(genre.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text(countLabel(genre.trackCount, singular: "canción", plural: "canciones"))
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .padding(.vertical, 6)
                    }
                    .contextMenu {
                        Button("Mezclar canciones") { model.startMix(MixRule(genres: [genre.name])) }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 16)
            }
        }
        .background(Theme.surface)
    }
}

/// Canciones de un género.
struct GenreDetailView: View {
    @Environment(AppModel.self) private var model
    let name: String

    var body: some View {
        let tracks = model.library.tracks(inGenre: name)
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: name, subtitle: countLabel(tracks.count, singular: "canción", plural: "canciones")) {
                ShuffleButton { model.startMix(MixRule(genres: [name])) }
                    .disabled(tracks.isEmpty)
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)

            TrackTable(tracks: tracks)
        }
        .background(Theme.surface)
        .navigationTitle(name)
    }
}

// MARK: - Búsqueda

/// Resultados de la búsqueda: discos arriba, canciones abajo.
struct SearchResultsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    let query: String

    var body: some View {
        let results = model.library.search(query)

        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Resultados", subtitle: "“\(query)”")
                .padding(.horizontal, 32)
                .padding(.top, 28)

            if results.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if !results.albums.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("DISCOS")
                            .font(Theme.sectionLabel)
                            .tracking(0.6)
                            .foregroundStyle(Theme.tertiaryText)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 18) {
                                ForEach(results.albums) { album in
                                    NavigationLink(value: LibraryRoute.album(album)) {
                                        AlbumTile(album: album,
                                                  isPlaying: album.id != nil && model.player.currentTrack?.albumId == album.id)
                                            .frame(width: 130)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu { AlbumContextMenu(album: album, model: model, navigator: navigator) }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.horizontal, 32)
                }

                if !results.tracks.isEmpty {
                    Text("CANCIONES")
                        .font(Theme.sectionLabel)
                        .tracking(0.6)
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.horizontal, 32)
                    TrackTable(tracks: results.tracks)
                } else {
                    Spacer()
                }
            }
        }
        .background(Theme.surface)
    }
}
