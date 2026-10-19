import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Miniaturas de carátulas en disco (~600 px, JPEG), para que la grilla sea fluida.
enum CoverCache {
    static let maxPixelSize = 600

    static func folder() throws -> URL {
        let folder = try AppDatabase.supportFolder().appendingPathComponent("Covers", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Crea la miniatura de un disco a partir de datos de imagen y devuelve su ruta.
    static func storeThumbnail(from data: Data, albumId: Int64) throws -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return try storeThumbnail(source: source, albumId: albumId)
    }

    /// Crea la miniatura a partir de un archivo de imagen (cover.jpg, folder.jpg…).
    static func storeThumbnail(fromFile url: URL, albumId: Int64) throws -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return try storeThumbnail(source: source, albumId: albumId)
    }

    private static func storeThumbnail(source: CGImageSource, albumId: Int64) throws -> String? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        // Nombre único: al cambiar la carátula cambia la ruta, y la vista (que guarda las imágenes por ruta) la recarga.
        let url = try folder().appendingPathComponent("\(albumId)-\(UUID().uuidString.prefix(8)).jpg")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return url.path
    }

    /// Nombres habituales de carátula dentro de la carpeta de un disco.
    static let folderCoverNames = ["cover.jpg", "cover.jpeg", "cover.png", "folder.jpg", "folder.jpeg", "folder.png", "front.jpg", "front.png"]

    static func findFolderCover(in folder: URL) -> URL? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: folder.path) else { return nil }
        let lowered = Dictionary(entries.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        for name in folderCoverNames {
            if let actual = lowered[name] {
                return folder.appendingPathComponent(actual)
            }
        }
        return nil
    }
}
