import SwiftUI

/// Ajustes (⌘,): generales y la cuenta de Last.fm, en una sola página
/// (sin pestañas: la barra de pestañas mostraba el logo de Last.fm en gris).
struct SettingsView: View {
    let model: AppModel
    @AppStorage("showsMenuBarPlayer") private var showsMenuBarPlayer = true

    var body: some View {
        Form {
            Section("General") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Carpeta de música")
                        Text(model.musicFolder.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "Sin elegir")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Cambiar…") { model.chooseFolder() }
                }
                Toggle("Mostrar el mini reproductor en la barra de menú", isOn: $showsMenuBarPlayer)
            }

            LastFMSettings(scrobbler: model.scrobbler)
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.surface)
        .navigationTitle("Ajustes")
        .preferredColorScheme(.light)
    }
}

/// Encabezado de la sección de Last.fm, con su logo.
private struct LastFMHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Image("LastFMLogo")
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Last.fm")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("Scrobbling y “Me encanta”")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .textCase(nil)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}

private struct LastFMSettings: View {
    @Bindable var scrobbler: Scrobbler

    var body: some View {
        Group {
            Section {
                account
            } header: {
                LastFMHeader()
            }

            Section {
                Toggle("Enviar lo que escucho (scrobbling)", isOn: $scrobbler.isEnabled)
                Toggle("Sincronizar favoritos con “Me encanta”", isOn: $scrobbler.syncsLoves)
            } footer: {
                Text("Una canción se registra al pasar la mitad o los 4 minutos (solo canciones de más de 30 segundos). Al marcar un favorito en Octava se marca “Me encanta” en Last.fm.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
            .disabled(!scrobbler.isConnected)

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(scrobbler.pendingCount == 0
                             ? "No hay scrobbles pendientes"
                             : countLabel(scrobbler.pendingCount, singular: "scrobble pendiente", plural: "scrobbles pendientes"))
                        if let sent = scrobbler.lastSentAt {
                            Text("Último envío: \(sent.formatted(date: .omitted, time: .shortened))")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    Spacer()
                    Button("Enviar ahora") { Task { await scrobbler.flush() } }
                        .disabled(scrobbler.pendingCount == 0 || !scrobbler.isConnected)
                }
            } footer: {
                Text("Sin conexión, los scrobbles se guardan y se envían después (Last.fm acepta hasta 14 días de antigüedad).")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }

            if let error = scrobbler.lastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.accentText)
                        .font(.system(size: 12))
                }
            }
        }
    }

    @ViewBuilder
    private var account: some View {
        if !scrobbler.isConfigured {
            VStack(alignment: .leading, spacing: 4) {
                Text("Falta configurar Last.fm")
                    .font(.system(size: 13, weight: .semibold))
                Text("Completa la API key y el shared secret en Octava/Config/Secrets.swift y vuelve a compilar.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
        } else if let username = scrobbler.username {
            HStack {
                Circle().fill(Theme.ok).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Conectado como \(username)")
                        .font(.system(size: 13, weight: .semibold))
                    Link("Ver perfil en Last.fm", destination: URL(string: "https://www.last.fm/user/\(LastFMAPI.percentEncode(username))")!)
                        .font(.system(size: 12))
                }
                Spacer()
                Button("Desconectar") { scrobbler.disconnect() }
            }
        } else if scrobbler.isAuthorizing {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Esperando la autorización…")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Se abrió Last.fm en el navegador: presiona “Yes, allow access” y vuelve a Octava.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Button("Cancelar") { scrobbler.cancelConnecting() }
            }
        } else {
            HStack {
                Circle().fill(Theme.mutedIcon).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sin conectar")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Conecta tu cuenta para registrar lo que escuchas.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Button("Conectar con Last.fm…") { scrobbler.connect() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        }
    }
}
