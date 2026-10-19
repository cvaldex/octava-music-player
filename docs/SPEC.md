# Especificación: Octava

Reproductor de música de escritorio para macOS. Versión de la especificación: 17 de octubre de 2026.
Fuente original (documento editable): https://claude.ai/code/artifact/681ede2f-63ea-4d0c-8b67-91046f789c12

## Objetivo y alcance

App nativa para macOS que administra una colección de MP3 alojada en una carpeta local, reproduce discos completos o listas aleatorias, permite editar los tags y hace scrobbling a Last.fm.

- **Uso**: personal, en un solo Mac. No se distribuirá a terceros.
- **Colección**: solo archivos MP3, organizados en una carpeta local con subcarpetas.
- **Plataforma**: macOS 14 o superior (SwiftUI moderno y framework Observation).
- **Nombre**: Octava. **Tema visual**: claro (el oscuro queda diseñado para más adelante).

## Stack tecnológico

| Necesidad | Tecnología | Motivo |
| --- | --- | --- |
| Lenguaje e interfaz | Swift + SwiftUI | Nativo, bajo consumo, integración con el sistema |
| Proyecto de Xcode | XcodeGen (`project.yml`) | El proyecto se genera desde un archivo de texto legible y versionable |
| Reproducción | AVFoundation (`AVAudioEngine` + `AVAudioPlayerNode`) | Suficiente para MP3; permite encolar la pista siguiente para gapless |
| Lectura de tags | AVFoundation (`AVURLAsset` + metadata) | Lee ID3v2 y carátulas incrustadas |
| Escritura de tags | `ID3TagWriter` propio (Swift) | Reemplaza solo los frames editados y conserva el resto byte a byte (ReplayGain, comentarios); AVFoundation no escribe tags MP3. ID3TagEditor se descartó en la fase 4 |
| Base de datos | SQLite con [GRDB](https://github.com/groue/GRDB.swift) | Rápida, con migraciones y observación de cambios |
| Vigilancia de la carpeta | FSEvents | Detecta archivos nuevos, borrados o modificados sin re-escanear todo |
| Integración con el sistema | `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` | Teclas multimedia y Centro de Control |
| Credenciales | Keychain | Guarda la session key de Last.fm |
| Control de versiones | Git + GitHub (repositorio privado) | Historial y respaldo |

Alternativa descartada para escritura de tags: TagLib (C++ con puente Objective-C). Solo tendría sentido si a futuro se suman otros formatos.

## Arquitectura

La interfaz nunca toca los archivos ni la base de datos directamente: todo pasa por cuatro servicios.

```
                 ┌──────────────────── Interfaz SwiftUI ────────────────────┐
                 │ Biblioteca · Detalle de disco · Cola · Listas · Editor · Ajustes │
                 └───────┬──────────────┬──────────────┬──────────────┬─────┘
                         │              │              │              │
                  Reproducción     Biblioteca     Edición de tags   Scrobbler
                  AVAudioEngine    Escaneo         ID3TagEditor      Now playing
                  Cola, gapless    FSEvents        Escritura atómica Scrobbles, favoritos
                  Normalización    Búsqueda        Deshacer          Cola offline
                         │              │              │              │
                       macOS     ┌─── Datos locales ───┐        API de Last.fm
                  Now Playing,   │ Carpeta MP3 (fuente │        session key en Keychain
                  teclas         │ de verdad) + SQLite │
                                 └─────────────────────┘
```

La cola de reproducción es un solo modelo para ambos modos: un disco es la cola ordenada por número de pista, y una lista aleatoria es la cola generada por el shuffle. El scrobbler escucha los eventos del motor de reproducción y guarda su cola offline en la misma base de datos.

## Funcionalidades

### Biblioteca
- Escaneo de la carpeta elegida, con avance visible y sin congelar la interfaz.
- Grilla de álbumes con carátulas y vista de detalle del disco.
- Agrupación por "Album Artist" cuando exista; si no, por "Artist". Así los recopilatorios no se fragmentan.
- Carátula incrustada en el MP3 o, de respaldo, `cover.jpg` / `folder.jpg` de la carpeta del disco.
- Detección automática de cambios en la carpeta (FSEvents).
- Búsqueda con un campo único que filtra por artista, álbum y canción.

### Reproducción
- Reproducción de discos completos en orden de disco y pista.
- Gapless: la pista siguiente se encola antes de que termine la actual.
- Cola editable: reproducir a continuación, agregar al final, quitar y reordenar.
- Reanudar al abrir: recordar cola, pista y posición.
- Normalización de volumen: leer tags ReplayGain si existen; si no, calcularlos durante el escaneo.
- Teclas multimedia y Centro de Control.

### Listas
- Generador de listas aleatorias con filtros: toda la colección, artista, género o década.
- Shuffle inteligente: evita repetir artistas seguidos y canciones escuchadas recientemente.
- Listas guardadas: guardar una lista aleatoria o armar una a mano.
- Listas dinámicas a partir de estadísticas: lo más escuchado, lo que no se escucha hace tiempo.

### Estadísticas y favoritos
- Contador de reproducciones y fecha de última escucha por canción.
- Favoritos (corazón por canción), sincronizados con el "love" de Last.fm.

### Edición de tags
- Editor individual y por lote (un disco completo o varias canciones).
- Actualiza el archivo MP3 y la base de datos (reglas más abajo).
- Deshacer la última edición.

### Last.fm
- Now playing, scrobbles con cola offline y sincronización de favoritos.

### Interfaz
- Mini-reproductor o ícono en la barra de menú, atajos de teclado.
- Tema claro (elegido). Modo oscuro: diseñado, implementación opcional al final.

### Fuera del alcance inicial
- Ecualizador, letras y descarga automática de carátulas faltantes. Se pueden agregar después sin cambiar la arquitectura.

## Modelo de datos

Implementado en `Octava/Database/AppDatabase.swift` (migración `v1`). Las tablas de fases futuras ya existen.

| Tabla | Campos principales |
| --- | --- |
| `track` | id, relativePath, fileModifiedAt, title, artist, albumArtist, album, trackNumber, discNumber, year, genre, duration, bitrate, replayGainTrack, replayGainAlbum, playCount, lastPlayedAt, isFavorite, albumId |
| `album` | id, title, albumArtist, year, folderPath, coverCachePath, addedAt (único: albumArtist + title) |
| `playlist` | id, name, kind (manual o generated), createdAt |
| `playlistItem` | playlistId, trackId, position |
| `scrobbleQueue` | id, artist, title, album, startedAt, duration, attempts |
| `tagEditHistory` | id, trackId, previousTags (JSON), editedAt |
| `appState` | key, value (cola, pista y posición para reanudar) |

- La ruta se guarda relativa a la carpeta raíz, para que la colección pueda moverse de disco sin perder estadísticas.
- La fecha de modificación permite re-escanear solo los archivos que cambiaron.
- Las carátulas se extraen una vez a una caché en disco (~600 px), para que la grilla sea fluida.
- El permiso de la carpeta se guarda como security-scoped bookmark en UserDefaults (no en `appState`).

## Edición de tags: reglas de diseño

El archivo MP3 es la fuente de verdad: primero se escribe el archivo y, solo si eso funciona, se actualiza la base de datos.

1. **Escritura segura**: los tags se escriben en un archivo temporal que luego reemplaza al original de forma atómica. Si algo falla, el MP3 original queda intacto.
2. **Edición por lote**: al seleccionar varias canciones se editan solo los campos comunes (álbum, artista del álbum, año, género, carátula). Los campos con valores distintos se muestran como "Varios valores · se conservan" y no se tocan si no se modifican. El campo modificado se marca y muestra el valor anterior.
3. **Deshacer**: antes de escribir se guardan los tags anteriores en `tagEditHistory`.
4. **Evitar el eco**: la app registra los archivos que está modificando, para que FSEvents no dispare un re-escaneo duplicado.
5. **Permisos**: la carpeta se elige con acceso de lectura y escritura (entitlement `files.user-selected.read-write`) y se guarda como security-scoped bookmark.
6. **Canción en reproducción**: se puede editar sin cortar el audio.
7. **Versión de ID3**: se conserva la versión que trae el archivo (v2.3 o v2.4); un archivo sin etiqueta recibe v2.4.
8. **Last.fm**: editar un tag no modifica scrobbles ya enviados; la API de Last.fm no permite editarlos.

Probar el editor primero sobre una copia de algunos discos.

## Integración con Last.fm

API 2.0 de Last.fm con una API key personal gratuita ([last.fm/api](https://www.last.fm/api)).

- **Autenticación**: flujo de escritorio con token; el usuario autoriza una vez en el navegador y la session key se guarda en el Keychain.
- **Now playing**: `track.updateNowPlaying` al iniciar cada pista.
- **Scrobble**: `track.scrobble` cuando la pista dura más de 30 segundos y se escuchó la mitad o 4 minutos, lo que ocurra primero (`scrobbleThreshold(forDuration:)`). El timestamp es el del inicio de la reproducción.
- **Pausas**: el tiempo en pausa no cuenta como escuchado.
- **Cola offline**: los scrobbles se guardan en `scrobbleQueue` y se reenvían en lotes (hasta 50 por llamada) cuando hay conexión.
- **Favoritos**: `track.love` y `track.unlove` al marcar o desmarcar el corazón.
- **Ajustes**: activar o desactivar el scrobbling y ver el estado de la conexión.
- La API key y el secret NO se versionan: van en un archivo local ignorado por git (ver CLAUDE.md, fase 5).

## Fases de desarrollo

Cada fase termina con algo que se puede probar en el Mac antes de seguir.

| Fase | Contenido | Criterio para pasar a la siguiente |
| --- | --- | --- |
| 0. Esqueleto | Proyecto SwiftUI, modelo de datos, escáner de carpeta, reproducción de un disco | Compila, escanea la colección real y reproduce un disco |
| 1. Biblioteca | Grilla de álbumes, detalle de disco, búsqueda, vigilancia de carpeta | La colección completa carga fluida, con avance visible |
| 2. Reproducción | Cola editable, gapless, reanudar al abrir, teclas multimedia, normalización | Un disco en vivo suena sin cortes entre pistas |
| 3. Listas | Generador aleatorio con filtros, shuffle inteligente, listas guardadas | Se genera, reproduce y guarda una lista |
| 4. Edición de tags | Editor individual y por lote, escritura segura, deshacer | Edición verificada sobre una copia de discos |
| 5. Last.fm | Autenticación, now playing, scrobbles, cola offline, favoritos | Los scrobbles aparecen en el perfil, también tras usar la app sin conexión |
| 6. Pulido | Mini-reproductor o barra de menú, atajos, manejo de errores, modo oscuro opcional | Uso diario sin fricciones |
| 7. Uso diario | Compilar en modo Release y copiar a Aplicaciones | La app reemplaza al reproductor actual |

Para uso personal no se necesita cuenta de desarrollador pagada.
