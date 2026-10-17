import AppKit
import ObjectiveC
import SwiftUI

/// Delegado de la app: confirmar antes de cerrar y cerrar la app al cerrar su ventana.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let skipQuitConfirmationKey = "skipQuitConfirmation"

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
