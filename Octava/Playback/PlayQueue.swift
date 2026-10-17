import Foundation

/// Una entrada de la cola. La misma canción puede aparecer varias veces, por eso cada entrada tiene su propio id.
struct QueueEntry: Identifiable, Equatable {
    let id: UUID
    let track: Track

    init(track: Track) {
        self.id = UUID()
        self.track = track
    }
}

/// Modo de repetición.
enum RepeatMode: String, CaseIterable, Identifiable {
    case off, all, one

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Sin repetir"
        case .all: "Repetir todo"
        case .one: "Repetir una"
        }
    }

    /// Siguiente modo al presionar el botón de repetir.
    var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}

/// Cola de reproducción. Un solo modelo sirve para ambos modos:
/// un disco es la cola ordenada por número de pista; una mezcla es la cola barajada.
/// Lógica pura, sin audio, para poder testearla.
struct PlayQueue: Equatable {
    private(set) var items: [QueueEntry] = []
    /// Índice de la pista actual. Es nil solo cuando la cola está vacía.
    private(set) var currentIndex: Int?

    var currentEntry: QueueEntry? {
        guard let currentIndex, items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    var current: Track? { currentEntry?.track }

    /// Lo que viene después de la pista actual.
    var upcoming: ArraySlice<QueueEntry> {
        guard let currentIndex else { return [] }
        return items[(currentIndex + 1)...]
    }

    var isEmpty: Bool { items.isEmpty }

    // MARK: Navegación

    mutating func replace(with tracks: [Track], startAt index: Int = 0) {
        items = tracks.map(QueueEntry.init(track:))
        currentIndex = items.isEmpty ? nil : (items.indices.contains(index) ? index : 0)
    }

    /// Índice de la pista que sigue a la actual.
    /// - automatic: true cuando la pista terminó sola (con "repetir una" vuelve a la misma);
    ///   false cuando el usuario presiona "siguiente".
    func indexAfterCurrent(repeatMode: RepeatMode, automatic: Bool) -> Int? {
        guard let currentIndex else { return nil }
        if repeatMode == .one && automatic { return currentIndex }
        if currentIndex + 1 < items.count { return currentIndex + 1 }
        if repeatMode == .all && !items.isEmpty { return 0 }
        return nil
    }

    func index(ofEntry id: UUID) -> Int? {
        items.firstIndex { $0.id == id }
    }

    mutating func select(_ index: Int) {
        guard items.indices.contains(index) else { return }
        currentIndex = index
    }

    /// Avanza a la pista siguiente sin repetir. Al final de la cola devuelve nil y se queda en la última.
    @discardableResult
    mutating func advance() -> Track? {
        guard let next = indexAfterCurrent(repeatMode: .off, automatic: false) else { return nil }
        currentIndex = next
        return current
    }

    /// Retrocede una pista. Devuelve false si ya estaba en la primera.
    @discardableResult
    mutating func goBack() -> Bool {
        guard let index = currentIndex, index > 0 else { return false }
        currentIndex = index - 1
        return true
    }

    /// Vuelve al principio de la cola (al terminar la reproducción).
    mutating func rewind() {
        currentIndex = items.isEmpty ? nil : 0
    }

    // MARK: Edición

    /// Inserta canciones justo después de la actual ("Reproducir a continuación").
    mutating func playNext(_ tracks: [Track]) {
        let entries = tracks.map(QueueEntry.init(track:))
        guard let currentIndex else {
            items = entries
            self.currentIndex = items.isEmpty ? nil : 0
            return
        }
        items.insert(contentsOf: entries, at: currentIndex + 1)
    }

    /// Agrega canciones al final de la cola.
    mutating func append(_ tracks: [Track]) {
        items.append(contentsOf: tracks.map(QueueEntry.init(track:)))
        if currentIndex == nil && !items.isEmpty {
            currentIndex = 0
        }
    }

    /// Quita una entrada que no sea la actual.
    mutating func remove(entryID: UUID) {
        guard let index = index(ofEntry: entryID), index != currentIndex else { return }
        items.remove(at: index)
        if let current = currentIndex, index < current {
            currentIndex = current - 1
        }
    }

    /// Quita entradas de lo que viene; los índices son relativos a `upcoming`.
    mutating func removeUpcoming(atOffsets offsets: IndexSet) {
        guard let currentIndex else { return }
        let base = currentIndex + 1
        for offset in offsets.sorted(by: >) where base + offset < items.count {
            items.remove(at: base + offset)
        }
    }

    /// Reordena lo que viene; los índices son relativos a `upcoming` (como los entrega `onMove` de SwiftUI).
    mutating func moveUpcoming(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard let currentIndex else { return }
        let base = currentIndex + 1
        var upcoming = Array(items[base...])
        let valid = source.filter { $0 < upcoming.count }.sorted()
        guard !valid.isEmpty else { return }

        let moving = valid.map { upcoming[$0] }
        for offset in valid.reversed() {
            upcoming.remove(at: offset)
        }
        let adjusted = destination - valid.filter { $0 < destination }.count
        upcoming.insert(contentsOf: moving, at: min(max(0, adjusted), upcoming.count))
        items.replaceSubrange(base..., with: upcoming)
    }

    /// Descarta las canciones ya reproducidas más antiguas, conservando las últimas `keeping` (para "anterior").
    mutating func trimHistory(keeping: Int) {
        guard let currentIndex, currentIndex > keeping else { return }
        let dropCount = currentIndex - keeping
        items.removeFirst(dropCount)
        self.currentIndex = currentIndex - dropCount
    }

    mutating func clearUpcoming() {
        guard let currentIndex else { return }
        items.removeSubrange((currentIndex + 1)...)
    }
}
