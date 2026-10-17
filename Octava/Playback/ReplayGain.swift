import Foundation

/// Cómo se normaliza el volumen entre canciones.
enum NormalizationMode: String, CaseIterable, Identifiable {
    case off, auto, track, album

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Desactivada"
        case .auto: "Automática"
        case .track: "Por canción"
        case .album: "Por disco"
        }
    }
}

/// De dónde viene la cola: define qué ganancia usa el modo automático.
enum QueueSource: String {
    /// Un disco completo en orden: se respeta la dinámica entre sus canciones (ganancia de disco).
    case album
    /// Una mezcla: cada canción se nivela por separado (ganancia de canción).
    case mix
}

/// Cálculo de la ganancia ReplayGain. Lógica pura, testeada.
enum ReplayGain {
    /// Máximo refuerzo permitido. Sin datos de pico no se puede garantizar que no sature, así que se limita.
    static let maxBoost = 6.0
    static let minGain = -24.0

    static func gain(trackGain: Double?, albumGain: Double?, mode: NormalizationMode, source: QueueSource) -> Double {
        let preferAlbum: Bool
        switch mode {
        case .off: return 0
        case .track: preferAlbum = false
        case .album: preferAlbum = true
        case .auto: preferAlbum = source == .album
        }
        let value = preferAlbum ? (albumGain ?? trackGain) : (trackGain ?? albumGain)
        return min(maxBoost, max(minGain, value ?? 0))
    }

    static func gain(for track: Track?, mode: NormalizationMode, source: QueueSource) -> Double {
        guard let track else { return 0 }
        return gain(trackGain: track.replayGainTrack, albumGain: track.replayGainAlbum, mode: mode, source: source)
    }

    /// "-6.54 dB" → -6.54
    static func parse(_ text: String?) -> Double? {
        guard var text else { return nil }
        text = text.replacingOccurrences(of: "dB", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(text), value.isFinite, abs(value) < 60 else { return nil }
        return value
    }
}
