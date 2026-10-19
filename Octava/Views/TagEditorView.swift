import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Editor de tags (hoja). Con una canción se editan todos los campos; con varias, solo los comunes:
/// los que tienen valores distintos muestran "Varios valores · se conservan" y no se tocan si no se escriben.
/// Recibe el modelo explícitamente (las hojas no heredan bien el entorno en todas las versiones de macOS).
struct TagEditorView: View {
    let model: AppModel
    let tracks: [Track]

    @Environment(\.dismiss) private var dismiss

    /// Valor común de cada campo; nil = las canciones tienen valores distintos.
    private let originals: [TagField: String?]
    @State private var values: [TagField: String]
    @State private var newArtwork: TagChanges.Artwork?
    @State private var newArtworkImage: NSImage?
    @State private var artworkError: String?
    @State private var isSaving = false

    init(model: AppModel, tracks: [Track]) {
        self.model = model
        self.tracks = tracks
        var originals: [TagField: String?] = [:]
        var values: [TagField: String] = [:]
        for field in TagField.allCases {
            let all = Set(tracks.map { Self.value(of: field, in: $0) })
            let common: String? = all.count == 1 ? all.first : nil
            originals[field] = common
            values[field] = common ?? ""
        }
        self.originals = originals
        _values = State(initialValue: values)
    }

    private var isBatch: Bool { tracks.count > 1 }

    /// En lote no se editan título ni número de pista (son propios de cada canción).
    private func isEditable(_ field: TagField) -> Bool {
        !(isBatch && (field == .title || field == .trackNumber))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 18)

            HStack(alignment: .top, spacing: 28) {
                coverColumn
                fieldsColumn
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 22)

