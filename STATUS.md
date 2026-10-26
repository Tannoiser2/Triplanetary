# Stato implementazione

Aggiornato al 26 ottobre 2026.

## Implementato e verificato

- Progetto Godot 4 e export Web single-threaded compatibile con GitHub Pages.
- Hot-seat a due giocatori e sequenza delle cinque fasi.
- Coordinate assiali, inerzia, una spinta per turno e consumo carburante.
- Sovraccarico da due accelerazioni, solo per nave militare, una volta tra manutenzioni.
- Gravità applicata al turno seguente e cumulativa.
- Gravità debole: prima freccia opzionale, seconda consecutiva obbligatoria.
- Tracciato supercover per intercettare passaggi lungo bordi esagonali.
- Partenza atterrata, booster di decollo, obbligo di accelerare dopo il decollo e ricaduta.
- Atterraggio da esagono orbitale a velocità uno, con costo di carburante.
- Collisione attraversando un corpo e distruzione uscendo dalla mappa.
- Visite Grand Tour, rifornimento alle quattro basi previste e condizione di vittoria.
- Salvataggio/caricamento locale e autosave a ogni avanzamento di fase.
- Tabella base del fuoco e RNG/risoluzione deterministica del motore.
- Attacco nave contro nave, scelta del contrattacco con passaggio di mano, distanza minima, velocità relativa, eroismo e applicazione simultanea dei risultati.
- Disabilitazioni cumulative e distruzione a sei turni residui.
- Mine, siluri e testate nucleari come entità vettoriali: inventario, massa, lancio, gravità, contatti ed eliminazione dopo cinque movimenti.
- Campi di asteroidi, rischio deterministico, asteroidi speciali e rimozione tramite testata nucleare.
- Regole motore per carico, capienza, trasferimento di materiali e carburante fra navi sulla stessa rotta.
- Rilevamento persistente da navi e basi, occultamento dopo l'atterraggio in una base amica e blocco del fuoco contro bersagli non rilevati.
- Schermata di passaggio hot-seat al cambio giocatore e prima della scelta riservata del contrattacco.
- Menu iniziale con catalogo degli otto scenari, scelta da 2 a 6 giocatori e nomi; solo Grand Tour è abilitato finché le regole specifiche degli altri scenari non sono complete.
- Plancia pubblica ridisegnata in stile astronomico scuro, anteprima tratteggiata del movimento e rotta percorsa persistente per ogni nave.
- Guida “Come si gioca” e suggerimento contestuale per ciascuna fase.
- Salvataggio portabile JSON tramite appunti, con import e preservazione dei vettori esagonali.
- Basi planetarie come entità dati e rifornimento solo dopo un atterraggio valido; fondazione del motore per basi orbitali/asteroidali e difese.
- Selezione esplicita di direzione e accelerazione 1/2 per il lancio dei siluri.
- Scheda e copertina originale per l'inclusione automatica nella Ludoteca Virtuale.
- Replay navigabile per fotogrammi, con stato delle navi e ultimo evento.
- Cataloghi dati separati e verificati per otto scenari, navi, equipaggiamento, costi e capacità dell'Updated Second Edition.
- Grand Tour configurabile da 2 a 6 giocatori.
- 35 test headless.

## Ancora incompleto

- Revisione manuale finale della trascrizione di ogni esagono della mappa, degli asteroidi, delle basi e dei detector.
- Collisione sub-esagono con il disco grafico anziché con l'intero esagono centrale.
- Attacchi combinati con più navi, ramming e selezione multipla dei bersagli.
- Interfaccia completa per carico e trasferimenti (le regole di motore sono presenti).
- Basi orbitali/asteroidali, difese, resa e cattura.
- Dummy e identità segrete (rilevamento, occultamento e schermata privacy hot-seat sono presenti).
- Replay navigabile ed export/import portabile del salvataggio.
- Gli altri sette scenari.

La build pubblica non include la scansione della plancia. La modalità locale può caricarla da `assets/local-reference/map-source.jpg`.
