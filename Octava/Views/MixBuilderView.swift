import SwiftUI

/// Ventana para armar una mezcla con filtros: origen, décadas, géneros y artistas.
/// La mezcla resultante se rellena sola (siempre 100 canciones por delante).
struct MixBuilderView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var rule = MixRule()
    @State private var artistQuery = ""

    var body: some View {
        let library = model.library
        let available = model.mixCandidates(for: rule).count
        let decades = MixBuilder.decades(in: library.tracks)
        let genres = library.genres.map(\.name)

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Nueva mezcla")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("Dentro de cada filtro se suman las opciones; entre filtros se combinan. Sin marcar nada, vale todo.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("Origen") {
                        Picker("Origen", selection: $rule.source) {
                            ForEach(MixSource.allCases) { source in
                                Text(source.title).tag(source)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }

                    if !decades.isEmpty {
                        section("Décadas") {
                            ChipFlow(items: decades.map { ($0, MixRule.decadeLabel($0)) },
                                     selected: Set(rule.decades)) { decade in
                                toggle(decade, in: &rule.decades)
                            }
                        }
                    }

                    if !genres.isEmpty {
                        section("Géneros") {
                            ChipFlow(items: genres.map { ($0, $0) }, selected: Set(rule.genres)) { genre in
                                toggle(genre, in: &rule.genres)
                            }
                        }
                    }

                    section("Artistas") {
                        artistPicker(library: library)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            Divider().overlay(Theme.separator)

            HStack(spacing: 12) {
                Text(available == 0 ? "Ninguna canción calza" : "\(countLabel(available, singular: "canción disponible", plural: "canciones disponibles"))")
                    .font(Theme.mono(12))
                    .foregroundStyle(available == 0 ? Theme.accentText : Theme.secondaryText)
                Spacer()
                if rule != MixRule() {
                    Button("Limpiar filtros") { rule = MixRule() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                }
                Button("Cancelar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    model.startMix(rule)
                    dismiss()
                } label: {
                    Label("Crear mezcla", systemImage: "shuffle")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(AccentButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(available == 0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 620, height: 600)
        .background(Theme.surface)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(Theme.sectionLabel)
                .tracking(0.6)
                .foregroundStyle(Theme.tertiaryText)
            content()
        }
    }

    private func artistPicker(library: LibraryStore) -> some View {
        let query = artistQuery.trimmingCharacters(in: .whitespaces)
        let all = library.artists.map(\.name)
        let shown = query.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(query) }

        return VStack(alignment: .leading, spacing: 8) {
            if !rule.artists.isEmpty {
                ChipFlow(items: rule.artists.map { ($0, $0) }, selected: Set(rule.artists), removable: true) { artist in
                    toggle(artist, in: &rule.artists)
                }
            }
            TextField("Buscar artista", text: $artistQuery)
                .textFieldStyle(.roundedBorder)
            List(shown, id: \.self) { name in
                let isOn = rule.artists.contains(name)
                Button {
                    toggle(name, in: &rule.artists)
                } label: {
                    HStack {
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isOn ? Theme.accent : Theme.mutedIcon)
                        Text(name)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: false))
            .frame(height: 170)
        }
    }

    private func toggle<T: Equatable>(_ value: T, in list: inout [T]) {
        if let index = list.firstIndex(of: value) {
            list.remove(at: index)
        } else {
            list.append(value)
        }
    }
}

/// Fichas seleccionables que se acomodan en varias líneas.
private struct ChipFlow<Value: Hashable>: View {
    let items: [(Value, String)]
    let selected: Set<Value>
    var removable = false
    let onToggle: (Value) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                let (value, label) = items[index]
                let isOn = selected.contains(value)
                Button {
                    onToggle(value)
                } label: {
                    HStack(spacing: 4) {
                        Text(label)
                        if removable { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    }
                    .font(.system(size: 12, weight: isOn ? .semibold : .regular))
                    .foregroundStyle(isOn ? Color.white : Theme.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(isOn ? Theme.accent : Theme.control, in: Capsule())
                    .overlay(Capsule().stroke(isOn ? Color.clear : Theme.controlBorder))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Distribución en líneas (como texto): cada elemento a su tamaño ideal, saltando de línea al no caber.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width && !current.indices.isEmpty {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
