import AppKit
import SwiftUI

/// Mini reproductor de la barra de menú: canción actual, avance y controles.
/// Recibe el modelo explícitamente (la ventana de la barra de menú no hereda el entorno de la ventana principal).
struct MiniPlayerView: View {
    let model: AppModel

    var body: some View {
        let player = model.player
        let track = player.currentTrack

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Group {
                    if let track, let album = model.library.album(id: track.albumId) {
                        AlbumCoverView(album: album, cornerRadius: 6)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Theme.control)
                            .overlay(Image(systemName: "music.note").foregroundStyle(Theme.mutedIcon))
                    }
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track?.title ?? "Nada sonando")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(track == nil ? Theme.secondaryText : Theme.ink)
                        .lineLimit(2)
                    if let track {
                        Text(track.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.navText)
                            .lineLimit(1)
                        Text(track.album)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let track {
                    FavoriteToggle(track: track, library: model.library)
                }
            }

            if track != nil {
                SeekBar(current: player.currentTime,
                        duration: player.duration,
                        scrobbleAt: model.scrobbler.isConnected ? scrobbleThreshold(forDuration: player.duration) : nil,
                        onSeek: { player.seek(to: $0) })
            }

            HStack(spacing: 14) {
                Spacer()
                Button { player.previous() } label: {
                    Image(systemName: "backward.end.fill").font(.system(size: 14))
                }
                .buttonStyle(IconButtonStyle(tint: Theme.ink))
                .accessibilityLabel("Anterior")

                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Theme.ink, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(track == nil)
                .accessibilityLabel(player.isPlaying ? "Pausar" : "Reproducir")

                Button { player.next() } label: {
                    Image(systemName: "forward.end.fill").font(.system(size: 14))
                }
                .buttonStyle(IconButtonStyle(tint: Theme.ink))
                .accessibilityLabel("Siguiente")

                Button { player.stopPlayback() } label: {
                    Image(systemName: "stop.fill").font(.system(size: 12))
                }
                .buttonStyle(IconButtonStyle(tint: Theme.ink))
                .disabled(track == nil)
                .accessibilityLabel("Detener")
                Spacer()
            }

            Divider().overlay(Theme.separator)

            HStack {
                Button {
                    model.playShuffledLibrary()
                } label: {
                    Label("Mezcla aleatoria", systemImage: "shuffle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accentText)
                .disabled(model.library.trackCount == 0)

                Spacer()

                Button("Abrir Octava") { Self.showMainWindow() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.navText)
            }
            .font(.system(size: 12, weight: .medium))
        }
        .padding(16)
        .frame(width: 320)
        .background(Theme.surface)
        .preferredColorScheme(.light)
    }

    /// Trae al frente la ventana principal.
    static func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain && window.title != "Ajustes" {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}

/// Glifo de Octava para la barra de menú (docs/brand/octava-menubar.svg): dos anillos, el grande con un punto.
/// Imagen "template": macOS la pinta del color correcto en modo claro y oscuro.
enum MenuBarGlyph {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { _ in
            // El SVG usa una grilla de 24: se escala a 18 pt.
            let scale = 18.0 / 24.0
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let big = NSBezierPath(ovalIn: NSRect(x: (12 - 5) * scale, y: (14.5 - 5) * scale, width: 10 * scale, height: 10 * scale))
            big.lineWidth = 2 * scale
            big.stroke()
            NSBezierPath(ovalIn: NSRect(x: (12 - 1.1) * scale, y: (14.5 - 1.1) * scale, width: 2.2 * scale, height: 2.2 * scale)).fill()
            let small = NSBezierPath(ovalIn: NSRect(x: (12 - 2) * scale, y: (6.5 - 2) * scale, width: 4 * scale, height: 4 * scale))
            small.lineWidth = 2 * scale
            small.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Octava"
        return image
    }()
}
