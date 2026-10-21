# Cambios

Historial de versiones de Octava Music Player. Se sigue el esquema MAYOR.MENOR.PARCHE:
funciones nuevas suben el segundo número; correcciones, el tercero.

## 1.1.0 — 2026-10-21

#### Nuevo
- **Importar listas de reproducción** `.xspf`, `.m3u` y `.m3u8` (Archivo → Importar lista…). Busca cada canción en la biblioteca por ruta, por el final de la ruta (listas hechas en otro computador) o por título y artista, y avisa cuáles no encontró.
- **Lista fija "Canciones cortas"**: canciones de más de 30 segundos y menos de 3:31, sin Drumless Tracks, ordenadas por fecha de agregado (lo más nuevo al final). Se actualiza sola.
- **Menú del Dock** (clic derecho en el ícono): la canción que suena, Reproducir/Pausar, Siguiente, Anterior, Detener, Detener al terminar esta canción y Agregar/Quitar de favoritos.
- **Pegar la carátula** en el editor de tags: imagen copiada desde el navegador o Vista Previa, archivo de imagen copiado, o la dirección web de una imagen. También se puede arrastrar desde el navegador.
- **Clic en la carátula** de la barra inferior para abrir el disco que suena (igual que ⌘L).

#### Mejoras
- **Etiquetas ID3v2.2**: se leen completas (pista, disco, año, artista del álbum y género) y se pueden editar; al guardar quedan como ID3v2.3. 38 discos recuperan su numeración.
- **Fecha de agregado por canción**: las canciones existentes toman la fecha de creación del archivo; las nuevas, la del escaneo. Corrige el orden "Agregados" de Álbumes.

#### Corregido
- Con un disco abierto, cambiar la búsqueda o pulsar Enter no mostraba los resultados.
- "Ir al disco" (⌘L o clic en la carátula) necesitaba dos clics desde otra sección.
- Algunos MP3 válidos que macOS rechazaba al leer los tags (por ejemplo "Corynorhinus" de *Batman Begins*) quedaban fuera de la biblioteca.

## 1.0.0 — 2026-10-19

Primera versión.

- Biblioteca de MP3 local que se mantiene al día sola: discos, artistas, canciones, favoritos y búsqueda.
- Reproducción sin cortes (gapless), normalización de volumen, repetir, Centro de Control y teclas multimedia.
- Cola "A continuación" editable: arrastrar canciones o discos, reordenar, menú contextual, "Detener al terminar esta canción".
- Mezclas aleatorias de toda la colección o con filtros (décadas, géneros, artistas) que se rellenan solas.
- Listas propias y fijas ("Más escuchadas", "Hace tiempo sin oír"), con conteo de reproducciones.
- Editor de tags para una o varias canciones, con carátula y deshacer.
- Scrobbling a Last.fm con cola sin conexión, "Reproduciendo ahora" y me gusta.
- Mini reproductor en la barra de menús.