            Divider().overlay(Theme.separator)
            footer
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
        }
        .frame(width: 720)
        .background(Theme.surface)
        .disabled(isSaving)
    }

    // MARK: Encabezado

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Editar tags")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
        }
    }

    private var subtitle: String {
        if !isBatch, let track = tracks.first {
            return "\(track.title) · \(track.performer)"
        }
        let albums = Set(tracks.map(\.album))
        let count = countLabel(tracks.count, singular: "canción seleccionada", plural: "canciones seleccionadas")
        return albums.count == 1 ? "\(count) de \(albums.first ?? "")" : "\(count) de \(albums.count) discos"
    }

    // MARK: Carátula

    private var coverColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                if let newArtworkImage {
                    Image(nsImage: newArtworkImage)
                        .resizable()
                        .scaledToFill()
                } else if let album = currentAlbum {
                    AlbumCoverView(album: album, cornerRadius: 0)
                } else {
                    Theme.control
                    VStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 22))
                        Text("Varias carátulas")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(width: 148, height: 148)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(newArtwork != nil ? Theme.accent : Theme.separator, lineWidth: newArtwork != nil ? 1.5 : 1))
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                return loadArtwork(from: url)
            }

            Button("Cambiar carátula…") { chooseArtwork() }
                .buttonStyle(OutlineButtonStyle())

            if newArtwork != nil {
                Button("Descartar carátula nueva") {
                    newArtwork = nil
                    newArtworkImage = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.accentText)
            }

            Text(artworkError ?? "Se incrusta en cada archivo. También puedes arrastrar una imagen.")
                .font(.system(size: 11))
                .foregroundStyle(artworkError == nil ? Theme.secondaryText : Theme.accentText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 148)
    }

    /// Disco cuya carátula se muestra (si todas las canciones son del mismo).
    private var currentAlbum: Album? {
        let ids = Set(tracks.map(\.albumId))
        guard ids.count == 1 else { return nil }
        return model.library.album(id: tracks.first?.albumId)
    }

    private func chooseArtwork() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Usar imagen"
        panel.message = "Elige la carátula para \(isBatch ? "estas canciones" : "esta canción")"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = loadArtwork(from: url)
    }

    private func loadArtwork(from url: URL) -> Bool {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let artwork = ArtworkImport.prepare(data),
              let image = NSImage(data: artwork.data) else {
            artworkError = "No se pudo usar esa imagen."
            return false
        }
        artworkError = nil
        newArtwork = artwork
        newArtworkImage = image
        return true
    }

    // MARK: Campos

    private var fieldsColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !isBatch {
                fieldEditor(.title)
            }
            fieldEditor(.album)
            HStack(alignment: .top, spacing: 14) {
                fieldEditor(.albumArtist)
                fieldEditor(.artist)
            }
            HStack(alignment: .top, spacing: 14) {
                fieldEditor(.year, compact: true).frame(width: 110)
                fieldEditor(.genre)
                if isBatch {
                    fieldEditor(.discNumber, compact: true).frame(width: 110)
                }
            }
            if !isBatch {
                HStack(alignment: .top, spacing: 14) {
                    fieldEditor(.trackNumber, compact: true).frame(width: 110)
                    fieldEditor(.discNumber, compact: true).frame(width: 110)
                    Spacer(minLength: 0)
                }
            }
            if isBatch {
                TagFieldBox(label: "Título y número de pista",
                            note: nil,
                            text: .constant(""),
                            placeholder: "Se editan canción por canción",
                            style: .disabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fieldEditor(_ field: TagField, compact: Bool = false) -> some View {
        let original = originals[field] ?? nil
        let isMixed = original == nil
        let modified = isModified(field)
        let error = validationError(field)

        let note: String?
        let style: TagFieldBox.Style
        if let error {
            note = error
            style = .modified
        } else if modified {
            let before = original.map { $0.isEmpty ? "vacío" : $0 } ?? "varios valores"
            note = "modificado (antes \(before))"
            style = .modified
        } else if isMixed {
            note = nil
            style = .mixed
        } else {
            note = nil
            style = .normal
        }

        return TagFieldBox(label: field.label,
                           note: note,
                           text: Binding(get: { values[field] ?? "" }, set: { values[field] = $0 }),
                           placeholder: isMixed ? (compact ? "Varios valores" : "Varios valores · se conservan") : "",
                           style: isEditable(field) ? style : .disabled)
    }

    private func isModified(_ field: TagField) -> Bool {
        guard isEditable(field) else { return false }
        let value = (values[field] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let original = originals[field] ?? nil else { return !value.isEmpty }
        return value != original
    }

    private func validationError(_ field: TagField) -> String? {
        guard isModified(field) else { return nil }
        let value = (values[field] ?? "").trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        switch field {
        case .year:
            return value.count == 4 && value.allSatisfy(\.isNumber) ? nil : "año de 4 dígitos"
        case .trackNumber, .discNumber:
            return value.allSatisfy(\.isNumber) && (Int(value) ?? 0) > 0 ? nil : "solo un número"
        default:
            return nil
        }
    }

    private var changes: TagChanges {
        var changes = TagChanges()
        for field in TagField.allCases where isModified(field) {
            changes.text[field] = (values[field] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        changes.artwork = newArtwork
        return changes
    }

    private var hasErrors: Bool {
        TagField.allCases.contains { validationError($0) != nil }
    }

    // MARK: Pie

    private var footer: some View {
        let changes = self.changes
        return HStack(spacing: 12) {
            Text(summary(for: changes))
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            if isSaving {
                ProgressView().controlSize(.small)
                Text("Guardando…")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
            Button("Cancelar") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button {
                save(changes)
            } label: {
                Text("Guardar cambios").font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(AccentButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(changes.isEmpty || hasErrors || isSaving)
        }
    }

    private func summary(for changes: TagChanges) -> String {
        guard !changes.isEmpty else {
            return "Modifica un campo o la carátula para guardar."
        }
        var parts = TagField.allCases.filter { changes.text[$0] != nil }.map(\.phrase)
        if changes.artwork != nil { parts.append("la carátula") }
        let what: String
        switch parts.count {
        case 1: what = parts[0]
        case 2: what = "\(parts[0]) y \(parts[1])"
        default: what = "\(parts.count) campos"
        }
        let files = countLabel(tracks.count, singular: "archivo MP3", plural: "archivos MP3")
        return "Se escribirá \(what) en \(files). Puedes deshacerlo desde Edición › Deshacer edición de tags."
    }

    private func save(_ changes: TagChanges) {
        isSaving = true
        Task {
            await model.saveTagEdit(changes, to: tracks)
            isSaving = false
            // Se cierra también si hubo errores: el aviso se muestra en la ventana principal.
            dismiss()
        }
    }

    // MARK: Valores

    static func value(of field: TagField, in track: Track) -> String {
        switch field {
        case .title: track.title
        case .artist: track.artist
        case .albumArtist: track.albumArtist ?? ""
        case .album: track.album
        case .trackNumber: track.trackNumber.map(String.init) ?? ""
        case .discNumber: track.discNumber.map(String.init) ?? ""
        case .year: track.year.map(String.init) ?? ""
        case .genre: track.genre ?? ""
        }
    }
}

/// Campo de texto del editor con sus tres estados visuales (normal, modificado, varios valores).
private struct TagFieldBox: View {
    enum Style { case normal, modified, mixed, disabled }

    let label: String
    let note: String?
    @Binding var text: String
    let placeholder: String
    let style: Style

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(style == .disabled ? Theme.mutedIcon : Theme.navText)

            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.tertiaryText))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(style == .disabled ? Theme.queuePanel : Theme.surface, in: RoundedRectangle(cornerRadius: 7))
                .overlay(border)
                .disabled(style == .disabled)
                .help(style == .mixed ? "Las canciones tienen valores distintos; si no escribes nada, se conservan" : "")

            if let note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accentText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var border: some View {
        let shape = RoundedRectangle(cornerRadius: 7)
        switch style {
        case .modified:
            shape.stroke(Theme.accent, lineWidth: 1.5)
        case .mixed:
            shape.stroke(Theme.controlBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        case .normal, .disabled:
            shape.stroke(Theme.controlBorder, lineWidth: 1)
        }
    }
}

/// Prepara una imagen para incrustarla: JPEG o PNG de tamaño razonable se usan tal cual;
/// el resto se convierte a JPEG de 1400 px como máximo.
enum ArtworkImport {
    static let maxDimension = 1600
    static let maxBytes = 3 * 1024 * 1024

    static func prepare(_ data: Data) -> TagChanges.Artwork? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String?,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard width > 0, height > 0 else { return nil }

        let isJPEG = type == UTType.jpeg.identifier
        let isPNG = type == UTType.png.identifier
        if (isJPEG || isPNG), max(width, height) <= maxDimension, data.count <= maxBytes {
            return TagChanges.Artwork(data: data, mimeType: isJPEG ? "image/jpeg" : "image/png")
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1400
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return TagChanges.Artwork(data: output as Data, mimeType: "image/jpeg")
    }
}
