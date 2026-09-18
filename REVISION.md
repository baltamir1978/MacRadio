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
- Shazam sobre Kiss FM **con el App ID de RadioApp** (ver pendiente).
- El título ICY llega al reproductor en su punto exacto del audio (−0,008 s medido). El desfase
  de la letra que se nota viene de la emisora, que cambia el título tarde; lo mide Shazam por
  emisora (`title_lag.<stream>`) y, mientras tanto, se corrige a mano con − / + junto a «Letra».

## Pendiente

### Requiere acción en developer.apple.com
- **Activar ShazamKit para el App ID `Altamirano.MacRadio`.** Sin eso, Shazam responde 401 /
  error 202 y no hay identificación: Kiss FM se queda sin canción ni letra, y no se aprende el
  retraso de título de cada emisora. La app lo detecta y lo avisa en Ajustes. Tras activarlo
  basta con reabrir la app, sin recompilar.

### Por verificar a mano
- Con ShazamKit activado: que el retraso de título aprendido (traza `… changes its titles …s
  late`) deja la letra a tiempo desde el cambio de canción, en La Indie y Cassette FM.
- Los botones del widget en el escritorio con la app cerrada: el widget tiene que arrancarla en
  segundo plano (`AppLauncher`). Si el sandbox de la extensión no lo permitiera, el síntoma sería
  que el botón no hace nada hasta abrir la app.
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
