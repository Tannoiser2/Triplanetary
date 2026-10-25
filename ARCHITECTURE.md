# Architettura

## Scelta tecnologica

Godot 4 + GDScript, renderer `gl_compatibility`, con export desktop e futuro Web/HTML5. La plancia usa disegno procedurale in un `Control`; UI e regole rimangono separate. Il motore usa classi `RefCounted` e funzioni deterministiche senza dipendenze dalla scena, così può essere testato headless.

## Moduli

```text
scripts/data/       scenari, tabelle, tipi nave, mappa versionati
scripts/engine/     funzioni pure, geometria, combattimento, RNG, reducer eventi
scripts/ui/         controller hot-seat e plancia procedurale
scenes/             scene Godot sottili, senza logica normativa
tests/              suite headless
```

Flusso: `ScenarioData -> initialState -> Command validation -> DomainEvent[] -> reduce -> GameState -> ViewModel -> Canvas`.

## Coordinate e geometria

Si usano coordinate assiali flat-top `(q,r)`, equivalenti cube `(x=q,z=r,y=-q-r)`. Distanza: `(abs(dx)+abs(dy)+abs(dz))/2`. Posizioni, velocità e accelerazioni sono intere. Il tracciato attraversato viene calcolato con interpolazione cube e arrotondamento deterministico; per bordi ambigui servirà `supercoverHexLine` che restituisca entrambi gli esagoni rilevanti secondo le regole.

La collisione con il disco planetario richiede geometria sub-esagono: ogni corpo avrà centro locale, raggio e lati atterrabili. La conversione dalla plancia deve essere una procedura di calibrazione ripetibile con punti di controllo.

## Gravità differita

Ogni entità mobile conserva `pendingGravity[]`. Durante il movimento t:

1. applica la somma accumulata in t−1;
2. applica spinta valida;
3. fissa velocità e destinazione;
4. enumerare campi attraversati in ordine;
5. memorizzare accelerazioni per t+1.

Le scelte sulle frecce deboli sono parte del comando e del log. Non si ricalcolano retroattivamente.

## Event sourcing e replay

Eventi consigliati: `GameCreated`, `PhaseAdvanced`, `ThrustPlotted`, `WeakGravityChosen`, `OrdnanceLaunched`, `EntityMoved`, `HazardRolled`, `AttackDeclared`, `DieRolled`, `DamageApplied`, `TransferCompleted`, `ShipDetected`, `VictoryDeclared`.

Ogni evento ha `schemaVersion`, indice monotono, turno/segmento/fase, payload e hash del precedente. Snapshot periodici accelerano il caricamento; il log resta la fonte del replay. L'RNG produce risultati solo tramite evento `DieRolled`.

## Modello dati

- `rulesetId`: `updated-second-edition` più opzioni di compatibilità.
- `scenario`: setup, disponibilità basi, limiti ordigni, trigger, vittoria.
- `map`: dimensioni, maschera valida, corpi, campi gravità, asteroidi, basi, zone rilevamento.
- `entity`: nave/ordigno/base con componenti tipizzati.
- `knowledge[player]`: identificazioni e rilevamenti; separato dallo stato fisico.

I dati devono essere validati all'avvio (in futuro Zod o JSON Schema). Nessun testo di scenario o valore tabellare deve vivere nel renderer.

## Salvataggi e compatibilità

JSON con `schemaVersion` e `contentVersion`. Migrazioni pure tra versioni. Salvataggio atomico in `user://` su desktop; su Web Godot usa lo storage persistente del browser. Esportazione include eventi e hash degli input, non asset coperti da diritti.

## Sicurezza e privacy

Applicazione offline, nessun telemetry/network in v1. Il privacy screen riduce visione accidentale ma non protegge il file da un giocatore che lo apre: limite dichiarato.
