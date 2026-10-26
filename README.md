# Triplanetary Digital - pacchetto di sviluppo

Prototipo locale e specifiche italiane per una versione digitale fedele all'**Updated Second Edition** di *Triplanetary*. Il repository separa regole, dati, simulazione e rendering; non contiene copie degli asset allegati né materiale grafico proprietario.

## Stato

- Motore GDScript: coordinate esagonali assiali, inerzia, spinta, carburante, gravità piena e debole differita, sovraccarico, decollo/atterraggio, collisioni e tabella di combattimento.
- Prototipo Godot hot-seat multigiocatore con sequenza di fasi, rendering procedurale e registro eventi.
- Menu iniziale nella palette della copertina, scenari a schede descrittive, sei posti equipaggio configurabili, guida integrata, plancia con zoom/scorrimento, vettore e spinta distinti, e traccia curva permanente dei movimenti.
- Scenari giocabili: Grand Tour ed Escape; Escape include identità segreta, scelta del bersaglio, ispezione/cattura, speronamento e livelli di vittoria.
- Scenario `Grand Tour` giocabile sulla **development map**, con partenza atterrata, visite, rifornimento, ritorno e vittoria. La trascrizione completa della plancia deve ancora essere verificata.
- Salvataggio/caricamento locale, autosave, replay a fotogrammi e scambio di salvataggi JSON dagli appunti. Sono operativi combattimento 1v1, contrattacco, danni, ordigni vettoriali, asteroidi, rilevamento, privacy hot-seat, basi planetarie e regole di carico/trasferimento. Attacchi combinati, interfaccia logistica completa e i sette scenari successivi restano nel backlog e non vengono presentati come giocabili.
- Lo stato preciso, senza sovrastimare la completezza, è in `STATUS.md`.

## Avvio

Richiede Godot 4.3 o successivo.

Aprire `project.godot` nell'editor e premere **F6/F5**, oppure:

Build di produzione:

```bash
godot --path . --editor
godot --headless --path . --script tests/run_tests.gd
```

L'export browser usa il preset `Web`, single-threaded per essere compatibile con GitHub Pages:

```bash
godot --headless --path . --export-release Web docs/index.html
```

La workflow `.github/workflows/pages.yml` pubblica la cartella `docs/` a ogni push su `main`. La cartella `ludoteca/` espone una scheda autonoma alla [Ludoteca Virtuale](https://tannoiser2.github.io/) e contiene solo grafica originale del progetto.

## Ordine di lettura per Codex

1. `RULES_IT.md`: regole normalizzate e questioni aperte.
2. `SPEC.md`: comportamento verificabile del gioco digitale.
3. `ARCHITECTURE.md`: confini del motore e modello degli eventi.
4. `SCENARIOS.md`: dati e condizioni degli scenari.
5. `ASSET_MANIFEST.md`: provenienza, diritti e trattamento degli allegati.
6. `TEST_PLAN.md`: matrice di verifica.
7. `CODEX_TASKS.md`: istruzioni eseguibili e backlog incrementale.

## Principi di fedeltà

- La fonte normativa primaria è il manuale “Updated Second Edition”, copyright 1973/1981 GDW.
- La scansione storica viene usata per confronto; il saggio di Brian McCue è analisi, non regola.
- Una contraddizione non viene silenziosamente corretta: viene marcata `TODO-RULE` e coperta da un'opzione di compatibilità quando necessario.
- Dadi e scelte sono eventi registrati; lo stesso seed e lo stesso flusso di comandi producono lo stesso replay.

## Diritti

Il codice e i documenti di progetto qui creati non concedono diritti sul gioco o sugli asset originali. Prima di distribuire una build pubblica occorre ottenere l'autorizzazione del titolare dei diritti o sostituire mappa, pedine, testo e marchi con contenuti originali autorizzati. Vedere `ASSET_MANIFEST.md`.
