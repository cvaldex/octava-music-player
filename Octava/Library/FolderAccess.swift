import AppKit

/// Elige la carpeta de música y guarda el permiso del sandbox (security-scoped bookmark)
/// para no volver a pedirlo en cada apertura.
@MainActor
enum FolderAccess {
    private static let bookmarkKey = "musicFolderBookmark"

    static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Elige tu carpeta de música"
        panel.message = "Octava leerá los MP3 de esta carpeta y sus subcarpetas."
        panel.prompt = "Usar esta carpeta"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try saveBookmark(for: url)
        } catch {
            print("Octava: no se pudo guardar el permiso de la carpeta: \(error)")
        }
        return url
    }

    static func restoreFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: data,
                              options: [.withSecurityScope],
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            if isStale {
                try? saveBookmark(for: url)
            }
            return url
        } catch {
            print("Octava: el permiso guardado de la carpeta ya no es válido: \(error)")
            return nil
        }
    }

    private static func saveBookmark(for url: URL) throws {
        let data = try url.bookmarkData(options: [.withSecurityScope],
                                        includingResourceValuesForKeys: nil,
                                        relativeTo: nil)
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }
}
