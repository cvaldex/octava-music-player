# Diseño de Octava

Tema elegido: **claro**. Lienzo de diseño (todas las pantallas, tema claro y oscuro, ícono):
https://claude.ai/artifact/7bZQoBdAyjZYiP7EgNamUM

El código de referencia de cada pantalla está en `docs/mockups/` (HTML con estilos en línea; se lee como especificación
de medidas y colores, no se abre directamente en el navegador porque depende del runtime del lienzo).

| Archivo | Pantalla |
| --- | --- |
| `docs/mockups/MainClaro.dc.html` | Biblioteca (grilla de álbumes + barra de reproducción) |
| `docs/mockups/AlbumClaro.dc.html` | Detalle del disco + panel "A continuación" |
| `docs/mockups/TagsClaro.dc.html` | Editor de tags por lote (hoja que baja desde la barra de título) |
| `docs/mockups/Icono.dc.html` | Ícono, tamaños y glifo de barra de menú |
| `docs/mockups/oscuro/*.dc.html` | Las mismas pantallas en tema oscuro (para más adelante) |

## Principios

- **Las carátulas son el color.** La interfaz es neutra (blanco y grises fríos) para que las portadas destaquen.
- **Un solo acento, terracota**, reservado para lo que está vivo: la canción que suena, los favoritos, la acción principal y Last.fm.
- **Nativo primero.** Barra lateral, hojas, controles y símbolos estándar de macOS (SF Symbols). La personalidad viene de la grilla, la tipografía y la barra de reproducción.
- **Números en monoespaciada**: duraciones, años, contadores y estados. Da un aire de etiqueta de disco y alinea columnas.

## Tokens (implementados en `Octava/Theme/Theme.swift`)

| Token | Valor | Uso |
| --- | --- | --- |
| `accent` | `#C2491A` | Botón principal (texto blanco, contraste 4,9:1), marca de scrobble, corazón activo |
| `accentText` | `#A63E14` | Texto de acento sobre blanco o tinte (canción sonando, píldora de scrobble) |
| `accentTint` | `#FBF0EA` | Fondo de la fila que está sonando |
| `ink` | `#16171A` | Texto principal, botón play/pausa, relleno de la barra de progreso |
| `secondaryText` | `#5F626A` | Texto secundario |
| `tertiaryText` | `#6B6E76` | Etiquetas de sección, números de pista |
| `navText` | `#3B3D44` | Ítems de la barra lateral, artista en el detalle |
| `surface` | `#FFFFFF` | Contenido |
| `sidebar` | `#F3F3F5` | Barra lateral y barra de título |
| `playerBar` | `#F7F7F9` | Barra de reproducción |
| `queuePanel` | `#FAFAFB` | Panel "A continuación" |
| `separator` | `#E3E4E8` | Divisores |
| `control` | `#E1E2E7` | Fondo de controles seleccionados, pista de la barra de progreso |
| `controlBorder` | `#CFD1D6` | Borde de botones secundarios y campos |
| `mutedIcon` | `#A3A6AD` | Corazón inactivo, íconos apagados |
| `ok` | `#1F9D62` | Last.fm conectado |

Radios: 6 px (carátulas en grilla), 8 px (botones, carátula grande, tarjetas), 10 px (tarjeta de estado), 14 px (hoja de tags).
Espaciado base: múltiplos de 4; márgenes de contenido 32 px; separación de grilla 22 px horizontal y 28 px vertical.

## Tipografía

- Interfaz: fuente del sistema (SF Pro).
- Números: monoespaciada del sistema (SF Mono). En el lienzo se usó IBM Plex Mono como sustituto web; se puede incluir en la app más adelante si se prefiere.

| Elemento | Tamaño / peso |
| --- | --- |
| Título de pantalla ("Álbumes") | 28 / bold |
| Título del disco (detalle) | 40 / bold, tracking −2 % |
| Artista en el detalle | 17 / regular |
| Título de canción, nombre de disco | 13 / semibold (en grilla), 13 / regular (lista) |
| Secundario | 12 / regular |
| Etiquetas de sección (MAYÚSCULAS) | 11 / semibold, tracking +6–8 % |
| Números | SF Mono 11–12 |

