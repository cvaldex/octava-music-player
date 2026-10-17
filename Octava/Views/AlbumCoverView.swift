import SwiftUI
import AppKit

/// Carátula de un disco: la miniatura en caché o, si no hay, una carátula geométrica de respaldo.
struct AlbumCoverView: View {
    let album: Album
    var cornerRadius: CGFloat = 6

    @State private var image: NSImage?

    var body: some View {
        // Siempre cuadrada: el marco lo define un cuadrado vacío y la imagen se superpone rellenándolo.
        // Una carátula más ancha que alta se recorta por igual a izquierda y derecha (y una más alta, arriba y abajo).
        // La imagen no participa del cálculo de tamaño, así que nunca ensancha la celda de la grilla.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    PlaceholderCover(seed: album.title + album.albumArtist)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: album.coverCachePath) {
            image = await CoverImageLoader.shared.image(at: album.coverCachePath)
        }
        .accessibilityHidden(true)
    }
}

/// Carátula de respaldo: fondo de color con una forma, como en el diseño.
struct PlaceholderCover: View {
    let seed: String

    var body: some View {
        let palette = Theme.placeholderCovers
        let hash = seed.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        let magnitude = hash.magnitude
        let colors = palette[Int(magnitude % UInt(palette.count))]
        let variant = Int((magnitude / 7) % 3)

        GeometryReader { geo in
            let size = geo.size.width
            ZStack {
                colors.background
                switch variant {
                case 0:
                    Circle().fill(colors.shape)
                        .frame(width: size * 0.6, height: size * 0.6)
                case 1:
                    Circle().strokeBorder(colors.shape, lineWidth: size * 0.06)
                        .frame(width: size * 0.7, height: size * 0.7)
                    Circle().fill(colors.shape)
                        .frame(width: size * 0.08, height: size * 0.08)
                default:
                    VStack(alignment: .leading, spacing: size * 0.07) {
                        Rectangle().fill(colors.shape).frame(width: size * 0.76, height: size * 0.09)
                        Rectangle().fill(colors.shape).frame(width: size * 0.76, height: size * 0.09)
                        Rectangle().fill(colors.shape).frame(width: size * 0.5, height: size * 0.09)
                    }
                }
            }
            .frame(width: size, height: size)
        }
    }
}

/// Carga de miniaturas fuera del hilo principal, con caché en memoria.
actor CoverImageLoader {
    static let shared = CoverImageLoader()
    private let cache = NSCache<NSString, NSImage>()

    func image(at path: String?) async -> NSImage? {
        guard let path else { return nil }
        if let cached = cache.object(forKey: path as NSString) {
            return cached
        }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}
