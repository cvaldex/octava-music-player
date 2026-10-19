// Plantilla de credenciales. NO pongas claves reales aquí: este archivo sí se versiona.
//
// Al generar el proyecto (xcodegen / bootstrap.sh) se copia como `Secrets.swift` si no existe.
// `Secrets.swift` está en .gitignore: completa ahí la API key y el shared secret de tu aplicación de Last.fm
// (https://www.last.fm/api/account/create). Sin ellos la app funciona igual, pero no hace scrobbling.
//
// Este archivo no se compila (está excluido en project.yml).

enum Secrets {
    static let lastFMAPIKey = ""
    static let lastFMSharedSecret = ""
}
