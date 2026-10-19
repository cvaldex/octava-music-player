import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Arrastrar canciones

/// Canciones arrastradas entre vistas (tablas, discos → cola). Viajan como texto "octava-tracks:1,2,3".
enum TrackDrag {
    static let prefix = "octava-tracks:"

    static func provider(for ids: [Int64]) -> NSItemProvider {
        NSItemProvider(object: (prefix + ids.map(String.init).joined(separator: ",")) as NSString)
    }

    static func provider(for tracks: [Track]) -> NSItemProvider {
        provider(for: tracks.compactMap(\.id))
    }

    static func ids(from text: String) -> [Int64] {
        guard text.hasPrefix(prefix) else { return [] }
        return text.dropFirst(prefix.count).split(separator: ",").compactMap { Int64($0) }
    }

    /// Lee los ids de canciones de lo que se soltó (en el orden de los elementos).
    static func loadIDs(from providers: [NSItemProvider]) async -> [Int64] {
        var result: [Int64] = []
        for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
            let text: String? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    continuation.resume(returning: object as? String)
                }
            }
            if let text { result += ids(from: text) }
        }
        return result
    }
}

// MARK: - Menú de canciones

/// Acciones comunes para una o varias canciones (clic derecho en tablas, discos y la cola).
/// Recibe el modelo y el navegador explícitamente (los menús no heredan bien el entorno; ver nota de TrackTable).
/// `tracks` es una función: se evalúa al elegir la opción, así actúa sobre la selección vigente en ese momento.
struct TrackActionsMenu: View {
    let tracks: () -> [Track]
    let model: AppModel
    let navigator: Navigator?
    /// Cantidad para los rótulos (se conoce al abrir el menú).
    var count = 1

    var body: some View {
        Button(count > 1 ? "Reproducir \(count) canciones a continuación" : "Reproducir a continuación") {
            model.playNext(tracks())
        }
        Button(count > 1 ? "Agregar \(count) canciones al final de la cola" : "Agregar al final de la cola") {
            model.addToQueue(tracks())
        }
        AddToPlaylistMenu(tracks: tracks(), model: model)
        Divider()
        if count == 1, let navigator {
            Button("Ir al disco") {
                if let album = model.library.album(id: tracks().first?.albumId) { navigator.show(.album(album)) }
            }
            Button("Ir al artista") {
                if let album = model.library.album(id: tracks().first?.albumId) { navigator.show(.artist(album.albumArtist)) }
            }
        }
        Button(count > 1 ? "Editar tags de \(count) canciones…" : "Editar tags…") { model.editTags(tracks()) }
        if count == 1, let track = tracks().first {
            Button(model.library.isFavorite(track) ? "Quitar de favoritos" : "Agregar a favoritos") {
                if let track = tracks().first { model.library.toggleFavorite(track) }
            }
        }
    }
}

// MARK: - Clic derecho selecciona

/// Detecta el clic derecho para marcar la fila como seleccionada antes de abrir el menú (como en Finder):
/// cada fila informa con `onHover` si el puntero está encima, y un monitor de eventos avisa del clic derecho.
@MainActor
final class RightClickWatcher {
    private var monitor: Any?
    var onRightClick: (() -> Void)?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            MainActor.assumeIsolated { self?.onRightClick?() }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
