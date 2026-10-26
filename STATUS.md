# Stato del progetto

Aggiornato al 26 ottobre 2026 — riscrittura completa e tutti gli otto scenari giocabili.

## Funziona

- Plancia trascritta e verificata visivamente sovrapponendo i dati alla mappa sorgente (`tools/verify` nel processo di `build_map.py`).
- Tutte le regole di movimento, combattimento, ordigni, pericoli, basi, rifornimento, rilevamento, trasferimenti e resa del manuale.
- Tutti gli otto scenari del manuale, con preparazione, regole speciali e condizioni di vittoria complete.
- Sistemi comuni: acquisto di flotte a punti di forza o in MegaCrediti, schieramento su basi, orbite o spazio libero, basi orbitali, cattura delle basi, soppressione e devastazione dei lati planetari, economia e depositi di ordigni.
- IA per tutti gli scenari e per tutte le parti.
- Hot-seat, schermata di passaggio, salvataggi, export Web.
- Interruttori di visualizzazione ROTTE, DERIVA e RADAR (tasti R, D, V), ricordati fra una sessione e l'altra.
- 95 controlli automatici in `tests/run_tests.gd`, comprese partite complete IA contro IA in tutti gli scenari.

## Scelte interpretative

- **Sol**: la mappa A4 usata ha un doppio anello di frecce attorno al Sole (frecce doppie nell'anello interno, coppie divergenti sui lati dell'anello esterno). È il comportamento predefinito; l'opzione *Sol classico* nel menu ripristina un solo anello come nella plancia GDW originale.
- **Gravità condivisa**: dove due corpi si toccano (Giove/Io) l'esagono applica entrambe le frecce.
- **Grand Tour**: i corpi a gravità piena sono Sol, Mercurio, Venere, Terra, Marte, Giove, Ganimede e Callisto. Le basi senza carburante (Mercurio, Luna, Io, Ganimede, Ceres, Clandestine) offrono comunque il booster. In caso di arrivo nello stesso giorno vince chi ha consumato meno carburante; a parità, ex aequo.
- **Escape**: "oltre Giove" è il bordo destro della plancia. I Pellegrini possono decollare dalla Terra anche se la base è degli Enforcers (il testo dice che possono partire "in qualunque modo").
- **Lateral 7**: Venere ha solo un porto civile (booster per la nave di linea, nessun rifornimento); "raggiunge Ganimede" = attraversa un esagono di gravità di Ganimede. I falsi bersagli entro la portata dei rilevatori nemici vengono smascherati.
- **Contrattacco**: colonna e modificatori sono ricalcolati per il contrattacco; i danni di attacco e contrattacco si applicano insieme.
- **Penalità di velocità relativa**: −1 per ogni punto oltre 2 (testo normativo), anche se l'esempio della figura 8b del manuale è incoerente.
- **Nova**: per impostazione predefinita EastBloc e WestBloc si concedono le basi a vicenda (il manuale lo lascia alla scelta del proprietario); si può disattivare dal menu. L'ordine dei segmenti è tirato a sorte. Se l'ultimo alieno si perde da solo, i due blocchi vincono insieme. Un alieno disabilitato che andrà comunque perso conta come distrutto, con il merito a chi l'ha disabilitato.
- **Retribution**: le corvette non partono da Clandestine (la missione sarebbe già compiuta). La nave assegnata alla Security Patrol è quella Enforcer più vicina alla Terra. "A terra per 12 turni" conta i turni consecutivi.
- **The Fleet Mutiny**: le 12 navi si scelgono liberamente; le basi orbitali vanno in orbita. Solo le navi (non le basi orbitali) sopprimono i lati. Una base si conquista atterrandoci, fermandosi nell'esagono di una base asteroidale o accoppiando la rotta con una base orbitale senza difensori. Al primo turno muovono i ribelli.
- **Interplanetary War**: gli ordigni comprati restano in deposito sul mondo di casa e le navi li caricano in base; le basi orbitali comprate in partita compaiono in orbita attorno al mondo di casa. Mercurio, Ceres e Clandestine non hanno basi attive. La Terra vince appena la flotta ribelle è tutta distrutta.
- **Prospecting**: si parte dalla Luna (a terra) o da Ceres (fermi); il carburante nelle basi costa 1 MCr a punto; l'estrazione a mano dà 0,1 t al giorno a una nave ferma sul filone. Vince chi ha più MegaCrediti allo scadere (60, 120 o 180 giorni).

## Da fare

- Multiplayer online su Firebase come negli altri giochi della ludoteca.
- Variante "rotta obbligata" del Grand Tour e variante a pedine coperte di The Fleet Mutiny.
- IA: il Prospecting automatico è prudente ma non ottimizza il commercio.
