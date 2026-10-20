# Octava Music Player

Reproductor de música nativo para macOS que administra una colección local de MP3: discos completos, cola de
reproducción, mezclas aleatorias, listas, edición de tags y scrobbling a Last.fm.

<img src="docs/brand/octava-icon-1024.png" width="128" alt="Ícono de Octava">

**Versión 1.0.0** · macOS 14 Sonoma o posterior · SwiftUI + GRDB (SQLite)

## Funciones

- **Biblioteca**: escanea una carpeta de MP3 (tags ID3 y carátulas) y la mantiene al día sola cuando agregas, mueves o
  borras archivos. Vistas de discos, artistas, canciones y favoritos, con búsqueda.
- **Reproducción sin cortes** (gapless), normalización de volumen, repetir, Centro de Control y teclas multimedia.
- **Cola "A continuación"**: arrastra canciones o discos a cualquier posición, reordénala con el asa, quita o
  reproduce desde el menú contextual. Opción "Detener al terminar esta canción".
- **Mezclas**: aleatoria de toda la colección o con filtros (décadas, géneros, artistas); se rellenan solas y evitan
  repetir artista o disco seguidos.
- **Listas** propias y dinámicas ("Más escuchadas", "Hace tiempo sin oír"), con conteo de reproducciones.
- **Editor de tags** para una o varias canciones (incluida la carátula), conservando el resto de la etiqueta, con
  deshacer.
- **Last.fm**: scrobbling (con cola sin conexión), "Reproduciendo ahora" y me gusta.
- **Mini reproductor** en la barra de menús.

## Atajos de teclado

| Acción | Atajo |
| --- | --- |
| Reproducir / pausar | Espacio o ⌘P |
| Siguiente / anterior | ⌘→ / ⌘← |
| Adelantar / retroceder 10 s | ⌥⌘→ / ⌥⌘← |
| Subir / bajar volumen | ⌥⌘↑ / ⌥⌘↓ |
| Silenciar | ⌥⌘M |
| Detener / detener al terminar la canción | ⌘. / ⌥⌘. |
| Ir a la canción actual | ⌘L |
| Mezcla aleatoria de toda la colección | ⇧⌘S |
| Nueva mezcla con filtros | ⇧⌘M |
| Nueva lista | ⇧⌘N |
| Deshacer edición de tags | ⌥⌘Z |
| Elegir carpeta / volver a escanear | ⌘O / ⌘R |

## Compilar e instalar

Requisitos: **Xcode** (abierto una vez para aceptar la licencia) y **Homebrew** (https://brew.sh).

```bash
./bootstrap.sh              # instala XcodeGen, genera Octava.xcodeproj e inicia git
open Octava.xcodeproj       # ⌘R para ejecutar la versión de desarrollo
./tools/install.command     # compila la versión Release y la instala en /Applications
```

`Octava.xcodeproj` no se versiona: se genera desde `project.yml` con XcodeGen.

La app se firma solo para uso local ("Sign to Run Locally"), sin cuenta de desarrollador. Si se copia a otro Mac,
macOS pedirá abrirla con clic derecho → Abrir la primera vez.

### Last.fm

Las credenciales no están en el repositorio. Al generar el proyecto se crea `Octava/Config/Secrets.swift` (ignorado
por git) desde `Secrets.example.swift`: pon ahí la API key y el shared secret de tu aplicación en
https://www.last.fm/api/account/create. Luego conecta tu cuenta en Ajustes; la sesión se guarda en el Llavero.

## Datos

La biblioteca, las listas y las estadísticas viven en
`~/Library/Containers/local.octava.Octava/Data/Library/Application Support/Octava/library.sqlite`. Octava nunca
modifica tus archivos de música, salvo los tags que confirmas en el editor.

## Estructura

| Carpeta | Contenido |
| --- | --- |
| `Octava/` | Código de la app (SwiftUI) y recursos |
| `OctavaTests/` | Tests |
| `tools/` | Instalador (`install.command`) y ejecutor de compilación |
| `docs/SPEC.md` | Especificación y fases |
| `docs/DESIGN.md` | Diseño: colores, tipografía, pantallas, ícono |
| `docs/mockups/`, `docs/brand/` | Referencias de diseño e ícono |
| `project.yml` | Definición del proyecto de Xcode (XcodeGen) |
| `CLAUDE.md` | Notas técnicas para seguir desarrollando con Claude Code |

## Créditos

- Base de datos: [GRDB.swift](https://github.com/groue/GRDB.swift).
- Logo de Last.fm en Ajustes: ícono de [Flaticon](https://www.flaticon.com) (n.º 145806), creado por Freepik.
  Last.fm es una marca de sus respectivos dueños.

## Licencia

Código bajo [GNU GPL v3](LICENSE). El logo de Last.fm no forma parte del código licenciado: se usa bajo la licencia
gratuita de Flaticon (con atribución) y la marca pertenece a Last.fm.
