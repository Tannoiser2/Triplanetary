# Piano di test

## Strategia

Piramide: unitari headless per geometria/regole; golden tests su scenari; integrazione reducer/eventi; test scene/UI per input e plancia; export Web come smoke test; sessioni manuali per regole ambigue. Ogni bug di regola riceve prima un test riproducibile.

## Matrice prioritaria

| Area | Casi minimi | Livello |
|---|---|---|
| Hex | 6 vicini, distanza, somma/sottrazione, linee e tie | unit |
| Inerzia | fermo, vettori in 6 direzioni, velocità >1 | unit |
| Spinta | 1 carburante, zero carburante, rallentamento, sovraccarica | unit |
| Gravità | effetto t+1, più campi, ordine, campo debole scelto/ignorato, due deboli | unit/golden |
| Orbita | sei passaggi stabili, uscita, atterraggio, decollo/ricaduta | golden |
| Collisioni | disco, tangente, bordo corpo, uscita mappa | geometry |
| Asteroidi | velocità 1/2, più hex, lato condiviso | unit |
| Fuoco | ogni cella tabella, tutti rapporti, arrotondamenti, range, velocità 2/3, eroismo | table/property |
| Danni | D1..D5, cumulo a 6, recovery fase, dreadnought | state |
| Ordigni | lancio, massa, durata 5, matrice collisioni, più bersagli | golden |
| Basi | match course, rifornimento, manutenzione, booster, difesa | integration |
| Detector | range 3/5, persistenza, reset base | integration |
| Cargo | capienza, oggetto indivisibile, nuke commerciale, base orbitale | unit |
| Replay | stesso seed/eventi = stesso hash; import/export | deterministic |
| Hot-seat | privacy screen, nessuna informazione avversaria | scene/UI |
| Grand Tour | visita, esclusione weak, ritorno, tie fuel | scenario |

## Golden fixtures

Trascrivere figure 2–8 come fixture con posizione/vettore/gravità e output atteso. Conservare screenshot di confronto, ma non includere scansioni coperte da copyright nei test distribuiti. Creare diagrammi originali equivalenti.

## Property tests

- `distance(a,b) == distance(b,a)` e disuguaglianza triangolare.
- Senza accelerazione, `v(t+1)==v(t)`.
- Il carburante non cresce salvo evento di rifornimento.
- Un'entità distrutta non torna attiva.
- Nessuna nave attacca o viene attaccata due volte nella stessa fase.
- Il replay non dipende da FPS, risoluzione o locale.

## Criteri di uscita MVP

Tutti i P0 verdi; 100% righe tabella combattimento coperte; figure movimento validate; 10 replay Grand Tour identici; salvataggio/caricamento in ogni fase; partita completa hot-seat senza modificare JSON a mano; nessun asset non autorizzato nella build.

## Test già presenti

`tests/run_tests.gd` contiene 18 controlli per inerzia, gravità differita/debole, supercover, sovraccarico, decollo/ricaduta, collisioni, persistenza, dichiarazione/contrattacco, danni cumulativi, distanza e tabella di combattimento. Si esegue con `godot --headless --path . --script tests/run_tests.gd`. Restano smoke test, non il criterio finale.
