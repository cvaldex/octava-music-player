import Foundation

/// Cola de reproducción. Un solo modelo sirve para ambos modos:
/// un disco es la cola ordenada por número de pista; una mezcla es la cola barajada.
/// Lógica pura, sin audio, para poder testearla.
struct PlayQueue: Equatable {
    private(set) var items: [Track] = []
    private(set) var currentIndex: Int?

    var current: Track? {
        guard let currentIndex, items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    /// Lo que viene después de la pista actual.
    var upcoming: ArraySlice<Track> {
        guard let currentIndex else { return items[...] }
        let start = currentIndex + 1
        return start < items.count ? items[start...] : []
    }

    var hasNext: Bool {
        guard let currentIndex else { return !items.isEmpty }
        return currentIndex + 1 < items.count
    }

    mutating func replace(with tracks: [Track], startAt index: Int = 0) {
        items = tracks
        currentIndex = tracks.indices.contains(index) ? index : (tracks.isEmpty ? nil : 0)
    }

    /// Avanza a la siguiente pista. Devuelve nil (y deja la cola sin pista actual) al terminar.
    @discardableResult
    mutating func advance() -> Track? {
        guard let index = currentIndex else { return nil }
        if index + 1 < items.count {
            currentIndex = index + 1
            return current
        }
        currentIndex = nil
        return nil
    }

    /// Retrocede a la pista anterior; en la primera, se queda en ella.
    @discardableResult
    mutating func goBack() -> Track? {
        guard let index = currentIndex else { return nil }
        currentIndex = max(0, index - 1)
        return current
    }

    /// Agrega una pista justo después de la actual ("Reproducir a continuación").
    mutating func playNext(_ track: Track) {
        let insertAt = (currentIndex ?? -1) + 1
        items.insert(track, at: min(insertAt, items.count))
    }

    /// Agrega una pista al final de la cola.
    mutating func append(_ track: Track) {
        items.append(track)
    }

    /// Quita una pista de lo que viene (índice absoluto en `items`).
    mutating func remove(at index: Int) {
        guard items.indices.contains(index), index != currentIndex else { return }
        items.remove(at: index)
        if let current = currentIndex, index < current {
            currentIndex = current - 1
        }
    }

    mutating func clearUpcoming() {
        guard let currentIndex else { items.removeAll(); return }
        items.removeSubrange((currentIndex + 1)...)
    }
}
