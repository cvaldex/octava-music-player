import AppKit
import SwiftUI

/// Ajustes (⌘,). Por ahora: la cuenta de Last.fm.
struct SettingsView: View {
    let model: AppModel

    /// Logo de Last.fm para la pestaña (a tamaño de ícono de barra de herramientas).
    private static let lastFMLogo: NSImage? = {
        guard let original = NSImage(named: "LastFMLogo"), let logo = original.copy() as? NSImage else { return nil }
        logo.size = NSSize(width: 24, height: 24)
        return logo
    }()

    var body: some View {
        TabView {
            LastFMSettings(scrobbler: model.scrobbler)
                .tabItem {
                    Label {
                        Text("Last.fm")
                    } icon: {
                        if let logo = Self.lastFMLogo {
                            Image(nsImage: logo).renderingMode(.original)
                        } else {
                            Image(systemName: "dot.radiowaves.left.and.right")
                        }
                    }
                }
        }
        .frame(width: 520)
        .preferredColorScheme(.light)
    }
}

private struct LastFMSettings: View {
    @Bindable var scrobbler: Scrobbler

    var body: some View {
        Form {
            Section {
                account
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
        .formStyle(.grouped)
        .padding(.vertical, 8)
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
