# MacRadio

Radio por internet para macOS, hermana de [RadioApp](https://github.com/baltamir1978/RadioApp) para
iOS: tus emisoras con carátula, **letra sincronizada**, historial con favoritas y un **widget de
escritorio** desde el que elegir emisora y ver lo que suena.

**Versión: 1.0** · macOS 26 o posterior · Swift 6 · Estado y pendientes en [REVISION.md](REVISION.md)

## Características

- 🎵 **Reproducción** sobre `AVPlayer`, con el mismo motor que RadioApp: proxy local para emisoras
  que describen mal su stream, reconexión automática, conexión de reserva sin cortes
  (*make-before-break*) y reconexión inmediata al despertar el Mac.
- 🖼️ **Carátula** del disco vía iTunes Search; si la emisora no manda título, vía **Shazam**.
- 📝 **Letra sincronizada** (LRCLIB), línea a línea, en la ventana y en el widget grande.
- 🔎 **Shazam** sobre el propio stream, sin micrófono, en cualquier salida de audio. En las
  emisoras que no dicen qué suena (Kiss FM) identifica solo cada minuto, y también cuando una
  emisora deja de cambiar el título (ver «Títulos que se quedan»).
- 🕑 **Historial** con favoritas (♥), búsqueda y lista de títulos ignorados (eslóganes de emisora).
- 🔇 **Salto de la cuña de entrada** que algunas emisoras ponen a cada oyente al conectarse.
- 🧩 **Widget** de escritorio en cuatro tamaños, con botones para elegir emisora, pausar, pasar
  de emisora, marcar favorita e identificar la canción.
- 📋 **Barra de menús** con minirreproductor; **teclas multimedia** y **Centro de control**.
- ⚡️ **Atajos**: escuchar emisora, reproducir/pausar, siguiente/anterior, favorita, identificar.
- 🌍 Español, inglés, francés, alemán y portugués. ♿️ VoiceOver, contraste AA, *Reducir movimiento*.

## Compilar e instalar

```sh
./build.sh             # compila en build/ (Release, firmado con Developer ID)
./build.sh --install   # y además la instala en /Applications y la abre
```

`build.sh` regenera antes el proyecto y comprueba que no falte ninguna traducción. El widget
aparece en la galería (clic derecho en el escritorio → *Editar widgets…* → MacRadio) una vez
instalada la app en /Applications.

## Estructura

```
MacRadio/
├── MacRadio/             App: reproductor, servicios y vistas
├── MacRadioWidget/       Extensión WidgetKit (configuración y línea de tiempo)
├── Shared/               Compilado en los dos: estado compartido, App Intents, vistas del widget
├── Localization/         <idioma>.lproj/Localizable.strings — generados, ver abajo
└── Tools/
    ├── generate_project.rb   Genera MacRadio.xcodeproj
    ├── translations.py       Traducciones y comprobación de cadenas
    └── make_icon.swift       Icono de macOS a partir del de iOS
```

> **El `.xcodeproj` es un resultado, no una fuente.** Lo genera `ruby Tools/generate_project.rb`
> (gema `xcodeproj`), que recoge solo los `.swift` de cada carpeta. Los ajustes de los targets
> van en ese script: lo que se cambie a mano en Xcode se pierde al regenerar.

## Cómo habla el widget con la app

El widget es otro proceso, en su propio sandbox: no puede tocar el reproductor. Se comunican por
el **App Group** `JKMR84FU58.Altamirano.MacRadio`, con ficheros en vez de `UserDefaults`:

| Fichero del contenedor | Lo escribe | Lo lee |
|---|---|---|
| `nowplaying.json` | la app, en cada cambio | el widget |
| `stations.json` | la app | el widget y su pantalla de configuración |
| `Images/` | la app (logos y carátulas, reducidos) | el widget, que no puede descargar imágenes |
| `Commands/` | el widget (una orden por fichero) | la app, al recibir la notificación Darwin |

Los botones del widget son `AppIntent`. `PlayerCommand.dispatch()` sabe en qué proceso corre:
dentro de la app actúa directamente; dentro del widget deja la orden en `Commands/`, avisa con
una notificación Darwin, arranca la app en segundo plano si no está abierta y escribe ya el
estado que la orden va a producir, porque WidgetKit redibuja en cuanto `perform()` termina.

El prefijo de equipo en el App Group no es decorativo: en macOS es lo que permite usar el
contenedor con firma Developer ID sin perfil de aprovisionamiento y sin que el sistema pregunte
si la app puede «acceder a datos de otras apps».

La letra avanza en el widget sin despertar la app: la línea de tiempo lleva una entrada por cada
línea sincronizada que queda por cantar.

## Letra sincronizada: de dónde sale el tiempo

Las marcas de LRCLIB cuentan desde el inicio de la canción, y la emisora solo dice *qué* suena,
no *desde cuándo*. El inicio solo se da por bueno si viene de una de estas dos fuentes:

1. **Ver cambiar el título mientras se escucha.** Se toma la marca de tiempo del bloque de
   metadatos dentro del audio, no el momento en que llega el aviso.
2. **Shazam**, que devuelve la posición exacta en la canción (`predictedCurrentMatchOffset`). Si
   se sintoniza a mitad de una canción con letra sincronizada, se identifica una vez solo para
   eso, sin tocar título ni historial.

   Cuando Shazam escucha por una segunda conexión (la escucha directa del reproductor no recibe
   audio), el servidor abre con una **ráfaga de audio atrasado**: Cadena 100 manda 5,2 s en medio
   segundo y Kiss FM unos 5 s, y después sigue en tiempo real. ShazamKit da por hecho que el
   audio suena según llega, así que la ráfaga lo retrasaría; `StreamDecoder` la decodifica pero
   no se la pasa (el audio deja de adelantarse al reloj → empieza lo que va en tiempo real). A la
   posición que da Shazam se le suma lo que el reproductor tiene en el búfer.

El título llega al reproductor en su punto exacto del audio (medido: −0,008 s), pero **las
emisoras lo cambian tarde**: la canción nueva ya ha empezado, en el fundido o por el retardo del
codificador. Ese retraso es de la emisora, no de la conexión, así que se mide y se guarda: en cada
canción con letra sincronizada, a los ~20 s, Shazam da la posición exacta; eso corrige la letra en
el momento y actualiza el retraso de la emisora (`title_lag.<stream>`, promediado), que se descuenta
desde el cambio de título en las canciones siguientes.

### Títulos que se quedan

Algunas emisoras dejan de cambiar el título: Cadena 100 siguió mandando una canción ya acabada
durante toda la siguiente. Por eso, si pasa la duración de la canción (la da LRCLIB; 5 min si
no se sabe) más 20 s y el título no ha cambiado, se pregunta a Shazam:

- **Otra canción**: el título de la emisora se da por caducado, se ignora aunque vuelva a llegar
  y Shazam nombra las canciones (pantalla, historial, widget) cada minuto, como en Kiss FM,
  hasta que la emisora mande un título nuevo. Si ese título es la canción que ya ha puesto
  Shazam, se queda como está, sin repetirla en el historial.
- **Nada reconocido** (anuncios, locutor): se vuelve al logo de la emisora y se sigue probando.
- **La misma canción** (una versión más larga): se vuelve a mirar al cabo de un minuto.

Si no hay ninguna fuente fiable, la letra se muestra entera y sin resaltar. Encima de todo, la
letra se adelanta 1 s (se lee justo antes de cantarse). Y siempre se puede ajustar a mano:

- **Clic en la línea que está sonando**: la letra sigue desde ahí. Si ya se sabía el inicio de
  la canción, la corrección se guarda como ajuste de la emisora y vale para las siguientes; si se
  había sintonizado a mitad, fija el inicio que faltaba.
- **− / +** junto a «Letra», o **⌥⌘→ / ⌥⌘←** en el menú Controles: medio segundo cada vez.
  Doble clic en el valor lo pone a cero. Se aplica también al widget.

Una letra de LRCLIB sin marcas de tiempo no puede seguir la canción; la ventana lo dice.

La letra se busca con el título y el artista que da la emisora; si no aparece, con los dos
cambiados de orden («Título - Artista»). Luego, las **colaboraciones**: LRCLIB guarda «El Canto
del Loco y Amaia Montero» con el primer nombre, así que se prueba con el artista principal
(separando por «y», «&», «,», «feat.», «ft.», «x», «con»…) y, por último, solo con el título,
aceptando únicamente un resultado de alguno de los artistas nombrados.

> Se probó a sacar el inicio del *now-playing* de AzuraCast más un retraso medido y guardado por
> emisora. No sirve: el retraso cambia en cada conexión (con cuña, sin ella, según el búfer) y la
> letra acababa desfasada varios segundos. Por eso no está.

## Cuñas de entrada

Algunos servidores (La Indie) mandan a cada oyente que se conecta unos 20 s de anuncios antes del
directo, y otra vez en cada reconexión. Es un fichero fijo: dos conexiones abiertas con unos
segundos de diferencia coinciden byte a byte exactamente lo que dura la cuña. `IntroLearner` lo
mide así la primera vez que suena la emisora (y cada hora, porque el anuncio rota), e
`IcyReframer`, dentro del proxy, la descarta en las conexiones siguientes.

- El stream intercala metadatos cada `icy-metaint` bytes, y el reproductor los cuenta desde el
  principio: quitar audio del frente obliga a desentrelazar y volver a entrelazar, o se pierden
  los títulos.
- La conexión con la que `AVPlayer` sondea el formato (`Range: bytes=0-1`) pasa sin tocar: si se
  le retiene la cuña, espera lo que dura y luego repite la espera en la conexión buena.
- Tras la cuña, el servidor manda el directo a tiempo real, sin colchón, así que en esas emisoras
  el búfer inicial baja a 3 s. Resultado: unos 10 s hasta el primer sonido, en vez de 20 s de
  anuncio. Se puede desactivar en Ajustes.

## Shazam y el App ID

ShazamKit exige que el **App ID tenga activado el servicio ShazamKit** en
[developer.apple.com](https://developer.apple.com/account/resources/identifiers/list):
*Identifiers → Altamirano.MacRadio → App Services → ShazamKit*. Sin eso, el servidor de Shazam
responde 401 y ShazamKit da el error 202 «Missing entitlements»; la app lo detecta, deja de
intentarlo y lo avisa en Ajustes. Comprobado firmando una copia con el App ID de RadioApp, que sí
lo tiene activado: con él reconoce al instante.

## Diagnóstico

Trazas con `os.Logger` bajo el subsistema `com.macradio.playback` (Console.app, o
`log stream --predicate 'subsystem == "com.macradio.playback"'`):

| Traza | Qué ha pasado |
|---|---|
| `watchdog fired after …s` | La conexión no sonaba y se reconstruye. |
| `woke from sleep — reconnecting` | El Mac ha despertado: la conexión vieja ya no sirve. |
| `station sends title and artist swapped` | La emisora manda «Título - Artista»; se corrige con iTunes. |
| `title timestamp is …s from playback` | Distancia entre el título en el audio y la reproducción. |
| `skipping the station's intro` | Se ha descartado la cuña de entrada. |
| `…: intro of N bytes` | Resultado de medir la cuña (0 = no tiene). |
| `match: … at …s` | Shazam ha reconocido la canción y dice por dónde va. |
| `second connection: …s of opening burst held back` | Audio atrasado de la ráfaga inicial que no se pasa a Shazam. |
| `player is …s behind the air` | Lo que el reproductor tiene en el búfer, sumado a la posición de Shazam. |
| `lyrics synced by ShazamKit` | Shazam ha fijado la posición exacta de la canción. |
| `… changes its titles …s late` | Retraso medido entre el inicio real de la canción y su título. |
| `title unchanged past the song's end` | La canción debería haber acabado y el título sigue: se pregunta a Shazam. |
| `station title is stale — …` | Suena otra cosa: Shazam nombra las canciones hasta el próximo título. |
| `ShazamKit error: … 202` | Falta activar ShazamKit en el App ID (ver arriba). |

Para comprobar el diseño del widget sin tocar el escritorio, la app lo dibuja a PNG en todos los
tamaños, en claro y oscuro (dentro de su contenedor, por el sandbox):

```sh
/Applications/MacRadio.app/Contents/MacOS/MacRadio --render-widgets ~/Library/Containers/Altamirano.MacRadio/Data/tmp/widgets
```

## Idiomas

El español es el idioma base: los literales del código son las claves. Las traducciones viven en
`Tools/translations.py`, que genera los `.strings` de los dos bundles (la extensión no puede leer
los de la app). `python3 Tools/translations.py check` lista las cadenas del código sin traducir.
Ojo con los ternarios: `Button(cond ? "A" : "B")` pasa un `String` y **no se traduce**; hay que
escribir `LocalizedStringKey("A")` en una de las ramas.

## Diseño

Sigue las guías de macOS 27: barra lateral y barras de herramientas del sistema sin fondos
propios, y menús contextuales sin iconos. La paleta es la de RadioApp, con contraste AA y
variantes oscuras, definida una sola vez en `Shared/Palette.swift` para la app y el widget.

## Privacidad

Sin backend, sin analítica, sin SDK de terceros. Las emisoras, el historial y los ajustes se
quedan en el Mac. Solo se conecta a las emisoras y a Radio Browser, iTunes Search, LRCLIB y
Shazam, sin cuenta ni identificador.

## Licencia

Proyecto personal de Bruno Altamirano. Todos los derechos reservados salvo indicación contraria.
