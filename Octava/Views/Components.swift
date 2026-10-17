import SwiftUI

/// Botón principal terracota con texto blanco.
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.85 : 1),
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Botón secundario con borde.
struct OutlineButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Theme.ink : Theme.tertiaryText)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(configuration.isPressed ? Theme.control : Theme.surface,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.controlBorder))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Botón de ícono redondeado (controles de la barra de reproducción).
struct IconButtonStyle: ButtonStyle {
    var tint: Color = Theme.secondaryText
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? Theme.ink : tint)
            .frame(width: 32, height: 32)
            .background((isActive || configuration.isPressed) ? Theme.control : .clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Indicador animado de "sonando" (tres barras).
/// Se dibuja cuadro a cuadro con TimelineView en vez de `withAnimation(.repeatForever)`: esa animación infinita
/// se "contagia" a los cambios de diseño de las vistas vecinas (la lista de la cola crecía y se achicaba sin parar).
struct PlayingBars: View {
    var color: Color = Theme.accent
    var animating = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !animating)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                bar(level(t, speed: 6.3, offset: 0.0, rest: 0.45))
                bar(level(t, speed: 4.9, offset: 1.9, rest: 0.9))
                bar(level(t, speed: 5.7, offset: 3.4, rest: 0.6))
            }
            .frame(width: 12, height: 12, alignment: .bottom)
        }
        .frame(width: 12, height: 12)
        .accessibilityElement()
        .accessibilityLabel("Sonando")
    }

    private func level(_ t: TimeInterval, speed: Double, offset: Double, rest: CGFloat) -> CGFloat {
        guard animating else { return rest }
        return 0.3 + 0.7 * CGFloat(0.5 + 0.5 * sin(t * speed + offset))
    }

    private func bar(_ level: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(color)
            .frame(width: 2.5, height: 12 * level)
    }
}
