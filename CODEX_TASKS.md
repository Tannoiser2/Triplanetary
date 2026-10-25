# Backlog eseguibile per Codex

Regola generale per ogni task: leggere `RULES_IT.md`; non risolvere `TODO-RULE` senza una decision record; aggiungere test prima/durante l'implementazione; dati fuori dal renderer; non importare gli allegati nel repository.

## P0 - Fondazioni e Grand Tour

### T01 - Schema e validazione dati

Creare `scripts/data/schema.gd` e file JSON/Resource per tipi nave, tabella danni, mappa e scenari. Validare ID univoci, coordinate intere, direzioni adiacenti, riferimenti esistenti, capienze non negative. Spostare la tabella hard-coded da `combat.gd`. Done: dati invalidi producono errori leggibili e test.

### T02 - Supercover e gravità

Implementare `supercoverHexLine` con tie deterministico; includere campi attraversati sui bordi secondo le regole. Implementare gravità debole e due campi consecutivi. Done: fixture originali equivalenti alle figure 6/7, inclusi più campi nello stesso movimento.

### T03 - Mappa canonica

Usare la copia locale della mappa solo come reference; calibrare e trascrivere coordinate/campi/basi/asteroidi. Produrre `map.updated-second.json`, rapporto di controllo e test coordinate→pixel. Non includere l'immagine. Done: seconda revisione documentata, zero `TODO-DATA` per Grand Tour.

### T04 - Orbite e superficie

Componenti `OrbitState`/`LandedState`, rilevamento orbita, atterraggio e decollo, ricaduta, Ceres/Clandestine. Opzione compatibilità L-01. Done: sei orientamenti e salvataggio a ogni transizione.

### T05 - UI astrogazione hot-seat

Estrarre renderer/controller da `main.ts`; pan/zoom, hit test, previsione a strati, conferma ordini per tutte le navi, privacy screen. Done: tastiera e mouse, viewport mobile leggibile.

### T06 - Vittoria Grand Tour

Visit tracker sui campi full gravity, rifornimento alle quattro basi, ritorno/atterraggio Terra, tie fuel/ex aequo. Done: partita automatizzata completa e log della classifica.

### T07 - Salvataggio e replay

Reducer eventi, RNG solo a eventi, IndexedDB, export/import JSON, hash chain, migrazione v1. Done: replay deterministic test e corruzione rilevata.

## P1 - Combattimento completo

### T08 - Attacchi e contrattacchi

Planner gruppi, limiti per fase, range minimo, velocità relativa, rapporto, eroismo, applicazione simultanea della contrattacca. Opzione C-01 fissata al profilo normativo. Done: matrice tabella completa.

### T09 - Danni e pericoli

Timer legati alla fase, cumulo, eccezione dreadnought, asteroidi e speronamenti. Done: recovery esatto dopo n ricorrenze della fase d'origine.

### T10 - Ordigni

Entità mine/siluri/nuke, durata, carico/lancio, matrice collisione O-01, ordine bersagli e interazioni asteroidi/corpi. Done: ogni coppia entità testata.

## P2 - Logistica e fog of war

### T11 - Basi e rifornimento

Tre tipi base, matching, difese, booster, manutenzione, munizioni e blocchi fire/resupply.

### T12 - Cargo/trasferimenti

Inventario mass-based, rescue, looting, surrender, capture, restrizioni base orbitale/nuke.

### T13 - Detection e identità

Knowledge state per giocatore, range/persistenza, dummy/identità segrete, privacy screen robusta.

## P3 - Scenari successivi

Ordine suggerito: Escape (pochi sistemi nuovi), Lateral 7 (detection/dummy/cargo), Nova (3 giocatori e acquisti punti), Retribution, Fleet Mutiny, Interplanetary War (economia), Prospecting (economia aleatoria e claim).

## Prompt operativo consigliato

> Implementa il task Txx in questo progetto Godot 4. Prima leggi README.md, RULES_IT.md, SPEC.md, ARCHITECTURE.md e TEST_PLAN.md. Mantieni il motore puro e deterministico, sposta i dati fuori dai nodi UI, aggiungi test headless e aggiorna i documenti se scopri un conflitto. Non usare o copiare gli asset sorgente. Esegui `godot --headless --path . --script tests/run_tests.gd` e un avvio headless della scena, poi riporta file cambiati, test e TODO residui.
