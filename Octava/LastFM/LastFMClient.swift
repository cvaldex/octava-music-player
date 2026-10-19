import CryptoKit
import Foundation

/// Una canción para enviar a Last.fm (scrobble o "now playing").
struct ScrobbleItem: Codable, Equatable, Sendable {
    var artist: String
    var title: String
    var album: String?
    var albumArtist: String?
    var trackNumber: Int?
    var duration: Double
    /// Cuándo empezó a sonar (Last.fm lo pide como marca de tiempo Unix).
    var startedAt: Date

    init(track: Track, startedAt: Date) {
        artist = track.artist
        title = track.title
        album = track.album.isEmpty ? nil : track.album
        albumArtist = track.albumArtist.flatMap { $0.isEmpty || $0 == track.artist ? nil : $0 }
        trackNumber = track.trackNumber
        duration = track.duration
        self.startedAt = startedAt
    }

    init(artist: String, title: String, album: String?, albumArtist: String?, trackNumber: Int?, duration: Double, startedAt: Date) {
        self.artist = artist
        self.title = title
        self.album = album
        self.albumArtist = albumArtist
        self.trackNumber = trackNumber
        self.duration = duration
        self.startedAt = startedAt
    }
}

/// Error de la API de Last.fm (o de red).
struct LastFMError: LocalizedError, Equatable {
    var code: Int?
    var message: String

    var errorDescription: String? { message }

    /// Códigos de la API: https://www.last.fm/api/errorcodes
    static let invalidSession = 9
    static let tokenNotAuthorized = 14
    static let tokenExpired = 15

    /// Vale la pena reintentar más tarde (sin conexión, servicio caído, límite de pedidos).
    var isTemporary: Bool {
        guard let code else { return true } // red
        return [8, 11, 16, 29].contains(code)
    }
}

/// Construcción, firma y lectura de pedidos a la API de Last.fm. Lógica pura, testeada.
enum LastFMAPI {
    static let endpoint = URL(string: "https://ws.audioscrobbler.com/2.0/")!
    static let authPage = "https://www.last.fm/api/auth/"
    /// Last.fm acepta hasta 50 scrobbles por pedido.
    static let maxBatch = 50
    /// Last.fm rechaza scrobbles de hace más de 14 días.
    static let maxScrobbleAge: TimeInterval = 14 * 24 * 3600

