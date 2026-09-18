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

## Pendiente

### Por verificar a mano
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
