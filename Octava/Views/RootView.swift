import SwiftUI

/// Ventana principal: barra lateral + contenido, panel de la cola a la derecha y la barra de reproducción abajo.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem = .albums
    @State private var navigator = Navigator()
    @State private var query = ""
    @AppStorage("showQueue") private var showQueue = true

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // El panel de la cola es una columna propia de la ventana, fuera del NavigationSplitView:
            // dentro de él, la navegación (entrar a un disco) reemplazaba la columna completa y el panel desaparecía.
            HStack(spacing: 0) {
                NavigationSplitView {
                    SidebarView(selection: $selection)
                        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
                } detail: {
                    // minWidth 0 + clipped: el contenido nunca empuja el panel de la cola fuera de la ventana.
                    detail
                        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
                .searchable(text: $query, placement: .toolbar, prompt: "Artista, álbum o canción")
                .frame(minWidth: 0, maxWidth: .infinity)

                if showQueue {
                    Divider().overlay(Theme.separator)
                    QueuePanel()
                        .frame(width: 280)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showQueue)
            Divider().overlay(Theme.separator)
            PlayerBarView()
        }
        .environment(navigator)
        .background(Theme.surface)
        .onChange(of: selection) {
            navigator.reset()
            query = ""
        }
        .onChange(of: isSearching) { _, searching in
            // Al empezar a buscar se vuelve a la raíz para mostrar los resultados.
            if searching { navigator.reset() }
        }
        .sheet(isPresented: Binding(get: { model.showsMixBuilder }, set: { model.showsMixBuilder = $0 })) {
            MixBuilderView(model: model)
        }
        .onChange(of: model.playlists.playlists) { _, playlists in
            // Si se borró la lista que estaba abierta, volver a Álbumes.
            if case .playlist(let id) = selection, !playlists.contains(where: { $0.id == id }) {
                selection = .albums
            }
        }
        .alert("Algo salió mal",
               isPresented: Binding(get: { model.errorMessage != nil },
                                    set: { if !$0 { model.errorMessage = nil } })) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var detail: some View {
        if model.musicFolder == nil {
            WelcomeView()
        } else {
            NavigationStack(path: Binding(get: { navigator.path }, set: { navigator.path = $0 })) {
                rootPage
                    .navigationDestination(for: LibraryRoute.self) { route in
                        switch route {
                        case .album(let album):
                            AlbumDetailView(album: album)
                        case .artist(let name):
                            ArtistDetailView(name: name)
                        case .genre(let name):
                            GenreDetailView(name: name)
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var rootPage: some View {
        if isSearching {
            SearchResultsView(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            switch selection {
            case .albums:
                AlbumGridView()
            case .artists:
                ArtistsView()
            case .songs:
                SongsView()
            case .genres:
                GenresView()
            case .favorites:
                FavoritesView()
            case .mostPlayed:
                MostPlayedView()
            case .forgotten:
                ForgottenView()
            case .playlist(let id):
                PlaylistView(id: id) { selection = .albums }
                    .id(id)
            }
        }
    }
}
