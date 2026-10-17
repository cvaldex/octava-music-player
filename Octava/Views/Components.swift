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
struct PlayingBars: View {
    var color: Color = Theme.accent
    var animating = true
    @State private var phase = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            bar(low: 0.45, high: 0.9)
            bar(low: 0.9, high: 0.35)
            bar(low: 0.3, high: 0.7)
        }
        .frame(width: 12, height: 12)
        .onAppear {
            guard animating else { return }
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { phase.toggle() }
        }
        .accessibilityLabel("Sonando")
    }

    private func bar(low: CGFloat, high: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(color)
            .frame(width: 2.5, height: 12 * (phase && animating ? high : low))
    }
}
