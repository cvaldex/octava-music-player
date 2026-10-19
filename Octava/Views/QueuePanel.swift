import SwiftUI

/// Panel lateral "A continuación": la cola editable (arrastrar para reordenar, quitar, saltar a una canción)
/// y el ajuste de seguir con una mezcla al terminar.
struct QueuePanel: View {
    @Environment(AppModel.self) private var model

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
                            Text(current.artist)
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
                Text(player.queue.isEmpty
                     ? "La cola está vacía. Reproduce un disco o una mezcla aleatoria."
                     : "No hay más canciones en la cola.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 20)
                Spacer(minLength: 0)
            } else {
                List {
                    ForEach(upcoming) { entry in
                        QueueRow(track: entry.track)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { player.jump(to: entry.id) }
                            .contextMenu {
                                Button("Reproducir ahora") { player.jump(to: entry.id) }
                                Button("Quitar de la cola") { player.removeEntry(entry.id) }
                                AddToPlaylistMenu(tracks: [entry.track], model: model)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .onMove { source, destination in
                        player.moveUpcoming(fromOffsets: source, toOffset: destination)
                    }
                    .onDelete { offsets in
                        player.removeUpcoming(atOffsets: offsets)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 40)
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
                Text(track.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
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
