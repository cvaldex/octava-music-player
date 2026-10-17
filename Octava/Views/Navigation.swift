import Observation
import SwiftUI

/// Destinos de navegación dentro del contenido.
enum LibraryRoute: Hashable {
    case album(Album)
    case artist(String)
    case genre(String)
}

/// Pila de navegación compartida: cualquier vista puede abrir un disco, un artista o un género
/// (por ejemplo, "Ir al disco" desde una tabla de canciones).
@MainActor
@Observable
final class Navigator {
    var path: [LibraryRoute] = []

    func show(_ route: LibraryRoute) {
        path.append(route)
    }

    func reset() {
        path.removeAll()
    }
}

/// Encabezado de página: título grande, subtítulo y acciones a la derecha.
struct PageHeader<Actions: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 16)
            actions()
        }
    }
}

extension PageHeader where Actions == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle, actions: { EmptyView() })
    }
}

/// Botón terracota "Mezclar" usado en varias páginas.
struct ShuffleButton: View {
    var title = "Mezclar"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "shuffle")
                .font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(AccentButtonStyle())
    }
}

/// "1 canción" / "12 canciones"
func countLabel(_ count: Int, singular: String, plural: String) -> String {
    "\(count.formatted()) \(count == 1 ? singular : plural)"
}