    /// Firma: parámetros (sin `format` ni `callback`) ordenados por nombre, "nombrevalor" concatenados,
    /// más el secreto, en MD5 hexadecimal.
    static func signature(for parameters: [String: String], secret: String) -> String {
        let joined = parameters
            .filter { $0.key != "format" && $0.key != "callback" }
            .sorted { $0.key < $1.key }
            .map { $0.key + $0.value }
            .joined()
        let digest = Insecure.MD5.hash(data: Data((joined + secret).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Parámetros completos de un método: agrega method, api_key, sk (si hay), api_sig y format=json.
    static func signedParameters(method: String, parameters: [String: String], apiKey: String,
                                 secret: String, sessionKey: String?) -> [String: String] {
        var all = parameters
        all["method"] = method
        all["api_key"] = apiKey
        if let sessionKey { all["sk"] = sessionKey }
        all["api_sig"] = signature(for: all, secret: secret)
        all["format"] = "json"
        return all
    }

    static func formBody(_ parameters: [String: String]) -> Data {
        Data(query(parameters).utf8)
    }

    static func query(_ parameters: [String: String]) -> String {
        parameters.sorted { $0.key < $1.key }
            .map { "\(percentEncode($0.key))=\(percentEncode($0.value))" }
            .joined(separator: "&")
    }

    static func percentEncode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    /// Parámetros de un lote de scrobbles: artist[0], track[0], timestamp[0]…
    static func scrobbleParameters(_ items: [ScrobbleItem]) -> [String: String] {
        var parameters: [String: String] = [:]
        for (index, item) in items.prefix(maxBatch).enumerated() {
            for (key, value) in fields(of: item, includeTimestamp: true) {
                parameters["\(key)[\(index)]"] = value
            }
        }
        return parameters
    }

    static func nowPlayingParameters(_ item: ScrobbleItem) -> [String: String] {
        fields(of: item, includeTimestamp: false)
    }

    private static func fields(of item: ScrobbleItem, includeTimestamp: Bool) -> [String: String] {
        var fields = ["artist": item.artist, "track": item.title]
        if includeTimestamp { fields["timestamp"] = String(Int(item.startedAt.timeIntervalSince1970)) }
        if let album = item.album { fields["album"] = album }
        if let albumArtist = item.albumArtist { fields["albumArtist"] = albumArtist }
        if let trackNumber = item.trackNumber { fields["trackNumber"] = String(trackNumber) }
        if item.duration > 0 { fields["duration"] = String(Int(item.duration.rounded())) }
        return fields
    }

    /// Lee la respuesta JSON: el objeto, o el error que informa Last.fm.
    static func parse(_ data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LastFMError(code: nil, message: "Respuesta inesperada de Last.fm.")
        }
        if let code = object["error"] as? Int {
            throw LastFMError(code: code, message: (object["message"] as? String) ?? "Error \(code) de Last.fm.")
        }
        return object
    }

    /// Cuántos scrobbles aceptó Last.fm en un lote.
    static func acceptedCount(_ object: [String: Any]) -> Int {
        guard let scrobbles = object["scrobbles"] as? [String: Any],
              let attributes = scrobbles["@attr"] as? [String: Any] else { return 0 }
        if let accepted = attributes["accepted"] as? Int { return accepted }
        if let accepted = attributes["accepted"] as? String { return Int(accepted) ?? 0 }
        return 0
    }
}

/// Cliente HTTP de Last.fm.
struct LastFMClient: Sendable {
    let apiKey: String
    let secret: String

    var isConfigured: Bool { !apiKey.isEmpty && !secret.isEmpty }

    private func call(_ method: String, _ parameters: [String: String] = [:], sessionKey: String? = nil,
                      post: Bool = true) async throws -> [String: Any] {
        let all = LastFMAPI.signedParameters(method: method, parameters: parameters, apiKey: apiKey,
                                             secret: secret, sessionKey: sessionKey)
        var request: URLRequest
        if post {
            request = URLRequest(url: LastFMAPI.endpoint)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = LastFMAPI.formBody(all)
        } else {
            request = URLRequest(url: URL(string: LastFMAPI.endpoint.absoluteString + "?" + LastFMAPI.query(all))!)
        }
        request.timeoutInterval = 20
        request.setValue("Octava/0.1 (macOS)", forHTTPHeaderField: "User-Agent")

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw LastFMError(code: nil, message: "Sin conexión con Last.fm (\(error.localizedDescription)).")
        }
        return try LastFMAPI.parse(data)
    }

    // MARK: Autenticación de escritorio

    /// Paso 1: token que el usuario autoriza en el navegador.
    func getToken() async throws -> String {
        let object = try await call("auth.getToken", post: false)
        guard let token = object["token"] as? String else { throw LastFMError(code: nil, message: "Last.fm no entregó un token.") }
        return token
    }

    func authorizationURL(token: String) -> URL {
        URL(string: "\(LastFMAPI.authPage)?api_key=\(LastFMAPI.percentEncode(apiKey))&token=\(LastFMAPI.percentEncode(token))")!
    }

    /// Paso 2: con el token ya autorizado, la sesión (usuario y clave de sesión, que no expira).
    func getSession(token: String) async throws -> (username: String, key: String) {
        let object = try await call("auth.getSession", ["token": token], post: false)
        guard let session = object["session"] as? [String: Any],
              let name = session["name"] as? String, let key = session["key"] as? String else {
            throw LastFMError(code: nil, message: "Last.fm no entregó la sesión.")
        }
        return (name, key)
    }

    // MARK: Scrobbling

    func updateNowPlaying(_ item: ScrobbleItem, sessionKey: String) async throws {
        _ = try await call("track.updateNowPlaying", LastFMAPI.nowPlayingParameters(item), sessionKey: sessionKey)
    }

    /// Envía hasta 50 scrobbles. Devuelve cuántos aceptó Last.fm (el resto los ignoró, por ejemplo por ser duplicados).
    @discardableResult
    func scrobble(_ items: [ScrobbleItem], sessionKey: String) async throws -> Int {
        let object = try await call("track.scrobble", LastFMAPI.scrobbleParameters(items), sessionKey: sessionKey)
        return LastFMAPI.acceptedCount(object)
    }

    func setLoved(_ loved: Bool, artist: String, title: String, sessionKey: String) async throws {
        _ = try await call(loved ? "track.love" : "track.unlove", ["artist": artist, "track": title], sessionKey: sessionKey)
    }
}
