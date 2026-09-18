#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Writes Localization/<lang>.lproj/Localizable.strings.

Spanish is the development language: the literals in the code are the keys, so es.lproj
only has to exist. Every other language needs every key — `check` lists the ones missing.

    python3 Tools/translations.py          write the files
    python3 Tools/translations.py check    compare the keys in the code with these
"""
import glob, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# key: (en, fr, de, pt)
T = {
    "5 segundos": ("5 seconds", "5 secondes", "5 Sekunden", "5 segundos"),
    "10 segundos": ("10 seconds", "10 secondes", "10 Sekunden", "10 segundos"),
    "20 segundos": ("20 seconds", "20 secondes", "20 Sekunden", "20 segundos"),
    "30 segundos": ("30 seconds", "30 secondes", "30 Sekunden", "30 segundos"),
    "Abrir MacRadio": ("Open MacRadio", "Ouvrir MacRadio", "MacRadio öffnen", "Abrir o MacRadio"),
    "Abrir al iniciar sesión": ("Open at login", "Ouvrir à l’ouverture de session", "Beim Anmelden öffnen", "Abrir ao iniciar sessão"),
    "Abrir en Apple Music": ("Open in Apple Music", "Ouvrir dans Apple Music", "In Apple Music öffnen", "Abrir no Apple Music"),
    "Ajustes…": ("Settings…", "Réglages…", "Einstellungen …", "Definições…"),
    "Aquí va la letra de la canción": ("Here go the song’s lyrics", "Ici, les paroles de la chanson", "Hier steht der Songtext", "Aqui fica a letra da canção"),
    "Artista": ("Artist", "Artiste", "Künstler", "Artista"),
    "Añadida": ("Added", "Ajoutée", "Hinzugefügt", "Adicionada"),
    "Añadir": ("Add", "Ajouter", "Hinzufügen", "Adicionar"),
    "Añadir emisora": ("Add Station", "Ajouter une station", "Sender hinzufügen", "Adicionar estação"),
    "Añadir una emisora a mano…": ("Add a Station Manually…", "Ajouter une station manuellement…", "Sender manuell hinzufügen …", "Adicionar estação manualmente…"),
    "Bajar volumen": ("Volume Down", "Baisser le volume", "Leiser", "Diminuir volume"),
    "Busca emisoras": ("Search for Stations", "Rechercher des stations", "Sender suchen", "Procurar estações"),
    "Busca emisoras o añade una con su dirección de stream.": ("Search for stations or add one by its stream address.", "Recherchez des stations ou ajoutez-en une avec l’adresse de son flux.", "Suche nach Sendern oder füge einen mit seiner Stream-Adresse hinzu.", "Procure estações ou adicione uma pelo endereço do stream."),
    "Buscando la letra…": ("Looking for the lyrics…", "Recherche des paroles…", "Songtext wird gesucht …", "A procurar a letra…"),
    "Buscando…": ("Searching…", "Recherche…", "Suche …", "A procurar…"),
    "Buscar": ("Search", "Rechercher", "Suchen", "Procurar"),
    "Buscar emisoras…": ("Search for Stations…", "Rechercher des stations…", "Sender suchen …", "Procurar estações…"),
    "Búfer": ("Buffer", "Mémoire tampon", "Puffer", "Buffer"),
    "Cancelar": ("Cancel", "Annuler", "Abbrechen", "Cancelar"),
    "Canción en directo": ("Live song", "Chanson en direct", "Live-Song", "Canção em direto"),
    "Comprueba la conexión y vuelve a intentarlo.": ("Check your connection and try again.", "Vérifiez la connexion et réessayez.", "Prüfe die Verbindung und versuche es erneut.", "Verifique a ligação e tente novamente."),
    "Con la app abierta, los botones del widget responden al instante.": ("With the app open, the widget’s buttons respond instantly.", "Quand l’app est ouverte, les boutons du widget réagissent aussitôt.", "Ist die App geöffnet, reagieren die Tasten des Widgets sofort.", "Com a app aberta, os botões do widget respondem de imediato."),
    "Conectando…": ("Connecting…", "Connexion…", "Verbinden …", "A ligar…"),
    "Controles": ("Controls", "Commandes", "Steuerung", "Controlos"),
    "Código de país de dos letras. Déjalo vacío para buscar en todo el mundo.": ("Two-letter country code. Leave it empty to search worldwide.", "Code pays à deux lettres. Laissez vide pour chercher dans le monde entier.", "Zweistelliger Ländercode. Leer lassen, um weltweit zu suchen.", "Código de país de duas letras. Deixe vazio para procurar em todo o mundo."),
    "Dirección del stream": ("Stream address", "Adresse du flux", "Stream-Adresse", "Endereço do stream"),
    "Editar emisora": ("Edit Station", "Modifier la station", "Sender bearbeiten", "Editar estação"),
    "Editar…": ("Edit…", "Modifier…", "Bearbeiten …", "Editar…"),
    "Elige qué emisoras aparecen como botones en el widget.": ("Choose which stations appear as buttons on the widget.", "Choisissez les stations qui apparaissent comme boutons dans le widget.", "Wähle, welche Sender als Tasten im Widget erscheinen.", "Escolha que estações aparecem como botões no widget."),
    "Elige una emisora": ("Choose a station", "Choisissez une station", "Wähle einen Sender", "Escolha uma estação"),
    "Eliminar": ("Delete", "Supprimer", "Löschen", "Apagar"),
    "Emisora": ("Station", "Station", "Sender", "Estação"),
    "Emisora anterior": ("Previous Station", "Station précédente", "Vorheriger Sender", "Estação anterior"),
    "Emisora siguiente": ("Next Station", "Station suivante", "Nächster Sender", "Estação seguinte"),
    "Emisoras": ("Stations", "Stations", "Sender", "Estações"),
    "Emisoras del widget": ("Widget Stations", "Stations du widget", "Sender im Widget", "Estações do widget"),
    "En directo": ("Live", "En direct", "Live", "Em direto"),
    "En directo · la emisora no dice qué suena": ("Live · the station doesn’t say what’s playing", "En direct · la station n’indique pas ce qui passe", "Live · der Sender verrät nicht, was läuft", "Em direto · a estação não diz o que está a tocar"),
    "En pausa": ("Paused", "En pause", "Pausiert", "Em pausa"),
    "Escuchar %@": ("Listen to %@", "Écouter %@", "%@ hören", "Ouvir %@"),
    "Escuchar emisora": ("Play Station", "Écouter une station", "Sender abspielen", "Ouvir estação"),
    "Escúchala sin añadirla": ("Listen without adding it", "L’écouter sans l’ajouter", "Anhören, ohne hinzuzufügen", "Ouvir sem adicionar"),
    "Guardar": ("Save", "Enregistrer", "Sichern", "Guardar"),
    "Género (opcional)": ("Genre (optional)", "Genre (facultatif)", "Genre (optional)", "Género (opcional)"),
    "Has sintonizado a mitad de canción: la letra irá sincronizada desde la siguiente.": ("You tuned in mid-song: the lyrics will follow along from the next one.", "Vous avez pris la chanson en cours : les paroles seront synchronisées dès la suivante.", "Du hast mitten im Song eingeschaltet: Ab dem nächsten läuft der Text synchron mit.", "Sintonizou a meio da canção: a letra acompanha a partir da próxima."),
    "Haz clic con el botón derecho en el escritorio, elige «Editar widgets…» y busca MacRadio. Para elegir sus emisoras, haz clic con el botón derecho sobre el widget y elige «Editar “MacRadio”».": (
        "Right-click the desktop, choose “Edit Widgets…” and search for MacRadio. To pick its stations, right-click the widget and choose “Edit “MacRadio””.",
        "Faites un clic droit sur le bureau, choisissez « Modifier les widgets… » et cherchez MacRadio. Pour choisir ses stations, faites un clic droit sur le widget et choisissez « Modifier “MacRadio” ».",
        "Klicke mit der rechten Maustaste auf den Schreibtisch, wähle „Widgets bearbeiten …“ und suche nach MacRadio. Um die Sender auszuwählen, klicke mit der rechten Maustaste auf das Widget und wähle „„MacRadio“ bearbeiten“.",
        "Clique com o botão direito na secretária, escolha «Editar widgets…» e procure MacRadio. Para escolher as estações, clique com o botão direito no widget e escolha «Editar “MacRadio”»."),
    "Instrumental ♪": ("Instrumental ♪", "Instrumental ♪", "Instrumental ♪", "Instrumental ♪"),
    "La letra aparece cuando la emisora dice qué canción suena.": ("Lyrics appear when the station says which song is playing.", "Les paroles s’affichent quand la station indique la chanson en cours.", "Der Text erscheint, sobald der Sender verrät, welcher Song läuft.", "A letra aparece quando a estação diz que canção está a tocar."),
    "Letra": ("Lyrics", "Paroles", "Songtext", "Letra"),
    "Listo": ("Done", "Terminé", "Fertig", "OK"),
    "Lo que suena, con carátula, y tus emisoras a un clic. En el tamaño grande, también la letra.": ("What’s playing, with its cover, and your stations one click away. The large size adds the lyrics.", "Ce qui passe, avec sa pochette, et vos stations en un clic. En grand format, les paroles aussi.", "Was gerade läuft, mit Cover, und deine Sender mit einem Klick. In groß auch der Songtext.", "O que está a tocar, com a capa, e as suas estações a um clique. No tamanho grande, também a letra."),
    "Logo (dirección de la imagen, opcional)": ("Logo (image address, optional)", "Logo (adresse de l’image, facultatif)", "Logo (Bildadresse, optional)", "Logótipo (endereço da imagem, opcional)"),
    "MacRadio": ("MacRadio", "MacRadio", "MacRadio", "MacRadio"),
    "Mis emisoras": ("My Stations", "Mes stations", "Meine Sender", "As minhas estações"),
    "Mostrar en la barra de menús": ("Show in menu bar", "Afficher dans la barre des menus", "In der Menüleiste anzeigen", "Mostrar na barra de menus"),
    "Más de 50.000 emisoras de todo el mundo, del directorio Radio Browser.": ("Over 50,000 stations worldwide, from the Radio Browser directory.", "Plus de 50 000 stations du monde entier, issues de l’annuaire Radio Browser.", "Über 50.000 Sender aus aller Welt, aus dem Verzeichnis Radio Browser.", "Mais de 50 000 estações de todo o mundo, do diretório Radio Browser."),
    "No hay letra para esta canción.": ("No lyrics for this song.", "Pas de paroles pour cette chanson.", "Für diesen Song gibt es keinen Text.", "Não há letra para esta canção."),
    "No se pudo buscar": ("Couldn’t Search", "Recherche impossible", "Suche nicht möglich", "Não foi possível procurar"),
    "Nombre": ("Name", "Nom", "Name", "Nome"),
    "Nombre de la emisora": ("Station name", "Nom de la station", "Sendername", "Nome da estação"),
    "Pausar": ("Pause", "Pause", "Pause", "Pausa"),
    "País": ("Country", "Pays", "Land", "País"),
    "País (opcional)": ("Country (optional)", "Pays (facultatif)", "Land (optional)", "País (opcional)"),
    "Pone una de tus emisoras en MacRadio.": ("Plays one of your stations in MacRadio.", "Lance l’une de vos stations dans MacRadio.", "Spielt einen deiner Sender in MacRadio.", "Toca uma das suas estações no MacRadio."),
    "Probar": ("Try", "Essayer", "Probehören", "Experimentar"),
    "Reconectando…": ("Reconnecting…", "Reconnexion…", "Neu verbinden …", "A religar…"),
    "Reproducir": ("Play", "Lire", "Wiedergabe", "Reproduzir"),
    "Reproducir o pausar la radio": ("Play or Pause the Radio", "Lire ou mettre en pause la radio", "Radio abspielen oder pausieren", "Reproduzir ou pausar a rádio"),
    "Salir": ("Quit", "Quitter", "Beenden", "Sair"),
    "Selecciona una emisora en la barra lateral para empezar a escucharla.": ("Select a station in the sidebar to start listening.", "Sélectionnez une station dans la barre latérale pour l’écouter.", "Wähle in der Seitenleiste einen Sender, um ihn zu hören.", "Selecione uma estação na barra lateral para começar a ouvir."),
    "Sin datos de la canción": ("No song information", "Aucune info sur la chanson", "Keine Songinfos", "Sem dados da canção"),
    "Sin emisoras": ("No Stations", "Aucune station", "Keine Sender", "Sem estações"),
    "Sonando": ("Playing", "En lecture", "Läuft", "A tocar"),
    "Subir volumen": ("Volume Up", "Augmenter le volume", "Lauter", "Aumentar volume"),
    "Tiene que ser una dirección http o https.": ("It has to be an http or https address.", "Il doit s’agir d’une adresse http ou https.", "Es muss eine http- oder https-Adresse sein.", "Tem de ser um endereço http ou https."),
    "Un búfer mayor aguanta mejor los cortes de red, pero tarda más en empezar a sonar. Se aplica al cambiar de emisora.": ("A bigger buffer rides out network drops better but takes longer to start. Applies when you change station.", "Une mémoire tampon plus grande résiste mieux aux coupures réseau, mais la lecture démarre plus lentement. S’applique au changement de station.", "Ein größerer Puffer übersteht Netzausfälle besser, startet aber langsamer. Gilt beim Senderwechsel.", "Um buffer maior aguenta melhor as falhas de rede, mas demora mais a começar. Aplica-se ao mudar de estação."),
    "Volumen": ("Volume", "Volume", "Lautstärke", "Volume"),
    "Widget": ("Widget", "Widget", "Widget", "Widget"),
    "Ya tienes una emisora con esta dirección.": ("You already have a station with this address.", "Vous avez déjà une station avec cette adresse.", "Du hast bereits einen Sender mit dieser Adresse.", "Já tem uma estação com este endereço."),
    "línea a línea, a su ritmo": ("line by line, in time", "ligne après ligne, en rythme", "Zeile für Zeile, im Takt", "linha a linha, ao seu ritmo"),
    "que suena en la radio,": ("playing on the radio,", "qui passe à la radio,", "der im Radio läuft,", "que toca na rádio,"),
}
LANGS = ["en", "fr", "de", "pt"]


def code_keys():
    pat = re.compile(r'(?:Text|Button|Label|Section|Toggle|TextField|Picker|Link|CommandMenu|ContentUnavailableView|ProgressView|help|note|configurationDisplayName|description|IntentDescription|TypeDisplayRepresentation\(name:|Parameter\(title:|localized:|accessibilityLabel|LocalizedStringKey|return|Window)\s*\(?\s*"((?:[^"\\]|\\.)*)"')
    keys = set()
    for f in glob.glob(os.path.join(ROOT, "*", "*.swift")):
        if "/Tools/" in f:
            continue
        src = open(f, encoding="utf-8").read()
        for m in list(pat.finditer(src)) + list(re.finditer(r'(?:\{|\?|:) "([^"]+)"(?: \}|\s*:|\s*$)', src, re.M)):
            k = re.sub(r'\\\([^)]*\)', '%@', m.group(1))
            if re.search(r'[A-Za-zÁÉÍÓÚáéíóúñ]', k) and not re.fullmatch(r'[a-z0-9.\-]+', k):
                keys.add(k)
    return keys


def escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "check":
        missing = sorted(k for k in code_keys() if k not in T)
        print("\n".join(missing) if missing else "Todas las cadenas del código están traducidas.")
        sys.exit(1 if missing else 0)
    for i, lang in enumerate(LANGS):
        lines = [f"/* MacRadio — {lang}. Generado por Tools/translations.py: edita allí. */", ""]
        lines += [f'"{escape(k)}" = "{escape(v[i])}";' for k, v in sorted(T.items())]
        path = os.path.join(ROOT, "Localization", f"{lang}.lproj", "Localizable.strings")
        open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    es = os.path.join(ROOT, "Localization", "es.lproj", "Localizable.strings")
    open(es, "w", encoding="utf-8").write("/* Español: idioma base. Las claves son los literales del código. */\n")
    print(f"{len(T)} cadenas × {len(LANGS)} idiomas")
