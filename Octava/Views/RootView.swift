import SwiftUI

/// Ventana principal: barra lateral + contenido, panel de la cola a la derecha y la barra de reproducción abajo.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem = .albums
    @State private var navigator = Navigator()
    @State private var query = ""
    @AppStorage("showQueue") private var showQueue = true
    /// Disco a mostrar después de cambiar de sección (⌘L desde otra sección).
    @State private var pendingReveal: Album?

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            LibraryBanners(model: model)
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
            .overlay(alignment: .bottom) {
                if let notice = model.player.notice {
                    NoticeToast(text: notice.text) { model.player.dismissNotice(notice.id) }
                        .padding(.bottom, 14)
                        .task(id: notice.id) {
                            try? await Task.sleep(for: .seconds(7))
                            model.player.dismissNotice(notice.id)
                        }
                }
            }
            Divider().overlay(Theme.separator)
            PlayerBarView()
        }
        .environment(navigator)
        .background(Theme.surface)
        .onChange(of: selection) {
            navigator.reset()
            query = ""
            if let album = pendingReveal {
                pendingReveal = nil
                navigator.show(.album(album))
            }
        }
        .onChange(of: model.revealCurrentRequest) {
            guard let album = model.library.album(id: model.player.currentTrack?.albumId) else { return }
            query = ""
            if selection == .albums {
                navigator.reset()
                navigator.show(.album(album))
            } else {
                pendingReveal = album
                selection = .albums
            }
        }
        .onChange(of: isSearching) { _, searching in
            // Al empezar a buscar se vuelve a la raíz para mostrar los resultados.
            if searching { navigator.reset() }
        }
        .sheet(isPresented: Binding(get: { model.showsMixBuilder }, set: { model.showsMixBuilder = $0 })) {
            MixBuilderView(model: model)
        }
        .sheet(item: Binding(get: { model.tagEditTarget }, set: { model.tagEditTarget = $0 })) { target in
            TagEditorView(model: model, tracks: target.tracks)
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

/// Avisos sobre la carpeta de música, arriba de la ventana.
private struct LibraryBanners: View {
    let model: AppModel

    var body: some View {
        if model.folderUnavailable {
            banner(icon: "externaldrive.badge.exclamationmark",
                   text: "No se encuentra la carpeta de música (¿un disco desconectado?). Tu biblioteca, escuchas y listas se conservan; al reconectarla, Octava la vuelve a leer.") {
                Button("Reintentar") { Task { await model.rescan() } }
                Button("Elegir otra carpeta…") { model.chooseFolder() }
            }
        } else if model.withheldMissingCount > 0 {
            banner(icon: "questionmark.folder",
                   text: "\(countLabel(model.withheldMissingCount, singular: "canción ya no está", plural: "canciones ya no están")) en la carpeta. ¿Quitarlas de la biblioteca? Se pierden sus escuchas y favoritos.") {
                Button("Mantener") { model.keepMissingTracks() }
                Button("Quitar de la biblioteca") { Task { await model.removeMissingTracks() } }
            }
        }
    }

    private func banner<Actions: View>(icon: String, text: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.accent)
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                actions()
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Theme.accentTint)
            Divider().overlay(Theme.separator)
        }
    }
}

/// Aviso breve flotante (por ejemplo, una canción que no se pudo abrir).
private struct NoticeToast: View {
    let text: String
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.accent)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondaryText)
            .accessibilityLabel("Cerrar aviso")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: 560)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.controlBorder))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
    }
}
