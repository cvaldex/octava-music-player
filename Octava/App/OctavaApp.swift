import SwiftUI

@main
struct OctavaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @AppStorage("showsMenuBarPlayer") private var showsMenuBarPlayer = true

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
                Button("Importar lista…") { model.importPlaylist() }
                    .disabled(model.musicFolder == nil)
            }
            CommandGroup(after: .undoRedo) {
                Divider()
                Button("Deshacer edición de tags") {
                    Task { await model.undoLastTagEditConfirming() }
                }
                .keyboardShortcut("z", modifiers: [.command, .option])
                .disabled(!model.canUndoTagEdit || model.isSavingTags)
            }
            CommandMenu("Reproducción") {
                // Barra espaciadora sin modificadores: pendiente para la fase 6 (debe convivir con el campo de búsqueda).
                Button(model.player.isPlaying ? "Pausar" : "Reproducir") { model.player.togglePlayPause() }
                    .keyboardShortcut("p", modifiers: .command)
                Button("Siguiente") { model.player.next() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Anterior") { model.player.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button(model.player.isMuted ? "Quitar el silencio" : "Silenciar") { model.player.toggleMute() }
                    .keyboardShortcut("m", modifiers: [.command, .option])
                Divider()
                Button("Retroceder 10 segundos") { model.skip(by: -10) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                    .disabled(model.player.currentTrack == nil)
                Button("Adelantar 10 segundos") { model.skip(by: 10) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                    .disabled(model.player.currentTrack == nil)
                Button("Subir el volumen") { model.changeVolume(by: 0.1) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                Button("Bajar el volumen") { model.changeVolume(by: -0.1) }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                Button("Ir a la canción actual") { model.revealCurrentTrack() }
                    .keyboardShortcut("l", modifiers: .command)
                    .disabled(model.player.currentTrack == nil)
                Divider()
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

        Settings {
            SettingsView(model: model)
        }

        // El título es el texto que aparece al dejar el puntero sobre el ícono.
        MenuBarExtra("Octava Music Player", image: "MenuBarGlyph", isInserted: $showsMenuBarPlayer) {
            MiniPlayerView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
