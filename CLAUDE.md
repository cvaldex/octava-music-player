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
  Library/    LibraryScanner (actor, lectura en paralelo) · TagReader · ID3UserTextReader (frames TXXX) · CoverCache
              FolderAccess · FolderWatcher (FSEvents) · LibraryStore (biblioteca en memoria) · LibraryIndex (agrupar y buscar, testeado)
  Playback/   PlayQueue (cola con entradas únicas y repetición, testeada) · PlaybackEngine (AVAudioEngine, gapless)
              ReplayGain (cálculo, testeado) · NowPlayingCenter (Centro de Control, teclas multimedia) · scrobbleThreshold
  Views/      RootView (navegación y búsqueda) · Navigation (rutas, Navigator, PageHeader) · SidebarView · AlbumGridView
              AlbumGrid · AlbumDetailView · LibraryPages (Artistas, Canciones, Géneros, Favoritos, Búsqueda) · TrackTable
              QueuePanel · PlayerBarView · AlbumCoverView · WelcomeView · Components
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
      barra de reproducción con punto de scrobble, ícono. Compila sin errores con Xcode 27.1 (macOS 26) y pasan los
      15 tests. *Pendiente: que el usuario verifique en Xcode que escanee su colección real y reproduzca un disco.*
- [x] **1. Biblioteca** — vigilancia de la carpeta con FSEvents (`FolderWatcher`, escaneo incremental 2 s después del
      último cambio; el aviso de escaneo solo aparece si dura más de 1,5 s), búsqueda global en la barra de herramientas
      (discos y canciones, sin distinguir mayúsculas ni acentos, todas las palabras), bitrate por canción y por disco,
      vistas Artistas (→ discos del artista), Canciones (tabla ordenable), Géneros (→ canciones del género) y Favoritos,
      lectura de tags en paralelo (8 a la vez), géneros numéricos de ID3v1 traducidos a su nombre. Migraciones `v3`
      (releer tags por el bitrate) y `v4` (géneros numéricos). *Pendiente de verificar por el usuario en Xcode.*
- [x] **2. Reproducción** — gapless (la siguiente pista se programa 10 s antes del final si tiene el mismo formato),
      cola editable (arrastrar, quitar, "reproducir a continuación", "agregar al final", doble clic para saltar) en un
      panel lateral global (inspector), reanudar al abrir (instantánea en `appState`), ReplayGain leído de frames TXXX
      (`ID3UserTextReader`, modos desactivada/automática/por canción/por disco con `AVAudioUnitEQ`), teclas multimedia y
      Centro de Control (`NowPlayingCenter`), repetir (sin repetir/todo/una), "seguir con una mezcla al terminar la cola".
      Migración `v2` fuerza a releer los tags una vez. *Pendiente de verificar por el usuario en Xcode.*
      Fuera de esta fase: calcular ReplayGain cuando el MP3 no lo trae (análisis de audio, costoso) → opcional en fase 6.
- [x] **3. Listas** — mezclas con filtros (`MixRule`: origen colección/favoritos/olvidadas + artistas, géneros y
      décadas; ventana "Filtros…" en Álbumes y ⇧⌘M) que se rellenan solas para tener siempre 100 canciones por delante
      (`AppModel.refillMixIfNeeded`, la cola conserva solo 50 ya escuchadas). Shuffle inteligente (`MixBuilder`): primero
      lo no escuchado en 7 días, al final lo reciente; sin el mismo artista en las últimas 2 ni el mismo disco seguido.
      Listas guardadas (`PlaylistStore`, tablas `playlist`/`playlistItem`): "Nueva lista", "Agregar a lista" en todos los
      menús, "Guardar la cola como lista", reordenar/quitar, renombrar/eliminar. Dinámicas: Más escuchadas (top 100) y
      Hace tiempo sin oír (6 meses o nunca). *Pendiente de verificar por el usuario en Xcode.*
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
- `PlaybackEngine`: cada tramo programado en el `AVAudioPlayerNode` tiene un id; el callback de fin solo se atiende si
  coincide con el tramo actual y con `generation` (que sube en cada stop/seek/cambio de pista). El tiempo actual se calcula
  con `baseSampleTime` (crece en cada transición gapless) y `startFrame` (desplazamiento tras un salto). Si se edita la cola
  y la pista ya programada deja de ser la siguiente, se reprograma la actual desde su posición (`queueDidChange`).
