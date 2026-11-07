import SwiftUI

/// Filtro dentro de una lista (campo "Filtrar" de listas, listas fijas, Favoritos y Canciones).
/// Calza si cada palabra escrita aparece en el título, el artista o el álbum, sin distinguir mayúsculas ni tildes.
enum ListFilter {
    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    static func words(_ query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func matches(_ track: Track, query: String) -> Bool {
        let words = words(query)
        guard !words.isEmpty else { return true }
        let fields = [track.title, track.performer, track.artist, track.album]
        return words.allSatisfy { word in fields.contains { $0.range(of: word, options: options) != nil } }
    }

    static func apply(_ tracks: [Track], query: String) -> [Track] {
        words(query).isEmpty ? tracks : tracks.filter { matches($0, query: query) }
    }

    /// El texto con las partes que calzan destacadas (color de acento y fondo suave).
    static func highlighted(_ text: String, query: String) -> AttributedString {
        var result = AttributedString(text)
        for word in words(query) {
            var start = result.startIndex
            while start < result.endIndex, let range = result[start...].range(of: word, options: options) {
                result[range].foregroundColor = Theme.accentText
                result[range].backgroundColor = Theme.accentTint
                start = range.upperBound
            }
        }
        return result
    }

    /// "8 de 330 canciones" cuando hay filtro; "330 canciones" si no.
    static func countLabel(shown: Int, total: Int) -> String {
        let all = Octava.countLabel(total, singular: "canción", plural: "canciones")
        return shown == total ? all : "\(shown.formatted()) de \(all)"
    }
}

/// Campo "Filtrar" bajo el encabezado de una lista.
struct FilterField: View {
    @Binding var text: String
    var prompt = "Filtrar por título, artista o álbum"

    var body: some View {
        let isActive = !text.isEmpty
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 12))
                .foregroundStyle(isActive ? Theme.accent : Theme.secondaryText)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onExitCommand { text = "" }
            if isActive {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.mutedIcon)
                }
                .buttonStyle(.plain)
                .help("Quitar el filtro")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(width: 280)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(isActive ? Theme.accent : Theme.controlBorder, lineWidth: isActive ? 1.5 : 1))
    }
}

/// Mensaje cuando el filtro no deja ninguna canción.
struct NoFilterMatches: View {
    let query: String

    var body: some View {
        ContentUnavailableView("Ninguna canción calza con “\(query)”",
                               systemImage: "line.3.horizontal.decrease",
                               description: Text("Prueba con otra palabra o quita el filtro."))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
