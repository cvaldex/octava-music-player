import SwiftUI

/// Tokens del tema claro de Octava. Valores tomados del diseño (docs/DESIGN.md).
/// Usar siempre estos tokens en las vistas; no escribir colores sueltos.
enum Theme {
    // Acento terracota: botón principal, canción en reproducción, favoritos, Last.fm.
    static let accent = Color(hex: 0xC2491A)
    static let accentText = Color(hex: 0xA63E14)
    static let accentTint = Color(hex: 0xFBF0EA)

    // Texto
    static let ink = Color(hex: 0x16171A)
    static let secondaryText = Color(hex: 0x5F626A)
    static let tertiaryText = Color(hex: 0x6B6E76)
    static let navText = Color(hex: 0x3B3D44)

    // Superficies
    static let surface = Color.white
    static let sidebar = Color(hex: 0xF3F3F5)
    static let playerBar = Color(hex: 0xF7F7F9)
    static let queuePanel = Color(hex: 0xFAFAFB)
    static let separator = Color(hex: 0xE3E4E8)
    static let control = Color(hex: 0xE1E2E7)
    static let controlBorder = Color(hex: 0xCFD1D6)
    static let mutedIcon = Color(hex: 0xA3A6AD)

    // Estado
    static let ok = Color(hex: 0x1F9D62)

    // Tipografía: fuente del sistema para la interfaz, monoespaciada para números (duraciones, años, contadores).
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let sectionLabel = Font.system(size: 11, weight: .semibold)

    // Colores de las carátulas de respaldo (cuando un disco no tiene carátula).
    static let placeholderCovers: [(background: Color, shape: Color)] = [
        (Color(hex: 0x2F4858), Color(hex: 0xF6AE2D)),
        (Color(hex: 0x8E3B46), Color(hex: 0xE9D8A6)),
        (Color(hex: 0x3E424B), Color(hex: 0xD9D9D9)),
        (Color(hex: 0xE07A5F), Color(hex: 0x3D405B)),
        (Color(hex: 0x1B998B), Color(hex: 0xF8F1E5)),
        (Color(hex: 0xF2C14E), Color(hex: 0x2B2D42)),
        (Color(hex: 0x5B5F97), Color(hex: 0xFFC6AC)),
        (Color(hex: 0x6A994E), Color(hex: 0xF2E8CF)),
        (Color(hex: 0xBC4749), Color(hex: 0xF2E8CF)),
        (Color(hex: 0x22223B), Color(hex: 0xC9ADA7)),
        (Color(hex: 0xA7754D), Color(hex: 0x2E1F14))
    ]
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Formato m:ss para duraciones.
func formatDuration(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let total = Int(seconds.rounded(.down))
    return String(format: "%d:%02d", total / 60, total % 60)
}
