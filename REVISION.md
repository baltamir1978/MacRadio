# Revisión — MacRadio

Estado del proyecto y trabajo pendiente. Actualizado el 19/09/2026.

## Estado

Primera versión funcional, instalada en /Applications con `./build.sh --install` (Developer ID,
sandbox, App Group con prefijo de equipo). Compila sin avisos en Swift 6 con Xcode 27.

Comprobado en este Mac:

- Reproducción de Cassette FM, La Indie y Kiss FM a través del proxy local.
- Metadatos ICY, incluida la corrección de emisoras que mandan «Título - Artista» (Cassette FM,
  La Indie): se detecta con el artista que devuelve iTunes.
- Carátula (iTunes), letra sincronizada (LRCLIB) e historial.
- Cuña de entrada de La Indie: medida (≈320 KB, 20 s), descartada en las conexiones siguientes y
  primer sonido a unos 10 s. Cassette FM, sin cuña, no da falso positivo. El reencuadre ICY está
  probado con un stream sintético (corte exacto, títulos intactos, paso íntegro si no coincide).
- Widget dibujado en los cuatro tamaños, claro y oscuro, en español e inglés (`--render-widgets`).
- Shazam sobre Kiss FM con el App ID propio `Altamirano.MacRadio`, registrado con ShazamKit en
  App Services el 2026-09-19 (antes no existía: la app se firma con Developer ID sin perfil).
- Comprobado a mano (2026-09-19): con Shazam, la letra sale a tiempo desde el cambio de canción
  en La Indie y Cassette FM; los botones del widget arrancan la app cerrada en segundo plano; el
  botón ▶︎/⏸ se ve en el escritorio sin foco; − / + y el clic en la letra funcionan en el widget.
- El título ICY llega al reproductor en su punto exacto del audio (−0,008 s medido). El desfase
  de la letra que se nota viene de la emisora, que cambia el título tarde; lo mide Shazam por
  emisora (`title_lag.<stream>`) y, mientras tanto, se corrige a mano con − / + junto a «Letra».
- Ajuste de la letra a cero: botón ↺ junto a − / +, menú «Poner la letra a cero» (⌥⌘0) y clic en
  la cifra del widget (el clic en una línea deja cifras como +1,3 s que los pasos de 0,5 no
  devuelven a cero). Cuando Shazam ha situado una canción en la emisora, el ajuste vuelve a ±0
  en cada canción nueva y al llegar cada posición de Shazam: el ajuste a mano es de esa canción.
- Títulos que se quedan (2026-09-19): Cadena 100 siguió mandando «Olivia Dean - So easy» con la
  canción acabada y la app se quedó en ella. Pasada la duración de la canción (LRCLIB) + 20 s
  con el mismo título, Shazam dice qué suena; si es otra cosa, nombra las canciones hasta que la
  emisora cambie el título, y si no reconoce nada se muestra el logo.
- Desfase de ~1 s en Cadena 100 (2026-09-19): Bruno tenía que adelantar la letra +1 s. Shazam
  siempre escucha por la segunda conexión, y esta abre con 5,2 s de audio atrasado en medio
  segundo; ShazamKit da por hecho que el audio suena según llega. Ahora la ráfaga no se le pasa.
- Letra de colaboraciones (2026-09-19): «El Canto del Loco y Amaia Montero - Puede ser» no daba
  letra (LRCLIB no tiene ese artista junto). Se prueba con el artista principal y con el título
  solo, filtrando por los artistas nombrados; comprobado con LRCLIB real (57 líneas).
- Widget sin nada sonando (2026-09-19): se quedaba con la última canción y su letra, también con
  la app cerrada. Ahora, en pausa o sin emisora, la carátula es el icono de la app, la letra queda
  en blanco y se lee la emisora que ▶︎ volvería a poner; al salir, la app pausa antes para que el
  widget lo sepa. Logos a sangre, sin el marco blanco; los de fondo transparente van enteros con
  un margen, sobre oscuro si son claros (Kiss FM). Dibujado con `--render-widgets` e instalado.

## Pendiente

### Por verificar a mano
- Que al salir de la app sonando, el widget pase al icono de la app y la letra en blanco.
- Que el ajuste vuelva a ±0 al cambiar de canción con Shazam activo, y ↺ en ventana y widget.
- Que la letra de Cadena 100 vaya a tiempo sin tocar − / +. En los registros, el retraso de
  títulos aprendido (`changes its titles …s late`, antes 3,0–3,6 s) debería subir en lo que
  retrasaba la ráfaga.
- Por qué la escucha directa del reproductor (`AudioStreamTap`) siempre llega vacía («tap
  starved»): con ella Shazam oiría exactamente lo que suena, sin segunda conexión.
- La próxima vez que una emisora deje un título caducado: que salga la canción de Shazam (o el
  logo) ~20 s después de acabar la anterior, y que al volver el título de la emisora no se
  duplique en el historial.
- Cuánto se aleja la letra del audio en el widget frente a la ventana: WidgetKit decide cuándo
  pinta cada entrada de la línea de tiempo y puede llegar tarde.
- Cuña de La Indie cuando rota el anuncio: todos empiezan con la misma sintonía, así que el
  reconocimiento por los primeros bytes no distingue anuncios de distinta duración. Se vuelve a
  medir cada hora; entre medias puede sonar la cola de un anuncio más largo o perderse medio
  segundo de música.

### Mejoras posibles
- Al abrir la app como ítem de inicio de sesión se muestra la ventana; lo propio sería arrancar
  solo en la barra de menús.
- No hay tests en el proyecto. Candidatos baratos: `LyricsService.parseLRC`,
  `IntroLearner.introLength` e `IcyReframer` (ya probados a mano con un stream sintético),
  `StationEntity`/`StationQuery` y el parseo de «Artista - Título».
