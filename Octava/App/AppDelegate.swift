import AppKit
import ObjectiveC
import SwiftUI

/// Delegado de la app: confirmar antes de cerrar y cerrar la app al cerrar su ventana.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let skipQuitConfirmationKey = "skipQuitConfirmation"

    /// Modelo de la app, para el menú del Dock (lo asigna la vista raíz al aparecer).
    @MainActor static weak var model: AppModel?

    /// Clic derecho en el ícono del Dock: la canción que suena y los controles básicos.
    @MainActor
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let model = Self.model else { return nil }
        let player = model.player
        let menu = NSMenu()
        menu.autoenablesItems = false

        if let track = player.currentTrack {
            let header = NSMenuItem(title: "\(track.title) — \(track.performer)", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(.separator())
        }
        let hasTrack = player.currentTrack != nil
        menu.addItem(ClosureMenuItem(player.isPlaying ? "Pausar" : "Reproducir", enabled: hasTrack || !player.queue.isEmpty) {
            player.togglePlayPause()
        })
        menu.addItem(ClosureMenuItem("Siguiente", enabled: hasTrack) { player.next() })
        menu.addItem(ClosureMenuItem("Anterior", enabled: hasTrack) { player.previous() })
        menu.addItem(ClosureMenuItem("Detener", enabled: hasTrack) { player.stopPlayback() })
        let stopAfter = ClosureMenuItem("Detener al terminar esta canción", enabled: hasTrack) {
            player.toggleStopAfterCurrent()
        }
        stopAfter.state = player.stopsAfterCurrent ? .on : .off
        menu.addItem(stopAfter)
        if let track = player.currentTrack {
            menu.addItem(.separator())
            let isFavorite = model.library.isFavorite(track)
            menu.addItem(ClosureMenuItem(isFavorite ? "Quitar de favoritos" : "Agregar a favoritos", enabled: true) {
                model.library.toggleFavorite(track)
            })
        }
        return menu
    }

    /// Al cerrar la ventana principal se cierra la app (y se detiene la música).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Una sola confirmación para la X, ⌘W y ⌘Q.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if UserDefaults.standard.bool(forKey: Self.skipQuitConfirmationKey) {
            return .terminateNow
        }
        let alert = NSAlert()
        alert.messageText = "¿Cerrar Octava?"
        alert.informativeText = "La música se detendrá. La próxima vez que abras Octava, seguirás desde este punto."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Cerrar")
        alert.addButton(withTitle: "Cancelar")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "No volver a preguntar"

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return .terminateCancel }
        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: Self.skipQuitConfirmationKey)
        }
        return .terminateNow
    }
}

/// Se agrega como fondo de la vista raíz para interceptar el cierre de la ventana (botón X o ⌘W):
/// en vez de cerrarla, pide cerrar la app, que muestra la confirmación. Si se cancela, la ventana sigue abierta.
struct WindowCloseConfirmation: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { GuardView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class GuardView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { WindowCloseGuard.install(on: window) }
        }
    }
}

/// Delegado intermedio de la ventana: responde `windowShouldClose` y reenvía todo lo demás
/// al delegado original de SwiftUI, para no romper su manejo de la ventana.
private final class WindowCloseGuard: NSObject, NSWindowDelegate {
    private static var associationKey: UInt8 = 0
    private weak var original: NSWindowDelegate?

    private init(original: NSWindowDelegate?) {
        self.original = original
    }

    static func install(on window: NSWindow) {
        guard !(window.delegate is WindowCloseGuard) else { return }
        let guardDelegate = WindowCloseGuard(original: window.delegate)
        // El delegado de la ventana es una referencia débil: se retiene asociado a la ventana.
        objc_setAssociatedObject(window, &associationKey, guardDelegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        window.delegate = guardDelegate
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
        return false
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let original, original.responds(to: aSelector) {
            return original
        }
        return super.forwardingTarget(for: aSelector)
    }
}

/// Ítem de menú que ejecuta un bloque (para menús armados en código, como el del Dock).
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, enabled: Bool, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        isEnabled = enabled
    }

    required init(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    @objc private func run() { handler() }
}