- AVAudioEngine: **nunca** reconectar nodos con el motor encendido (queda detenido sin aviso) ni llamar a
  `player.play()` directamente (con el motor apagado lanza una excepción que cierra la app). Usar `connect(format:)` y
  `startPlayer()`. Si el motor se detiene solo (cambio de salida de audio), `recoverStoppedEngine()` reprograma la pista.
- Para probar en la app sin Xcode: `build-logs/wait.sh run` la lanza con su salida en `build-logs/app.log`; `sample`
  toma una muestra del proceso (útil si se cuelga). Los crash bajo Xcode no dejan reporte en DiagnosticReports.
- Cerrar la ventana (X o ⌘W) cierra la app previa confirmación (`AppDelegate.applicationShouldTerminate`);
  `WindowCloseConfirmation` intercepta el cierre con un delegado intermedio que reenvía el resto al de SwiftUI.
  "No volver a preguntar" se guarda en `UserDefaults` (`skipQuitConfirmation`).
- El panel de la cola es una columna de la ventana, **fuera** del `NavigationSplitView` (dentro, la navegación lo
  reemplazaba). No usar `.inspector` para él.
- Carátulas: `AlbumCoverView` es siempre cuadrada (cuadrado vacío + imagen `scaledToFill` superpuesta y recortada).
- Detalle de disco: encabezado adaptable con `ViewThatFits`; lista de canciones con selección (clic), doble clic o
  Enter para reproducir, ↑/↓ para moverse.
- Ojo: al copiar al Mac con la herramienta de archivos, verificar con md5; una segunda copia del mismo archivo a veces no
  se aplica.
- `Table` (TrackTable): las celdas viven en vistas de AppKit propias. **Nada dentro de una celda ni de un menú
  contextual puede usar `@Environment`** (se cerraba la app al desplazar): pasar los datos explícitamente. Sin
  animaciones dentro de las celdas, y `.id(sortIdentity)` para reconstruir la tabla al cambiar el orden (animar el
  reordenamiento de miles de filas colgaba la app).
- Navegación: `Navigator` (en el entorno) guarda la ruta (`LibraryRoute`: disco, artista, género). Al cambiar de sección
  o empezar a buscar se vuelve a la raíz.
- No usar `withAnimation(.repeatForever)` en vistas: la animación infinita se contagia a los cambios de diseño vecinos
  (la cola crecía y se achicaba). Las animaciones continuas van con `TimelineView` (ver `PlayingBars`).
- Ajustes de reproducción (repetir, normalización, volumen, seguir con mezcla) en `UserDefaults`; la cola en `appState`.
- Al abrir con carpeta configurada se lanza un escaneo incremental automático.
- `TagReader` toma "Album Artist" del frame TPE2 (`id3MetadataBand`).
- `tools/build-runner.command`: ejecutor que se abre con doble clic y compila cuando aparece `build-logs/request`
  (bootstrap | generate | build | test | all | env | gitstatus | gitcommit). `build-logs/wait.sh <comando>` envía el pedido
  y espera el resultado. Sirve para trabajar a distancia sin escribir en la Terminal;
  el resultado queda en `build-logs/latest.log` (ignorado por git). Compila con `-derivedDataPath build/DerivedData`.
- Mezclas: mientras `activeMix` exista (se guarda en UserDefaults), cada cambio de la cola la rellena. Reproducir un
  disco, una lista o una tabla la detiene; "Limpiar" la cola también (si no, se rellenaría al instante).
- Diálogos de nombre/confirmación desde menús: `TextPrompt` (NSAlert modal), no hojas de SwiftUI.
