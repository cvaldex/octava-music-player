# Octava — guía para Claude Code

Reproductor de música nativo para macOS (SwiftUI) que administra una colección local de MP3: discos completos,
listas aleatorias, edición de tags y scrobbling a Last.fm. Proyecto personal de un solo usuario, que habla español.

- Especificación completa: `docs/SPEC.md` (alcance, arquitectura, modelo de datos, reglas de tags, Last.fm, fases).
- Diseño: `docs/DESIGN.md` (tokens, tipografía, pantallas, ícono) y referencias en `docs/mockups/`.
- Lee ambos antes de empezar una fase nueva.

## Comandos

```bash
./bootstrap.sh                       # primera vez: instala XcodeGen (Homebrew), genera el proyecto, inicia git
xcodegen generate                    # regenerar Octava.xcodeproj tras agregar/quitar archivos o cambiar project.yml
xcodebuild -project Octava.xcodeproj -scheme Octava -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Octava.xcodeproj -scheme Octava -destination 'platform=macOS' test
open Octava.xcodeproj                # para ejecutar y probar la interfaz en Xcode (⌘R)
```

- `project.yml` es la fuente de verdad del proyecto. **No edites `Octava.xcodeproj` a mano** ni lo versiones (está en `.gitignore`).
- Al crear o borrar archivos Swift, ejecuta `xcodegen generate` antes de compilar.
- Después de cada cambio: compila; si tocaste lógica, corre los tests. No des una tarea por terminada si no compila.
- La app no se puede probar de forma automática con audio ni con la interfaz: al terminar una fase, deja una lista corta
  de qué debe probar el usuario en Xcode.

## Arquitectura

```
Octava/
  App/        OctavaApp (escena, menús) · AppModel (estado global: base de datos, biblioteca, reproductor, carpeta)
  Theme/      Theme (tokens de color y tipografía del diseño claro) · formatDuration
  Models/     Track · Album (registros GRDB, Codable)
  Database/   AppDatabase (GRDB, migraciones)
  Library/    LibraryScanner (actor) · TagReader · CoverCache · FolderAccess · LibraryStore (lecturas para la UI)
  Playback/   PlayQueue (lógica pura, testeada) · PlaybackEngine (AVAudioEngine) · scrobbleThreshold
  Views/      RootView · SidebarView · AlbumGridView · AlbumDetailView · PlayerBarView · AlbumCoverView · WelcomeView · Components
  Resources/  Assets.xcassets (AppIcon, AccentColor)
OctavaTests/  Tests de cola, regla de scrobble, parseo de tags y base de datos
```

Flujo: la interfaz llama a `AppModel` / `LibraryStore` / `PlaybackEngine`; nunca toca archivos ni SQL directamente.

## Convenciones

- **Idioma**: todo texto visible y los comentarios, en español. Nombres de tipos, funciones y variables, en inglés.
- **Swift 5 language mode** (`SWIFT_VERSION: 5.0`), macOS 14+. Estado observable con `@Observable`; tipos de UI con `@MainActor`.
  Trabajo pesado (escaneo, E/S) fuera del hilo principal (actores o `Task.detached`).
- **Colores y tipografía solo desde `Theme`**. No escribir hex sueltos en las vistas. Íconos: SF Symbols.
- **Tema claro forzado** (`.preferredColorScheme(.light)` en `OctavaApp`). El oscuro es opcional en la fase 6.
- **Base de datos**: cada cambio de esquema es una migración nueva (`v2`, `v3`…). Nunca edites `v1` ni uses
  `eraseDatabaseOnSchemaChange`: la base guarda estadísticas y favoritos que no se pueden reconstruir.
- **Rutas relativas** a la carpeta de música en la base de datos (`Track.relativePath`).
- **El MP3 es la fuente de verdad de los tags**: en la fase 4, primero se escribe el archivo (escritura atómica en un
  temporal) y solo después la base de datos. Guardar los tags previos en `tagEditHistory` para deshacer.
- **Nunca modifiques, muevas ni borres archivos de la colección de música del usuario**, salvo la escritura de tags que
  el usuario confirma en el editor (fase 4). Para probar la escritura de tags, usa copias.
- **Secretos**: la API key y el secret de Last.fm no se versionan. Fase 5: crear `Octava/Config/Secrets.swift`
  (en `.gitignore`) a partir de un `Secrets.example.swift` versionado; la session key va al Keychain.
- Sin dependencias nuevas sin motivo. Aprobadas: GRDB (en uso) e ID3TagEditor (fase 4, ya comentada en `project.yml`).
- Commits pequeños, uno por avance funcional, mensaje en español en imperativo ("Agrega búsqueda por canción").

## Estado de las fases

- [x] **0. Esqueleto** — proyecto XcodeGen, sandbox con acceso a carpeta (bookmark), esquema GRDB completo, escáner con
      caché de carátulas, grilla y detalle de disco, cola, reproducción secuencial, contador de reproducciones, favoritos,
      barra de reproducción con punto de scrobble, ícono. **El código se escribió en un entorno sin Xcode y nunca se
      compiló: la primera tarea es ejecutar `./bootstrap.sh`, compilar, correr los tests y corregir los errores.**
      Luego el usuario verifica en Xcode que escanee su colección real y reproduzca un disco.
- [ ] **1. Biblioteca** — vigilancia con FSEvents (re-escaneo incremental, debounce), búsqueda por canción, bitrate,
      vistas Artistas / Canciones / Géneros / Favoritos, escaneo inicial rápido con muchas pistas.
- [ ] **2. Reproducción** — gapless real (programar la siguiente pista antes del final), cola editable (arrastrar, quitar,
      "reproducir a continuación"), reanudar al abrir (`appState`), ReplayGain, teclas multimedia y Centro de Control
      (`MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`), repetir, interruptor "seguir con mezcla al terminar el disco".
- [ ] **3. Listas** — generador con filtros (artista, género, década), shuffle inteligente, listas guardadas y dinámicas.
- [ ] **4. Edición de tags** — ID3TagEditor, editor individual y por lote según `docs/DESIGN.md`, deshacer, evitar eco de FSEvents.
- [ ] **5. Last.fm** — autenticación de escritorio, now playing, scrobble (regla en `scrobbleThreshold`), cola offline
      en `scrobbleQueue` con reenvío por lotes, love/unlove, ajustes.
- [ ] **6. Pulido** — mini-reproductor o barra de menú (glifo en `docs/brand/octava-menubar.svg`), atajos (barra
      espaciadora sin chocar con la búsqueda), manejo de errores (carpeta desconectada, archivo movido, cambio de salida de audio), modo oscuro opcional.
- [ ] **7. Uso diario** — build Release y copia a /Applications.

Actualiza esta lista al cerrar cada fase.

## Detalles conocidos

- El sandbox guarda la base en `~/Library/Containers/local.octava.Octava/Data/Library/Application Support/Octava/`
  (`library.sqlite` y `Covers/`).
- Firma "Sign to Run Locally" (`CODE_SIGN_IDENTITY: "-"`): no requiere cuenta de desarrollador. Si macOS pide permisos
  de nuevo tras recompilar, es por la firma ad hoc; elegir la carpeta otra vez lo resuelve.
- `PlaybackEngine` usa un contador `generation` para ignorar los callbacks de fin de pista provocados por `stop()`/`seek()`.
  Mantener ese patrón al implementar gapless.
- `TagReader` toma "Album Artist" del frame TPE2 (`id3MetadataBand`).
