import SwiftUI

/// Ventana principal: barra lateral + contenido, y la barra de reproducción a lo ancho abajo.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem = .albums
    @State private var path: [Album] = []
    @AppStorage("showQueue") private var showQueue = true

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
