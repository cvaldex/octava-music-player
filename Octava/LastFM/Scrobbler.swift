import AppKit
import Foundation
import Observation

/// Last.fm: conexión de la cuenta, "now playing", scrobbles con cola sin conexión y "Me encanta" de los favoritos.
@MainActor
@Observable
final class Scrobbler {
    /// Usuario conectado (nil = sin conectar).
    private(set) var username: String?
    private(set) var isAuthorizing = false
    private(set) var pendingCount = 0
    private(set) var lastError: String?
    private(set) var lastSentAt: Date?
    /// La canción actual ya pasó el punto de scrobble.
    private(set) var currentScrobbled = false

    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.enabled) }
    }
    var syncsLoves: Bool {
        didSet { defaults.set(syncsLoves, forKey: Keys.syncsLoves) }
    }

    var isConnected: Bool { username != nil }
    var isConfigured: Bool { client.isConfigured }

    /// Reintentos de un lote que Last.fm rechaza (no por falta de conexión) antes de descartarlo.
    static let maxAttempts = 3
    static let retryDelay: Duration = .seconds(300)

    @ObservationIgnored private let client: LastFMClient
    @ObservationIgnored private let database: AppDatabase
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var cachedSessionKey: String?
    @ObservationIgnored private var authTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var isFlushing = false

    // Seguimiento de la canción actual.
    @ObservationIgnored private var currentEntryID: UUID?
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var nowPlayingSent = false

    private enum Keys {
        static let username = "lastfmUsername"
        static let enabled = "lastfmScrobblingEnabled"
        static let syncsLoves = "lastfmSyncLoves"
    }

    init(database: AppDatabase,
         client: LastFMClient = LastFMClient(apiKey: Secrets.lastFMAPIKey, secret: Secrets.lastFMSharedSecret),
         defaults: UserDefaults = .standard) {
        self.database = database
        self.client = client
        self.defaults = defaults
        username = defaults.string(forKey: Keys.username)
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        syncsLoves = defaults.object(forKey: Keys.syncsLoves) as? Bool ?? true
        pendingCount = database.pendingScrobbleCount
    }

    // MARK: Cuenta

    /// Autenticación de escritorio: abre Last.fm en el navegador y espera a que el usuario autorice.
    func connect() {
        guard isConfigured else {
            lastError = "Falta la API key o el shared secret de Last.fm (Octava/Config/Secrets.swift)."
            return
        }
        guard !isAuthorizing else { return }
        isAuthorizing = true
        lastError = nil
        authTask = Task {
            defer { isAuthorizing = false }
            do {
                let token = try await client.getToken()
                NSWorkspace.shared.open(client.authorizationURL(token: token))
                // El token vale 60 minutos; se consulta cada 3 s durante 10 minutos.
                for _ in 0..<200 {
                    try await Task.sleep(for: .seconds(3))
                    do {
                        let session = try await client.getSession(token: token)
                        finishConnecting(username: session.username, key: session.key)
                        return
                    } catch let error as LastFMError where error.code == LastFMError.tokenNotAuthorized {
                        continue
                    }
                }
                lastError = "No llegó la autorización de Last.fm. Vuelve a intentarlo."
            } catch is CancellationError {
                // Cancelado por el usuario.
            } catch {
                lastError = "No se pudo conectar con Last.fm: \(error.localizedDescription)"
            }
        }
    }

    func cancelConnecting() {
        authTask?.cancel()
        authTask = nil
        isAuthorizing = false
    }

    private func finishConnecting(username: String, key: String) {
        guard Keychain.save(key, account: username) else {
            lastError = "No se pudo guardar la sesión en el Llavero."
            return
        }
        cachedSessionKey = key
        self.username = username
        defaults.set(username, forKey: Keys.username)
        lastError = nil
        NSApp.activate(ignoringOtherApps: true)
        Task { await flush() }
    }

    /// Desconecta la cuenta. Los scrobbles pendientes se conservan hasta volver a conectar (o que caduquen).
    func disconnect() {
        if let username { Keychain.delete(account: username) }
        username = nil
        cachedSessionKey = nil
        defaults.removeObject(forKey: Keys.username)
        retryTask?.cancel()
    }

    private func sessionKey() -> String? {
        if let cachedSessionKey { return cachedSessionKey }
        guard let username else { return nil }
        cachedSessionKey = Keychain.read(account: username)
        return cachedSessionKey
    }

    private func sessionExpired() {
        disconnect()
        lastError = "La sesión de Last.fm ya no es válida. Vuelve a conectar la cuenta en Ajustes."
    }

    // MARK: Reproducción

    /// Se llama a menudo con el estado del reproductor: envía "now playing" al empezar una canción y la deja en la
    /// cola de scrobbles al pasar el punto (la mitad o 4 minutos; canciones de más de 30 s).
    func update(entryID: UUID?, track: Track?, isPlaying: Bool, position: TimeInterval) {
        guard let entryID, let track else {
            currentEntryID = nil
            return
        }
        if entryID != currentEntryID {
            currentEntryID = entryID
            startedAt = Date().addingTimeInterval(-position)
            nowPlayingSent = false
            // Retomada más allá del punto de scrobble (por ejemplo al reabrir la app): ya se contó antes.
            let threshold = scrobbleThreshold(forDuration: track.duration)
            currentScrobbled = threshold.map { position >= $0 } ?? false
        }
        guard isPlaying else { return }

        if !nowPlayingSent {
            nowPlayingSent = true
            sendNowPlaying(track)
        }
        if !currentScrobbled, let threshold = scrobbleThreshold(forDuration: track.duration), position >= threshold {
            currentScrobbled = true
            scrobble(ScrobbleItem(track: track, startedAt: startedAt))
        }
    }

    /// Terminó la canción: si vuelve a sonar (repetir una), cuenta como otra escucha.
    func trackFinished() {
        currentEntryID = nil
    }

    private func sendNowPlaying(_ track: Track) {
        guard isEnabled, isConnected, let key = sessionKey() else { return }
        let item = ScrobbleItem(track: track, startedAt: Date())
        Task {
            do {
                try await client.updateNowPlaying(item, sessionKey: key)
            } catch let error as LastFMError where error.code == LastFMError.invalidSession {
                sessionExpired()
            } catch {
                // "Now playing" es informativo: si falla, no se reintenta.
            }
        }
    }

    private func scrobble(_ item: ScrobbleItem) {
        guard isEnabled, isConnected else { return }
        do {
            try database.enqueueScrobble(item)
        } catch {
            lastError = "No se pudo guardar el scrobble: \(error.localizedDescription)"
            return
        }
        pendingCount = database.pendingScrobbleCount
        Task { await flush() }
    }

    // MARK: Cola

    /// Envía los scrobbles pendientes en lotes de 50, los más antiguos primero.
    func flush() async {
        pendingCount = database.pendingScrobbleCount
        guard isConnected, isConfigured, isEnabled, !isFlushing, pendingCount > 0, let key = sessionKey() else { return }
        isFlushing = true
        defer {
            isFlushing = false
            pendingCount = database.pendingScrobbleCount
        }
        try? database.dropScrobbles(olderThan: Date().addingTimeInterval(-LastFMAPI.maxScrobbleAge))

        while true {
            let batch = database.pendingScrobbles(limit: LastFMAPI.maxBatch)
            guard !batch.isEmpty else { break }
            let ids = batch.map(\.id)
            do {
                try await client.scrobble(batch.map(\.item), sessionKey: key)
                try? database.deleteScrobbles(ids)
                lastError = nil
                lastSentAt = Date()
            } catch let error as LastFMError {
                lastError = "Scrobbles pendientes: \(error.message)"
                if error.code == LastFMError.invalidSession {
                    sessionExpired()
                } else if error.isTemporary {
                    scheduleRetry()
                } else {
                    try? database.markScrobblesFailed(ids, maxAttempts: Self.maxAttempts)
                    scheduleRetry()
                }
                return
            } catch {
                lastError = error.localizedDescription
                scheduleRetry()
                return
            }
        }
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task {
            try? await Task.sleep(for: Self.retryDelay)
            guard !Task.isCancelled else { return }
            await flush()
        }
    }

    // MARK: Favoritos

    /// Marca o desmarca "Me encanta" en Last.fm al cambiar un favorito en Octava.
    func setLoved(_ loved: Bool, track: Track) {
        guard syncsLoves, isConnected, let key = sessionKey() else { return }
        Task {
            do {
                try await client.setLoved(loved, artist: track.artist, title: track.title, sessionKey: key)
            } catch let error as LastFMError where error.code == LastFMError.invalidSession {
                sessionExpired()
            } catch {
                lastError = "No se pudo actualizar “Me encanta” en Last.fm: \(error.localizedDescription)"
            }
        }
    }
}
