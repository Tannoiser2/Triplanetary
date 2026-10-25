# Scenari

## Registro fonti e disponibilità

| Scenario | Giocatori | Durata | Stato dati |
|---|---:|---|---|
| Grand Tour (2037) | multi | non indicata | primo MVP; regole complete, coordinate da verificare |
| Escape | 2 | breve | trascritto in specifica |
| Lateral 7 | 2 | breve | trascritto in specifica |
| Nova | 3 | breve | trascritto in specifica |
| Retribution | 2 | breve | trascritto in specifica |
| The Fleet Mutiny | 2 | breve | trascritto in specifica |
| Interplanetary War | 2 | lunga | trascritto in specifica |
| Prospecting | multi | lunga | trascritto in specifica |

## Grand Tour - implementazione MVP

Setup: una corvetta per giocatore, su Terra. Rifornimento gratuito solo a Terra, Venere, Marte e Callisto. Combattimento consentito. Obiettivo: attraversare almeno un campo di gravità piena di ogni corpo che ne possiede e poi atterrare su Terra. Vince il primo; stesso tempo → minor carburante consumato; ulteriore parità → ex aequo (`TODO-RULE GT-01`).

Variante route constraint: il manuale propone ordine alfabetico, dimensione o distanza da Sol; il criterio viene scelto prima della gara. `TODO-DATA`: l'elenco esatto dei corpi di piena gravità deve derivare dalla mappa canonica verificata, non dai nomi presenti nel solo testo.

Schema dati previsto:

```json
{
  "id": "grand-tour-2037",
  "players": { "min": 2 },
  "fleet": [{ "perPlayer": true, "type": "corvette", "location": "terra" }],
  "freeFuelAt": ["terra", "venus", "mars", "callisto"],
  "combat": true,
  "objectives": [{ "type": "visitAll", "selector": "body.fullGravity" }, { "type": "land", "body": "terra" }]
}
```

## Altri scenari - dati essenziali

### Escape

Pilgrims: 3 trasporti su Terra, uno segreto con fuggitivi. Enforcers: corvetta in orbita Terra, corsair in orbita Venere. Niente mine/siluri; Pilgrims possono speronare; basi solo Terra/Venere/Io, tutte Enforcer, difese spente. Nessun limite. Livelli vittoria dipendono da uscita oltre Giove e carburante per fermarsi +1, cattura/distruzione. `TODO-RULE`: formalizzare “oltre Giove” sulla geometria del bordo.

### Lateral 7

Pirates: 2 corsair, 1 corvette, 9 dummy; Navy: dreadnought, 3 dummy, liner. Posizionamento Belt, velocità zero; liner su Venere. Clandestine pirata e special asteroids accessibili; corsair con una mina. Navy basi Marte/Terra/Callisto; dreadnought con mina+siluro e immobile fino a rilevamento pirata. Vittoria tramite passeggeri a Clandestine o liner a Ganimede.

### Nova

Tre giocatori. EastBloc/WestBloc 50 punti forza ciascuno, colonie determinate come da tabella d6 (Venere, Marte, Ceres, Callisto, Clandestine, Mercurio). Aliens: 4 corsair dal bordo Giove a velocità 1, pieno carico mine e Nova bombs senza massa; una nave in orbita attorno a Sol attiva la distruzione. `TODO-RULE`: “pieno carico mine” per corsair da 10 t equivale plausibilmente a una mina, ma registrare come dato esplicito.

### Retribution

Enforcers: 2 corsair in orbita di pianeti distinti, 1 frigate a Luna. Sons of Liberty: 10 corvette in successione da basi diverse da Luna/Ceres/Terra; missione Clandestine o schianto su Terra. Conversione corvette giunte a Clandestine in flotta per il doppio dei punti; Torch ammessa. Vittoria come testo, inclusa inattività a terra per 12 turni.

### The Fleet Mutiny

Empire: 12 navi + 2 basi orbitali disperse a distanza ≥3. Rebel designa 5 unità e tira: con 6 non si ribellano. Basi imperiali, difese spente, basi catturabili. Soppressione automatica di lati planetari da orbita al costo del fuoco. Vittoria basata sui lati di Terra soppressi.

### Interplanetary War

Terran 1600 MCr; Rebels 1000 MCr. Setup e mondi come manuale. Acquisti navi/ordigni/nuke, produzione 0,1 MCr per base per turno. Rebels spendono liberamente; Terran devono trasportare MCr su Terra con commerciali, 1 MCr = 1 t. Vittoria per flotta distrutta/devastazione lati Terra/Luna.

### Prospecting

Ogni giocatore 25 MCr e compra anche il carburante. Prospezione a velocità 1: primo d6, con 6 c'è minerale; secondo d6, con 1 c'è CT shard. Senza PM grapples: D4 ed elimina shard. Ogni esagono una volta. Minerale venduto Ceres/Luna con prezzo d6 (Ceres −2, minimo 1); shard 100/300 MCr. Durata concordata, esempio 120 giorni. Vince il più ricco.
