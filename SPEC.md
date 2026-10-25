# Specifica funzionale

## Scopo v1

Gioco Godot locale, hot-seat per due giocatori, senza server, esportabile in futuro anche Web/HTML5. Regole di riferimento: Updated Second Edition. Primo scenario: Grand Tour. Il giocatore può creare/salvare/caricare una partita, impartire ordini, avanzare le fasi, vedere previsione e vettore effettivo, consultare registro e riprodurre una partita.

## Requisiti verificabili

### Stato e determinismo

- `GAME-001` Tutto lo stato serializzabile è JSON: versione schema, scenario, seed, turno, segmento, fase, entità, ordini, visibilità, economia e log.
- `GAME-002` Nessun calcolo di regole dipende dall'orologio, dallo scene tree o dal renderer Godot.
- `GAME-003` Seed + snapshot iniziale + eventi ordinati producono hash finale identico.
- `GAME-004` Autosave locale alla fine di ogni fase; salvataggi nominati e import/export JSON.

### Astrogazione

- `MOVE-001` Coordinate assiali intere `(q,r)`; velocità e accelerazioni sono vettori esagonali.
- `MOVE-002` La previsione mostra inerzia, gravità pendente, spinta e destinazione separatamente.
- `MOVE-003` L'attraversamento usa una linea esagonale deterministica; i casi sul bordo richiedono tie-break documentato.
- `MOVE-004` Ogni campo attraversato accoda gravità per il movimento del turno seguente, in ordine.
- `MOVE-005` Scelta della gravità debole registrata come evento.
- `MOVE-006` Collisioni con corpi usano una maschera/segmento geometrico sub-esagono derivato dai dati della mappa, non il solo esagono.
- `MOVE-007` Sovraccarica disponibile solo a navi da guerra e consumata fino alla manutenzione.

### Sequenza simultaneità

- `TURN-001` Segmenti P1/P2, cinque fasi, passaggio esplicito.
- `TURN-002` Contrattacchi dichiarati e risolti prima dell'applicazione dei danni dell'attacco iniziale.
- `TURN-003` Scadenza ordigni e disabilitazioni legata alla fase d'origine, non a un semplice contatore globale.

### Combattimento e ordigni

- `COMBAT-001` Raggruppamento attaccanti/difensori con vincoli una volta per fase.
- `COMBAT-002` Distanza = minima distanza alla posizione finale del bersaglio; velocità relativa = distanza tra vettori traslati.
- `COMBAT-003` Tabella dati esterna versionata; risultato e modificatori esplicitati nel log.
- `ORD-001` Mina/siluro/nuke sono entità con proprietario, vettore, età e matrice collisioni.
- `ORD-002` La selezione sequenziale dei bersagli di un siluro è evento esplicito.

### Informazione nascosta

- `FOG-001` Hot-seat privacy screen prima del cambio giocatore.
- `FOG-002` Entità non rilevate omesse o mascherate in UI; il motore conserva lo stato autorevole.
- `FOG-003` Identità segrete/decoy per scenario persistono in salvataggio cifrato solo come futura opzione; in v1 il file locale è considerato trusted.

### Basi e logistica

- `BASE-001` Relazione nave-base validata per superficie/orbita/asteroide.
- `BASE-002` Rifornimento ripristina carburante, munizioni ammesse e manutenzione; impone i divieti di fuoco/lancio.
- `CARGO-001` Inventario con massa indivisibile e vincoli per tipo nave.
- `TRANSFER-001` Stessa posizione e stesso vettore richiesti; saccheggio/soccorso/cattura producono eventi atomici.

### Grand Tour MVP

- `GT-001` Ogni giocatore controlla una corvetta su Terra.
- `GT-002` Carburante gratuito solo a Terra, Venere, Marte e Callisto.
- `GT-003` Una visita conta quando la nave attraversa almeno un esagono di gravità piena del corpo.
- `GT-004` Sono richiesti tutti i corpi dotati di gravità piena definiti dalla mappa dello scenario; corpi deboli esclusi.
- `GT-005` Vince la prima nave che, dopo tutte le visite, atterra legalmente su Terra.
- `GT-006` Pari tempo: minor carburante consumato. `TODO-RULE GT-01`: se anche il consumo è pari, il manuale non fornisce ulteriore spareggio; dichiarare ex aequo.
- `GT-007` Il combattimento è consentito.

## UX minima

Canvas pannabile/zoomabile, selezione nave, vettore colorato, previsione tratteggiata, campi di gravità, pannello nave, sequenza fase, conferma fine fase, registro filtrabile. Tastiera: frecce/1-6 per spinta, spazio per nessuna spinta, invio per confermare. Contrasto WCAG AA dove applicabile; stato non comunicato dal solo colore.

## Fuori scopo iniziale

Multiplayer di rete, AI, editor di mappe, pubblicazione di asset, animazioni fisiche continue, regole fisiche “corrette” proposte dal saggio.
