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
- 18 test headless.

## Ancora incompleto

- Trascrizione certificata di ogni esagono della mappa, asteroidi, basi e detector.
- Collisione sub-esagono con il disco grafico anziché con l'intero esagono centrale.
- Attacchi combinati con più navi, ramming e selezione multipla dei bersagli.
- Mine, siluri e testate nucleari.
- Basi orbitali/asteroidali, difese, cargo, trasferimenti, resa e cattura.
- Fog of war, rilevamento, dummy e schermata privacy.
- Replay navigabile ed export/import portabile del salvataggio.
- Gli altri sette scenari.

La build pubblica non include la scansione della plancia. La modalità locale può caricarla da `assets/local-reference/map-source.jpg`.
