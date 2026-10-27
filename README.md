# Triplanetary — versione digitale

Versione digitale per uso personale di *Triplanetary* (Game Designers' Workshop, 1973/1981, regole **Updated Second Edition**), realizzata in **Godot 4.7** e pubblicata su GitHub Pages per la Ludoteca Virtuale.

**Gioca:** <https://tannoiser2.github.io/Triplanetary/>

## Cosa c'è

- **Plancia fedele**: la mappa A4 di riferimento è stata trascritta esagono per esagono (2277 esagoni, 13 corpi, 77 esagoni di gravità, 67 asteroidi, 7 asteroidi speciali, basi sui lati dei pianeti) in `data/map.json`, e viene ridisegnata in modo procedurale: cielo stellato, Sole luminoso, pianeti illuminati da sinistra, frecce di gravità piene e vuote.
- **Movimento vettoriale completo**: inerzia, spinte da 1 carburante, sovraccarico delle navi da guerra, gravità acquisita e applicata al turno dopo, gravità debole (prima freccia facoltativa, seconda consecutiva obbligatoria), orbite stabili, atterraggio da orbita, decollo con booster e ricaduta, schianti calcolati sulla geometria del disco e non sull'intero esagono, uscita dalla plancia.
- **Combattimento**: attacchi di gruppo contro navi nello stesso esagono, colonne 1:2–4:1 arrotondate a favore del difensore, distanza minima dalla rotta, velocità relativa, eroismo, contrattacco prima dell'applicazione dei danni, disabilitazione cumulativa con distruzione a 6 turni, difese planetarie, speronamento.
- **Ordigni e pericoli**: mine, siluri (accelerazione 1–2 al lancio), testate nucleari, durata 5 turni, detonazioni contro navi, corpi, asteroidi e altri ordigni; asteroidi e asteroidi speciali di Clandestine.
- **Basi, rifornimento e rilevamento**: rifornimento a terra o in orbita sopra la base, manutenzione, carico degli ordigni, ispezione, trasferimenti con rotta accoppiata, resa, rilevatori a 3/5 esagoni con informazione nascosta.
- **Tutti gli otto scenari del manuale**:
  - *Grand Tour* (2–6 piloti), *Escape*, *Lateral 7*;
  - *Nova* (3 giocatori): spartizione di Terra e Luna, colonie tirate a sorte, flotte da 50 punti di forza, quattro corsari alieni con bombe Nova;
  - *Retribution*: dieci corvette ribelli una alla volta, Terran Security Patrol, Flotta della Libertà al doppio della forza;
  - *The Fleet Mutiny*: dodici navi e due basi orbitali imperiali, cinque unità designate che si ammutinano, soppressione dei lati della Terra, cattura delle basi;
  - *Interplanetary War*: flotte in MegaCrediti, depositi di ordigni, testate nucleari, produzione delle basi e crediti da trasportare con navi commerciali;
  - *Prospecting* (2–6 cercatori): prospezione a velocità 1, minerale e schegge CT, miniere automatiche, guardie robot, mercati di Ceres e Luna.
- **Avversario IA**: pianifica le rotte con una ricerca A* sugli stati vettoriali (posizione, velocità, gravità in sospeso), gestisce carburante e rifornimenti, intercetta, combatte, ispeziona. Non sbircia le informazioni nascoste.
- **Gioco online** su Firebase, come gli altri giochi della ludoteca (vedi sotto).
- **Hot-seat** con schermata di passaggio negli scenari con informazioni nascoste, salvataggio automatico, slot manuale e salvataggio portabile negli appunti.

## Comandi

| Azione | Mouse / tastiera |
|---|---|
| Selezionare una nave | clic sulla pedina o sulla scheda della flotta, `Tab` per la successiva |
| Spinta | clic su uno dei sei esagoni azzurri attorno al punto d'arrivo (`1`–`6`) |
| Deriva | clic sull'esagono centrale o `Spazio` |
| Sovraccarico | dopo la prima spinta, clic su un esagono arancio |
| Confermare la fase | pulsante arancio in basso o `Invio` |
| Zoom / spostamento | rotella / trascinamento, `F` per vedere tutta la plancia |
| Annullare la selezione | clic destro o `Esc` |
| Rotte percorse (scia di ogni nave) | pulsante **ROTTE** in basso o `R` |
| Vettori di deriva (inerzia tratteggiata, gravità in arrivo in ambra, esagono d'arrivo senza spinte) | pulsante **DERIVA** o `D` |
| Raggio dei rilevatori | pulsante **RADAR** o `V` |

La guida completa è nel pulsante **GUIDA** del gioco.

## Gioco online

Dal menu, sotto il dettaglio dello scenario, **GIOCA ONLINE** (anche dalla versione web). Usa lo stesso progetto
Firebase degli altri giochi (Realtime Database), con le stanze sotto `triplanetary/rooms`.

- **Chi crea la stanza** prepara gli equipaggi nel menu: il primo posto *UMANO* è il suo, gli altri posti
  *UMANO* sono per gli amici, i posti *IA* li gioca il suo dispositivo. Scrive il nome, preme *Crea una stanza*
  e comunica il codice di 4 lettere. Quando ci sono tutti preme *Inizia online*: i posti rimasti liberi li gioca l'IA.
- **Gli amici** scrivono il nome e il codice e premono *Entra*.
- **Come si sincronizza.** Un solo dispositivo alla volta ha la mano: quello del giocatore di turno (o di chi
  ha creato la stanza, per i colori IA). Quando la mano passa, chi la lascia pubblica nel registro della stanza
  (`acts/0`, `acts/1`, …) un'istantanea compressa dello stato, con gli spostamenti da animare; gli altri la
  ricevono e proseguono. Ogni istantanea pesa circa 5 kB. Ognuno vede la plancia dal punto di vista del proprio
  colore, quindi le informazioni nascoste restano nascoste (nessuna schermata di passaggio).
- **Se cade la linea** si rientra dal menu con *Rientra nella stanza* (o con lo stesso codice ed *Entra*).
  Se un giocatore non dà segni di vita per un minuto, al suo posto gioca l'IA di chi ha creato la stanza
  finché non rientra.

**Configurazione Firebase.** Le stanze di Triplanetary sono coperte dalla regola generica `$game` già usata
dagli altri giochi; `firebase/database.rules.json` contiene comunque l'unione delle regole di tutti i giochi
della ludoteca più una sezione esplicita `triplanetary`. Se la creazione della stanza risponde
"Permission denied", vanno pubblicate nella console di Firebase (Realtime Database → Regole).

**Prove senza Firebase.** `tests/firebase_mock.py` è un finto Firebase locale. Con `TP_DB_URL`, `TP_AUTH_URL`
e `TP_REFRESH_URL` che puntano lì, `tests/online_play.gd` fa giocare una partita a due istanze
(`TP_ROLE=host` e `guest`, scenario in `TP_SCENARIO`; con `TP_DROP=1` l'ospite esce e rientra). Ognuna stampa
l'impronta dello stato per ogni voce del registro: devono coincidere.

## Sviluppo

```bash
godot --path . --editor                                  # editor
godot --headless --path . --script tests/run_tests.gd    # 95 controlli del motore e dell'IA
godot --headless --path . --export-release Web docs/index.html
```

La workflow `.github/workflows/pages.yml` pubblica la cartella `docs/` a ogni push su `main`.

```text
scripts/core/   regole pure e deterministiche: geometria, mappa, regole, scenari, IA, salvataggi
scripts/ui/     plancia, interfaccia, grafica procedurale, widget
scripts/net/    Firebase (REST) e partita online a istantanee
firebase/       regole del Realtime Database
data/map.json   plancia trascritta (generata da tools/build_map.py)
tools/          trascrizione della mappa e mappa sorgente di riferimento (escluse dalla build)
ludoteca/       scheda e copertina per la Ludoteca Virtuale
```

Il motore non dipende dalla scena: tutto lo stato è un dizionario serializzabile e ogni tiro di dado passa per il generatore nello stato, così una partita è riproducibile dallo stesso seme.

## Diritti

Codice e grafica procedurale sono originali. *Triplanetary*, il manuale e i materiali di riferimento appartengono ai rispettivi titolari; la copertina è usata per uso personale non commerciale. Font sotto licenza SIL OFL. Vedi `ASSET_MANIFEST.md` e `NOTICE.md`.
