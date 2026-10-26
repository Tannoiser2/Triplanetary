# Stato del progetto

Aggiornato al 26 ottobre 2026 — riscrittura completa del motore e dell'interfaccia.

## Funziona

- Plancia trascritta e verificata visivamente sovrapponendo i dati alla mappa sorgente (`tools/verify` nel processo di `build_map.py`).
- Tutte le regole di movimento, combattimento, ordigni, pericoli, basi, rifornimento, rilevamento, trasferimenti e resa del manuale.
- Scenari **Grand Tour**, **Escape**, **Lateral 7** con condizioni di vittoria complete (livelli decisivo/marginale/morale).
- IA per tutti e tre gli scenari e per tutte le parti (piloti, Pellegrini, Enforcers, Pirati, Marina).
- Hot-seat, schermata di passaggio, salvataggi, export Web.
- 68 controlli automatici in `tests/run_tests.gd`, comprese partite complete IA contro IA.

## Scelte interpretative

- **Sol**: la mappa A4 usata ha un doppio anello di frecce attorno al Sole (frecce doppie nell'anello interno, coppie divergenti sui lati dell'anello esterno). È il comportamento predefinito; l'opzione *Sol classico* nel menu ripristina un solo anello come nella plancia GDW originale.
- **Gravità condivisa**: dove due corpi si toccano (Giove/Io) l'esagono applica entrambe le frecce.
- **Grand Tour**: i corpi a gravità piena sono Sol, Mercurio, Venere, Terra, Marte, Giove, Ganimede e Callisto. Le basi senza carburante (Mercurio, Luna, Io, Ganimede, Ceres, Clandestine) offrono comunque il booster. In caso di arrivo nello stesso giorno vince chi ha consumato meno carburante; a parità, ex aequo.
- **Escape**: "oltre Giove" è il bordo destro della plancia. I Pellegrini possono decollare dalla Terra anche se la base è degli Enforcers (il testo dice che possono partire "in qualunque modo").
- **Lateral 7**: Venere ha solo un porto civile (booster per la nave di linea, nessun rifornimento); "raggiunge Ganimede" = attraversa un esagono di gravità di Ganimede. I falsi bersagli entro la portata dei rilevatori nemici vengono smascherati.
- **Contrattacco**: colonna e modificatori sono ricalcolati per il contrattacco; i danni di attacco e contrattacco si applicano insieme.
- **Penalità di velocità relativa**: −1 per ogni punto oltre 2 (testo normativo), anche se l'esempio della figura 8b del manuale è incoerente.

## Da fare

- Scenari *Nova*, *Retribution*, *The Fleet Mutiny*, *Interplanetary War*, *Prospecting* (economia, acquisti, colonie, basi orbitali).
- Multiplayer online su Firebase come negli altri giochi della ludoteca.
- Basi orbitali come entità mobili.
- Variante "rotta obbligata" del Grand Tour.
