import SwiftUI

@main
struct OctavaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .background(WindowCloseConfirmation())
                // Tema claro elegido en el diseño. El oscuro queda para más adelante (ver docs/DESIGN.md).
                .preferredColorScheme(.light)
                .frame(minWidth: 980, minHeight: 620)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Elegir carpeta de música…") { model.chooseFolder() }
                    .keyboardShortcut("o")
                Button("Volver a escanear la colección") {
                    Task { await model.rescan() }
                }
                .keyboardShortcut("r")
                .disabled(model.musicFolder == nil || model.isScanning)
                Divider()
                Button("Nueva lista…") { model.createPlaylistPrompting() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Guardar la cola como lista…") { model.saveQueueAsPlaylist() }
                    .disabled(model.player.queue.isEmpty)
            }
            CommandMenu("Reproducción") {
                // Barra espaciadora sin modificadores: pendiente para la fase 6 (debe convivir con el campo de búsqueda).
                Button(model.player.isPlaying ? "Pausar" : "Reproducir") { model.player.togglePlayPause() }
                    .keyboardShortcut("p", modifiers: .command)
                Button("Siguiente") { model.player.next() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Anterior") { model.player.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("Detener") { model.player.stopPlayback() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(model.player.currentTrack == nil)
                Toggle("Detener al terminar esta canción",
                       isOn: Binding(get: { model.player.stopsAfterCurrent },
                                     set: { model.player.setStopAfterCurrent($0) }))
                    .keyboardShortcut(".", modifiers: [.command, .option])
                    .disabled(model.player.currentTrack == nil)
                Divider()
                Button("Mezcla aleatoria de toda la colección") { model.playShuffledLibrary() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Nueva mezcla con filtros…") { model.showsMixBuilder = true }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                    .disabled(model.musicFolder == nil)
                Button("Detener el relleno de la mezcla") { model.stopMix() }
                    .disabled(model.activeMix == nil)
                Divider()
                Picker("Repetir", selection: Binding(get: { model.player.repeatMode },
                                                     set: { model.setRepeatMode($0) })) {
                    ForEach(RepeatMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Picker("Normalización de volumen", selection: Binding(get: { model.player.normalization },
                                                                      set: { model.setNormalization($0) })) {
                    ForEach(NormalizationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Toggle("Seguir con una mezcla al terminar la cola",
                       isOn: Binding(get: { model.continueWithMix }, set: { model.continueWithMix = $0 }))
            }
        }
    }
}
