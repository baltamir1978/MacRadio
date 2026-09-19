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
    "%@ · %@": ("%@ · %@", "%@ · %@", "%@ · %@", "%@ · %@"),
    "Adelantar la letra": ("Move Lyrics Earlier", "Avancer les paroles", "Songtext früher", "Adiantar a letra"),
    "Adelantar la letra medio segundo": ("Move the lyrics half a second earlier", "Avancer les paroles d’une demi-seconde", "Songtext eine halbe Sekunde früher", "Adiantar a letra meio segundo"),
    "Ajuste de la letra para esta emisora. Doble clic para volver a cero.": ("Lyrics timing for this station. Double-click to reset.", "Décalage des paroles pour cette station. Double-cliquez pour remettre à zéro.", "Textversatz für diesen Sender. Doppelklick setzt ihn zurück.", "Acerto da letra para esta estação. Duplo clique para repor."),
    "Ajuste de la letra: %@": ("Lyrics timing: %@", "Décalage des paroles : %@", "Textversatz: %@", "Acerto da letra: %@"),
    "Algunas emisoras ponen anuncios a cada oyente que se conecta. MacRadio los reconoce y se los salta: a cambio, la emisora tarda unos segundos más en empezar a sonar.": ("Some stations play ads to every listener who connects. MacRadio recognises and skips them; in exchange, the station takes a few seconds longer to start.", "Certaines stations diffusent des pubs à chaque auditeur qui se connecte. MacRadio les reconnaît et les saute ; en contrepartie, la station met quelques secondes de plus à démarrer.", "Manche Sender spielen jedem neuen Hörer Werbung vor. MacRadio erkennt und überspringt sie – dafür dauert der Start ein paar Sekunden länger.", "Algumas estações passam anúncios a cada ouvinte que se liga. O MacRadio reconhece-os e salta-os; em troca, a estação demora mais uns segundos a começar."),
    "Apple no ha autorizado a MacRadio a usar Shazam. Hay que activar ShazamKit para el identificador Altamirano.MacRadio en developer.apple.com.": ("Apple hasn’t authorised MacRadio to use Shazam. ShazamKit has to be enabled for the identifier Altamirano.MacRadio at developer.apple.com.", "Apple n’a pas autorisé MacRadio à utiliser Shazam. Il faut activer ShazamKit pour l’identifiant Altamirano.MacRadio sur developer.apple.com.", "Apple hat MacRadio die Nutzung von Shazam nicht erlaubt. ShazamKit muss für die Kennung Altamirano.MacRadio auf developer.apple.com aktiviert werden.", "A Apple não autorizou o MacRadio a usar o Shazam. É preciso ativar o ShazamKit para o identificador Altamirano.MacRadio em developer.apple.com."),
    "Averigua con Shazam qué canción suena en la emisora.": ("Finds out with Shazam which song the station is playing.", "Découvre avec Shazam la chanson diffusée par la station.", "Findet mit Shazam heraus, welcher Song gerade läuft.", "Descobre com o Shazam que canção está a tocar na estação."),
    "Buscar en el historial": ("Search History", "Rechercher dans l’historique", "Verlauf durchsuchen", "Procurar no histórico"),
    "Copiar título y artista": ("Copy Title and Artist", "Copier le titre et l’artiste", "Titel und Künstler kopieren", "Copiar título e artista"),
    "El historial está vacío": ("History Is Empty", "L’historique est vide", "Der Verlauf ist leer", "O histórico está vazio"),
    "En directo · no se ha reconocido la canción": ("Live · the song wasn’t recognised", "En direct · chanson non reconnue", "Live · Song nicht erkannt", "Em direto · a canção não foi reconhecida"),
    "En las emisoras que no dicen qué suena (como Kiss FM), MacRadio pregunta a Shazam cada minuto. Así aparecen la carátula, la letra sincronizada y el historial. Si sintonizas a mitad de canción, Shazam también dice por dónde va, para que la letra siga el ritmo.": ("On stations that don’t say what’s playing (like Kiss FM), MacRadio asks Shazam every minute, so you get the cover, synced lyrics and history. If you tune in mid-song, Shazam also tells where it is, so the lyrics keep time.", "Sur les stations qui n’indiquent pas ce qui passe (comme Kiss FM), MacRadio interroge Shazam chaque minute : pochette, paroles synchronisées et historique s’affichent. Si vous arrivez en cours de chanson, Shazam indique aussi où elle en est, pour que les paroles suivent.", "Bei Sendern, die nicht verraten, was läuft (wie Kiss FM), fragt MacRadio jede Minute Shazam – so erscheinen Cover, synchroner Text und Verlauf. Schaltest du mitten im Song ein, sagt Shazam auch, wo er gerade ist, damit der Text im Takt bleibt.", "Nas estações que não dizem o que está a tocar (como a Kiss FM), o MacRadio pergunta ao Shazam a cada minuto: assim aparecem a capa, a letra sincronizada e o histórico. Se sintonizar a meio da canção, o Shazam também diz onde vai, para a letra acompanhar."),
    "Favoritas": ("Favourites", "Favoris", "Favoriten", "Favoritas"),
    "Guarda la canción que suena entre tus favoritas de MacRadio, o la quita.": ("Adds the song that’s playing to your MacRadio favourites, or removes it.", "Ajoute la chanson en cours à vos favoris MacRadio, ou l’en retire.", "Fügt den laufenden Song deinen MacRadio-Favoriten hinzu oder entfernt ihn.", "Junta a canção que está a tocar às suas favoritas do MacRadio, ou retira-a."),
    "Historial": ("History", "Historique", "Verlauf", "Histórico"),
    "Historial de canciones (⌘Y)": ("Song History (⌘Y)", "Historique des chansons (⌘Y)", "Songverlauf (⌘Y)", "Histórico de canções (⌘Y)"),
    "Identificando la canción…": ("Identifying the song…", "Identification de la chanson…", "Song wird erkannt …", "A identificar a canção…"),
    "Identificar canciones automáticamente": ("Identify songs automatically", "Identifier les chansons automatiquement", "Songs automatisch erkennen", "Identificar canções automaticamente"),
    "Adelanta o retrasa la letra de la emisora que suena.": ("Moves the lyrics of the station playing earlier or later.", "Avance ou retarde les paroles de la station en cours.", "Verschiebt den Songtext des laufenden Senders nach vorn oder hinten.", "Adianta ou atrasa a letra da estação que está a tocar."),
    "Ajustar la letra": ("Adjust Lyrics", "Ajuster les paroles", "Songtext anpassen", "Ajustar a letra"),
    "Línea": ("Line", "Ligne", "Zeile", "Linha"),
    "Segundos": ("Seconds", "Secondes", "Sekunden", "Segundos"),
    "Sincroniza la letra con esta línea": ("Syncs the lyrics to this line", "Synchronise les paroles sur cette ligne", "Synchronisiert den Songtext mit dieser Zeile", "Sincroniza a letra com esta linha"),
    "Sincronizar la letra": ("Sync Lyrics", "Synchroniser les paroles", "Songtext synchronisieren", "Sincronizar a letra"),
    "Identificar la canción": ("Identify Song", "Identifier la chanson", "Song erkennen", "Identificar a canção"),
    "Identificar la canción (⌘I)": ("Identify Song (⌘I)", "Identifier la chanson (⌘I)", "Song erkennen (⌘I)", "Identificar a canção (⌘I)"),
    "Las canciones que suenen en tus emisoras irán apareciendo aquí.": ("Songs played on your stations will show up here.", "Les chansons diffusées sur vos stations apparaîtront ici.", "Die Songs deiner Sender erscheinen hier.", "As canções que tocarem nas suas estações vão aparecendo aqui."),
    "Las emisoras mandan a veces su eslogan como si fuera una canción. Estos títulos no se guardan en el historial.": ("Stations sometimes send their slogan as if it were a song. These titles aren’t saved to the history.", "Les stations envoient parfois leur slogan comme s’il s’agissait d’une chanson. Ces titres ne sont pas enregistrés dans l’historique.", "Sender schicken manchmal ihren Slogan, als wäre er ein Song. Diese Titel landen nicht im Verlauf.", "Às vezes as estações enviam o seu slogan como se fosse uma canção. Estes títulos não ficam no histórico."),
    "Marcar como favorita": ("Mark as Favourite", "Ajouter aux favoris", "Als Favorit markieren", "Marcar como favorita"),
    "Marcar la canción como favorita": ("Mark Song as Favourite", "Ajouter la chanson aux favoris", "Song als Favorit markieren", "Marcar a canção como favorita"),
    "Mostrar": ("Show", "Afficher", "Anzeigen", "Mostrar"),
    "Más": ("More", "Plus", "Mehr", "Mais"),
    "Más opciones": ("More Options", "Plus d’options", "Weitere Optionen", "Mais opções"),
    "Ningún título ignorado": ("No Ignored Titles", "Aucun titre ignoré", "Keine ignorierten Titel", "Nenhum título ignorado"),
    "No se ha reconocido la canción": ("The song wasn’t recognised", "Chanson non reconnue", "Song nicht erkannt", "A canção não foi reconhecida"),
    "No volver a guardar este título en %@": ("Never Save This Title on %@ Again", "Ne plus enregistrer ce titre sur %@", "Diesen Titel bei %@ nicht mehr speichern", "Não voltar a guardar este título em %@"),
    "Pulsa el corazón mientras suena una canción para guardarla aquí.": ("Click the heart while a song is playing to keep it here.", "Cliquez sur le cœur pendant une chanson pour la garder ici.", "Klicke während eines Songs auf das Herz, um ihn hier zu behalten.", "Clique no coração enquanto uma canção toca para a guardar aqui."),
    "Quitar de favoritas": ("Remove from Favourites", "Retirer des favoris", "Aus Favoriten entfernen", "Remover das favoritas"),
    "Poner la letra a cero": ("Reset Lyrics Timing", "Remettre les paroles à zéro", "Songtextversatz zurücksetzen", "Repor a letra a zero"),
    "Pone la letra a cero": ("Resets the lyrics timing", "Remet les paroles à zéro", "Setzt den Songtextversatz zurück", "Repõe a letra a zero"),
    "Retrasar la letra": ("Move Lyrics Later", "Retarder les paroles", "Songtext später", "Atrasar a letra"),
    "Retrasar la letra medio segundo": ("Move the lyrics half a second later", "Retarder les paroles d’une demi-seconde", "Songtext eine halbe Sekunde später", "Atrasar a letra meio segundo"),
    "Saltar la cuña de entrada": ("Skip connection ads", "Sauter les pubs de connexion", "Werbung beim Einschalten überspringen", "Saltar os anúncios de entrada"),
    "Se borran todas las canciones menos las favoritas.": ("Every song except your favourites is deleted.", "Toutes les chansons sont supprimées, sauf les favoris.", "Alle Songs außer den Favoriten werden gelöscht.", "São apagadas todas as canções exceto as favoritas."),
    "Shazam no está disponible para MacRadio": ("Shazam isn’t available to MacRadio", "Shazam n’est pas disponible pour MacRadio", "Shazam ist für MacRadio nicht verfügbar", "O Shazam não está disponível para o MacRadio"),
    "Sin favoritas": ("No Favourites", "Aucun favori", "Keine Favoriten", "Sem favoritas"),
    "Todas": ("All", "Toutes", "Alle", "Todas"),
    "Títulos ignorados": ("Ignored Titles", "Titres ignorés", "Ignorierte Titel", "Títulos ignorados"),
    "Títulos ignorados…": ("Ignored Titles…", "Titres ignorés…", "Ignorierte Titel …", "Títulos ignorados…"),
    "Vaciar": ("Clear", "Vider", "Leeren", "Limpar"),
    "Vaciar historial…": ("Clear History…", "Vider l’historique…", "Verlauf leeren …", "Limpar histórico…"),
    "¿Vaciar el historial?": ("Clear the history?", "Vider l’historique ?", "Verlauf leeren?", "Limpar o histórico?"),
    "Volver a guardar": ("Save Again", "Enregistrer à nouveau", "Wieder speichern", "Voltar a guardar"),
    "Sincroniza la letra desde esta línea": ("Syncs the lyrics from this line", "Synchronise les paroles à partir de cette ligne", "Synchronisiert den Text ab dieser Zeile", "Sincroniza a letra a partir desta linha"),
    "Suena ahora: sincronizar desde esta línea": ("Playing now: sync from this line", "En cours : synchroniser à partir de cette ligne", "Läuft gerade: ab dieser Zeile synchronisieren", "A tocar agora: sincronizar a partir desta linha"),
    "¿Va desfasada? Haz clic en la línea que está sonando.": ("Out of step? Click the line that’s being sung.", "Décalé ? Cliquez sur la ligne en train d’être chantée.", "Nicht im Takt? Klicke auf die Zeile, die gerade gesungen wird.", "Está desfasada? Clique na linha que está a tocar."),
    "No se sabe por dónde va la canción: haz clic en la línea que está sonando y la letra seguirá desde ahí.": ("It isn’t known how far into the song we are: click the line being sung and the lyrics will follow from there.", "On ne sait pas où en est la chanson : cliquez sur la ligne chantée et les paroles suivront à partir de là.", "Unklar, wo der Song gerade ist: Klicke auf die gesungene Zeile, und der Text läuft ab dort mit.", "Não se sabe em que ponto vai a canção: clique na linha que está a tocar e a letra acompanha a partir daí."),
    "Esta letra no trae tiempos, así que no puede seguir la canción.": ("These lyrics have no timings, so they can’t follow the song.", "Ces paroles n’ont pas de minutage : elles ne peuvent pas suivre la chanson.", "Dieser Text hat keine Zeitmarken und kann dem Song nicht folgen.", "Esta letra não traz tempos, por isso não pode acompanhar a canção."),
}
LANGS = ["en", "fr", "de", "pt"]
# Literals the scan picks up that never reach the screen through a localized API.
NOT_UI = {"ES", "±0 s"}


def code_keys():
    pat = re.compile(r'(?<![\w.])(?:Text|Button|Label|Section|Toggle|TextField|Picker|Link|CommandMenu|ContentUnavailableView|ProgressView|help|note|hint|configurationDisplayName|description|IntentDescription|TypeDisplayRepresentation\(name:|Parameter\(title:|localized:|accessibilityLabel|LocalizedStringKey|return|Window)\s*\(?\s*"((?:[^"\\\n]|\\.)*)"')
    keys = set()
    for f in glob.glob(os.path.join(ROOT, "*", "*.swift")):
        if "/Tools/" in f:
            continue
        src = open(f, encoding="utf-8").read()
        for m in list(pat.finditer(src)) + list(re.finditer(r'(?:\{|\?|:) "([^"\n]+)"(?: \}|[ \t]*:|[ \t]*$)', src, re.M)):
            k = re.sub(r'\\\([^)]*\)', '%@', m.group(1))
            if k in NOT_UI:
                continue
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
