import SwiftUI

/// Ventana principal: barra lateral + contenido, y la barra de reproducción a lo ancho abajo.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem = .albums
    @State private var path: [Album] = []

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                SidebarView(selection: $selection)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
            } detail: {
                detail
            }
            Divider().overlay(Theme.separator)
            PlayerBarView()
        }
        .background(Theme.surface)
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
            switch selection {
            case .albums:
                NavigationStack(path: $path) {
                    AlbumGridView()
                        .navigationDestination(for: Album.self) { album in
                            AlbumDetailView(album: album)
                        }
                }
            default:
                ContentUnavailableView(selection.title,
                                       systemImage: selection.systemImage,
                                       description: Text("Esta vista llega en una próxima fase."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.surface)
            }
        }
    }
}
