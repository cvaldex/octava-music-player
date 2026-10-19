import SwiftUI

/// Panel lateral "A continuación": la cola editable (arrastrar para reordenar, quitar, saltar a una canción)
/// y el ajuste de seguir con una mezcla al terminar.
struct QueuePanel: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    @State private var selection = Set<UUID>()
    @State private var isDropTargeted = false

    var body: some View {
        let player = model.player
        let upcoming = Array(player.queue.upcoming)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("A continuación")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button {
                    model.saveQueueAsPlaylist()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(player.queue.isEmpty ? Theme.mutedIcon : Theme.secondaryText)
                .disabled(player.queue.isEmpty)
                .help("Guardar la cola como lista")
                .accessibilityLabel("Guardar la cola como lista")
                Button("Limpiar") {
                    // Limpiar también detiene la mezcla: si no, se volvería a rellenar al instante.
                    model.stopMix()
                    player.clearUpcoming()
                }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(upcoming.isEmpty ? Theme.mutedIcon : Theme.secondaryText)
                    .disabled(upcoming.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 12)

            if let mix = model.activeMix {
                HStack(spacing: 8) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(mix.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Text("Mezcla · se rellena sola")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer(minLength: 6)
                    Button("Detener") { model.stopMix() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                        .help("Dejar de agregar canciones (lo que está en la cola se mantiene)")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Theme.accentTint, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }

            if let current = player.queue.current {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("SONANDO")
                            .font(Theme.sectionLabel)
                            .tracking(0.6)
                            .foregroundStyle(Theme.tertiaryText)
                        Spacer()
                        StopAfterChip(player: player)
                    }
                    HStack(spacing: 10) {
                        PlayingBars(animating: player.isPlaying)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(current.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.accentText)
                                .lineLimit(1)
                            Text(current.album.isEmpty ? current.performer : "\(current.performer) · \(current.album)")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
            }

            if upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text(player.queue.isEmpty
                         ? "La cola está vacía. Reproduce un disco o una mezcla, o arrastra canciones aquí."
                         : "No hay más canciones en la cola. Arrastra canciones aquí para agregarlas.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 20)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(isDropTargeted ? Theme.accentTint : Color.clear)
                .contentShape(Rectangle())
                .onDrop(of: [.plainText], isTargeted: $isDropTargeted) { providers in
                    Task {
                        let ids = await TrackDrag.loadIDs(from: providers)
                        model.insertInQueue(trackIDs: ids, at: 0)
                    }
                    return true
                }
            } else {
                // Selección nativa de la lista: así arrastrar desde el ícono ≡ reordena (un gesto de doble clic
                // sobre la fila lo impedía), y el doble clic se maneja como acción principal.
                List(selection: $selection) {
                    ForEach(upcoming) { entry in
                        QueueRow(track: entry.track)
                            .tag(entry.id)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .onMove { source, destination in
                        player.moveUpcoming(fromOffsets: source, toOffset: destination)
                    }
                    .onDelete { offsets in
                        player.removeUpcoming(atOffsets: offsets)
                    }
                    // Canciones arrastradas desde tablas o discos: se insertan donde se sueltan.
                    .onInsert(of: [.plainText]) { offset, providers in
                        Task {
                            let ids = await TrackDrag.loadIDs(from: providers)
                            model.insertInQueue(trackIDs: ids, at: offset)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 40)
                .contextMenu(forSelectionType: UUID.self) { ids in
                    queueMenu(ids: ids, upcoming: upcoming)
                } primaryAction: { ids in
                    if let id = upcoming.first(where: { ids.contains($0.id) })?.id { player.jump(to: id) }
                }
                .onDeleteCommand {
                    for id in selection { player.removeEntry(id) }
                    selection.removeAll()
                }
            }

            Divider().overlay(Theme.separator)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Al terminar la cola")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Seguir con una mezcla aleatoria")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 8)
                Toggle("Seguir con una mezcla aleatoria",
                       isOn: Binding(get: { model.continueWithMix }, set: { model.continueWithMix = $0 }))
                    .toggleStyle(.switch)
                    .tint(Theme.accent)
                    .labelsHidden()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.queuePanel)
    }

    /// Mismas opciones que en las tablas y discos, más las propias de la cola.
    @ViewBuilder
    private func queueMenu(ids: Set<UUID>, upcoming: [QueueEntry]) -> some View {
        let entries = upcoming.filter { ids.contains($0.id) }
        // Clic derecho fuera de la selección: esa fila pasa a ser la selección.
        let _ = selectLater(ids)
        if let first = entries.first {
            let player = model.player
            if entries.count == 1 {
                Button("Reproducir ahora") { player.jump(to: first.id) }
            }
            Button(entries.count == 1 ? "Quitar de la cola" : "Quitar \(entries.count) canciones de la cola") {
                for entry in entries { player.removeEntry(entry.id) }
                selection.subtract(entries.map(\.id))
            }
            Divider()
            TrackActionsMenu(tracks: { entries.map(\.track) }, model: model, navigator: navigator, count: entries.count)
        }
    }

    private func selectLater(_ ids: Set<UUID>) {
        guard !ids.isEmpty, !ids.isSubset(of: selection) else { return }
        DispatchQueue.main.async { selection = ids }
    }
}

private struct QueueRow: View {
    let track: Track

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(Theme.mutedIcon)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(track.album.isEmpty ? track.performer : "\(track.performer) · \(track.album)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .help("\(track.performer) · \(track.album)")
            }
            Spacer(minLength: 8)
            Text(formatDuration(track.duration))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.tertiaryText)
        }
        .padding(.vertical, 2)
    }
}

/// "Detener al terminar": interruptor junto a la canción que suena.
private struct StopAfterChip: View {
    let player: PlaybackEngine

    var body: some View {
        let isOn = player.stopsAfterCurrent
        Button {
            player.toggleStopAfterCurrent()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "stop.circle\(isOn ? ".fill" : "")")
                Text(isOn ? "Se detiene al terminar" : "Detener al terminar")
            }
            .font(.system(size: 11, weight: isOn ? .semibold : .regular))
            .foregroundStyle(isOn ? Theme.accentText : Theme.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isOn ? Theme.accentTint : Color.clear, in: Capsule())
            .overlay(Capsule().stroke(isOn ? Color.clear : Theme.controlBorder))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Detener la reproducción cuando termine esta canción")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