## Pantallas

### Biblioteca (`AlbumGridView`)
- Encabezado: "Álbumes" + subtítulo; a la derecha, control segmentado Artista / Año / Agregados y botón terracota "Mezcla aleatoria".
- Grilla adaptable (mínimo 160 px por carátula). Cada disco: carátula 1:1 con sombra leve, título, artista, año en mono.
- Disco sonando: contorno terracota de 2 px separado 3 px y píldora blanca "Sonando" con barras animadas.

### Detalle del disco (`AlbumDetailView`)
- Carátula 220 px con sombra; "ÁLBUM · año"; título 40; artista; "N canciones · M min · MP3" en mono.
- Botones: "Reproducir disco" (terracota), "Aleatorio" y "Editar tags" (secundarios con borde).
- Lista: # · Título · Escuchas · ♥ · Duración. La fila que suena lleva fondo `accentTint`, barras animadas y título en `accentText`.
- Panel derecho (280 px) "A continuación": próximas canciones, "y N más", e interruptor "Al terminar el disco, seguir con una mezcla aleatoria" (fase 2).

### Barra de reproducción (`PlayerBarView`)
- Izquierda: carátula 48 px, título, "Artista — Álbum", corazón.
- Centro: aleatorio, anterior, play/pausa (círculo `ink` de 44 px), siguiente, repetir; barra de progreso con tiempos en mono y una **marca terracota en el punto de scrobble**.
- Derecha: píldora "scrobble en m:ss" con anillo de avance, botón de cola, volumen.

### Barra lateral (`SidebarView`)
- Biblioteca: Álbumes, Artistas, Canciones, Géneros, Favoritos. Listas: inteligentes con ícono de shuffle terracota, listas propias, "+ Nueva lista".
- Abajo, tarjeta de estado: Last.fm (punto verde si está conectado), cola offline, carpeta vigilada.

### Editor de tags (fase 4)
- Hoja nativa que baja desde la barra de título, 720 px de ancho.
- Carátula 148 px con "Cambiar carátula" (se incrusta en cada archivo; acepta arrastrar).
- Campos: Álbum, Artista del álbum, Artista, Año, Género, Disco; "Título y número de pista" deshabilitado en lote.
- Campo modificado: borde terracota de 1,5 px y etiqueta "modificado (antes X)". Campo con valores distintos: borde punteado y "Varios valores · se conservan".
- Pie: "Se escribirá … en N archivos MP3 (ID3v2.4). Puedes deshacerlo desde Edición › Deshacer edición de tags." + Cancelar / Guardar cambios.

## Ícono

Dos anillos forman un **8**: dos notas a una octava de distancia. La aguda vibra al doble, por eso su anillo mide la mitad
y va en un tono más claro (`#FFC09A`); el grave (`#FF8A4C`) lleva un punto central que evoca un vinilo o un parlante.
Fondo grafito `#15171C`.

- Fuente maestra: `docs/brand/octava-icon.svg` (a sangre) y `docs/brand/octava-menubar.svg` (glifo monocromo de barra de menú).
- Los PNG del `AppIcon.appiconset` se generan con `python3 docs/brand/make_icon.py Octava/Resources/Assets.xcassets/AppIcon.appiconset`
  (requiere Pillow). Usa la retícula de macOS: cuerpo de 824 px dentro de 1024, sombra suave; en 16 y 32 px engrosa los trazos.

## Tema oscuro (para más adelante)

Está diseñado en el lienzo (página "Tema oscuro") y en `docs/mockups/oscuro/`. Valores principales: fondo `#121316`,
barra lateral `#17181C`, texto `#ECECEE`, secundario `#A1A3AB`, acento `#FF8A4C` con texto oscuro en el botón principal.
Para implementarlo, convertir los tokens de `Theme` en colores dinámicos (claro/oscuro) y quitar `.preferredColorScheme(.light)`.
