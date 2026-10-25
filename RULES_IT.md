# Regole italiane normalizzate

## 0. Autorità delle fonti

Profilo predefinito: **Updated Second Edition**. La scansione `Triplanetary.pdf` presenta lo stesso impianto e consente confronti puntuali. `The Physics of Triplanetary (revised)` è solo commento/variante. Le regole seguenti sono una sintesi tecnica italiana, non una riproduzione impaginata del manuale.

Parole normative: **deve** = obbligo; **può** = scelta; **TODO-RULE** = fonte insufficiente o conflittuale.

## 1. Materiali e unità

Un turno rappresenta un giorno. La mappa è una griglia esagonale del Sistema Solare interno. Una nave ha tipo, forza di combattimento, carburante, stiva, posizione, vettore di velocità, stato di danno, carico e proprietario.

| Tipo | Forza | Carburante | Stiva t | Note |
|---|---:|---:|---:|---|
| Dreadnought | 15 | 15 | 50 | può sparare anche disabilitata |
| Trasporto | 1D | 10 | 50 | commerciale |
| Cisterna | 1D | 50 | 0 | commerciale |
| Liner | 2D | 10 | 50 | commerciale |
| Packet | 1 | 10 | 50 | nave da guerra secondo il suffisso assente |
| Corvette | 2 | 20 | 5 | nave da guerra |
| Corsair | 4 | 20 | 10 | nave da guerra |
| Frigate | 8 | 20 | 40 | nave da guerra |
| Torch | 8 | illimitato | 10 | non trasferisce carburante |
| Base orbitale | 16 | 0 | illimitata | pesa 50 t; solo un trasporto la porta |

Una forza con suffisso `D` è commerciale e non può attaccare né contrattaccare.

## 2. Turno e segmenti

Ogni turno contiene un segmento per giocatore. Nel proprio segmento, il giocatore è “in fase” e svolge:

1. Astrogazione: prevede l'inerzia, applica la gravità maturata e decide la spinta.
2. Ordigni: può lanciare al massimo una mina, un siluro oppure una testata nucleare per nave.
3. Movimento: muove navi e propri ordigni; collisioni ed esplosioni avvengono qui.
4. Combattimento: risolve il fuoco, le contrattacche e i pericoli incontrati.
5. Rifornimento: rifornisce, carica/scarica, saccheggia o soccorre.

## 3. Movimento vettoriale

- Il vettore corrente va dalla posizione iniziale a quella finale del turno precedente.
- Senza accelerazioni, la nave replica lo stesso vettore.
- Una spinta costa 1 carburante e sposta l'estremità prevista di un esagono in una delle sei direzioni.
- Il vettore finale è sempre una linea retta centro-centro e diventa l'inerzia successiva.
- Senza carburante non si accelera, salvo gravità e booster.
- Le navi da guerra possono fare una sola sovraccarica tra due manutenzioni minori: 2 carburante e due accelerazioni di un esagono nello stesso turno. Le commerciali mai.

Formula digitale: `v(t) = v(t-1) + somma(gravitā attraversata in t-1) + spinta(t)`; `pos(t) = pos(t-1) + v(t)`.

### Gravità

- Ogni esagono di gravità piena attraversato produce una accelerazione obbligatoria nella direzione stampata, applicata al turno seguente.
- Gli effetti sono cumulativi.
- Passare tra un esagono di gravità e il bordo del corpo conta come attraversamento; l'effetto si estende al centro dell'esagono planetario adiacente.
- Una prima freccia debole (Luna/Io) può essere ignorata o applicata; entrando consecutivamente in due frecce deboli, la seconda è piena indipendentemente dalla prima.
- `TODO-RULE G-01`: definire geometricamente “consecutivamente” per un tragitto che attraversa più esagoni nello stesso turno e l'effetto del bordo esterno. Il saggio propone varianti che non fanno parte del profilo originale.

### Orbite, atterraggio, decollo

- È in orbita stabile una nave che, senza spinta, passa a velocità 1 da un esagono gravitazionale al successivo adiacente dello stesso corpo.
- Si atterra solo da orbita, spendendo 1 carburante, sul lato del corpo che contiene una base.
- Il decollo richiede una base amica: il booster porta nell'esagono gravitazionale sopra la base senza costo; la gravità superficiale annulla la velocità e la nave risulta ferma. Se al turno successivo non spende carburante, ricade e si distrugge.
- Ceres e Clandestine: atterraggio fermandosi nell'esagono; decollo accelerando fuori.
- `TODO-RULE L-01`: il manuale Updated Second Edition consente, dopo il decollo, di entrare in orbita “o manovrare altrimenti”; prima e terza edizione, secondo McCue, sono più restrittive. Profilo originale scelto: consentire qualsiasi singola spinta legale al turno successivo.

### Collisioni e uscita

Intersecare graficamente il disco di un corpo distrugge la nave, salvo atterraggio legale. Uscire con la posizione finale dalla mappa elimina la nave. Più navi possono condividere un esagono. Un giocatore in fase può tentare un solo speronamento per nave se la rotta attraversa il centro dell'esagono bersaglio; si tira sulla colonna `Ram` e il risultato si applica a entrambe.

## 4. Combattimento

### Fuoco

1. Sommare la forza degli attaccanti e dei difensori scelti.
2. Ridurre il rapporto alla colonna disponibile, sempre a favore del difensore: meno di 1:2 nessun effetto; oltre 4:1 usa 4:1.
3. Tirare 1d6.
4. Sottrarre la distanza: minima distanza tra la traiettoria dell'attaccante e la posizione finale del difensore; in attacchi multipli usare il valore peggiore.
5. Sottrarre `max(0, velocità_relativa - 2)`, dove la velocità relativa è la distanza esagonale tra le estremità dei due vettori traslati alla stessa origine; in attacchi multipli usare il valore peggiore.
6. Aggiungere +1 se l'attaccante è eroico. Limitare il risultato modificato a 1..6, con valori sotto 1 = nessun effetto.

Ogni nave attacca al massimo una volta e viene attaccata al massimo una volta per fase. Solo il giocatore in fase inizia. Le navi attaccate possono contrattaccare prima di applicare i danni; unità che condividono la rotta della vittima possono partecipare.

`TODO-RULE C-01`: il testo normativo impone penalità a velocità relativa 3, ma l'Updated Second Edition mostra “Distance: 3” e afferma nessun modificatore; la scansione precedente mostra distanza 2. Implementazione scelta: formula normativa, quindi −1 a 3.

### Tabella danni

| d6 | 1:2 | 1:1 | 2:1 | 3:1 | 4:1 | Siluro | Mina | Speronamento | Asteroidi |
|---:|---|---|---|---|---|---|---|---|---|
| 1 | - | - | - | - | D2 | - | - | - | - |
| 2 | - | - | - | D2 | D3 | D5 | - | - | - |
| 3 | - | - | D2 | D3 | D4 | E | - | - | - |
| 4 | - | D2 | D3 | D4 | D5 | E | D1 | - | - |
| 5 | D2 | D3 | D4 | D5 | E | E | D2 | D2 | D1 |
| 6 | D3 | D4 | D5 | E | E | E | D3 | D2 | D2 |

`Dn`: nessuna manovra, lancio o attacco per n turni; solo deriva. Recupero alla fine della stessa fase in cui fu inflitto. Il dreadnought può comunque sparare. I danni si sommano; se la disabilitazione raggiunge 6 o più turni futuri, la nave è distrutta. `E`: eliminata.

## 5. Ordigni

- Mina: 10 t, qualunque nave con stiva; eredita il vettore, nessuna spinta, dura 5 turni. Il lanciatore deve cambiare immediatamente rotta. Esplode se la sua rotta e quella di una nave coinvolgono l'esagono della punta della mina; ogni nave colpita tira separatamente. Immune a cannoni e difese.
- Siluro: 20 t, solo navi da guerra; eredita il vettore e solo al lancio può accelerare di 1 o 2 esagoni; poi mantiene il vettore, dura 5 turni. In un esagono con più navi, si tira in sequenza finché una è disabilitata/distrutta o tutte sono risultate indenni. Immune a cannoni e difese.
- Nuke: 20 t; una commerciale ne porta al massimo una. Eredita il vettore; il lanciatore deve cambiare rotta; dura 5 turni. Distrugge automaticamente tutto nell'esagono (navi, basi, asteroide), o devasta un lato planetario. Mine e siluri la trattano come nave. Cannoni e difese la attaccano sempre a 2:1 con normali modificatori. Una nuke disabilitata non funziona.

`TODO-RULE O-01`: il testo generale dice che gli ordigni detonano incontrando anche altri ordigni, mentre il paragrafo nuke esclude mine/siluri/nuke dai trigger diretti e poi dice che mine/siluri trattano le nuke come navi. Modellare per matrice di collisione e testare ogni coppia; non uniformare.

## 6. Pericoli

Per ogni esagono di asteroidi entrato a velocità >1, tirare sulla colonna Asteroidi. Viaggiare sul lato condiviso tra due esagoni asteroidali conta come ingresso in uno. Gli asteroidi speciali attorno a Clandestine distruggono gli intrusi senza diritto di accesso; mine/siluri detonano senza colpire l'interno, le nuke rendono libero l'esagono.

## 7. Basi, rifornimenti e rilevamento

- Le basi planetarie offrono difesa, carburante, manutenzione, booster e rilevamento. Una nave atterrata è immune a fuoco, mine, siluri e speronamento, non alle nuke; non spara né lancia.
- Ceres/Clandestine non hanno difese e lanciano un siluro per turno.
- Le basi orbitali forniscono rifornimenti; in orbita possono lanciare un siluro per turno se non riforniscono. Una volta piazzate non si recuperano.
- Rifornire richiede rotta/posizione coincidente secondo il tipo di base, riempie carburante, ripristina la sovraccarica e consente una combinazione di mine/siluri entro la stiva. La nave e la base coinvolta non sparano/lanciano nel segmento.
- Difesa planetaria: attacca tutte le navi nemiche direttamente sopra quel lato a 2:1, senza modificatori di distanza/velocità.
- Rilevatori nave 3 esagoni; basi 5. Una volta scoperta, una nave resta scoperta finché raggiunge una base amica.

## 8. Trasferimenti, cargo e resa

Trasferire richiede stessa posizione e stesso vettore. Il saccheggio è consentito contro navi disabilitate o arrese. Il soccorso trasferisce equipaggio/carburante. Una nave disabilitata saccheggiata può essere catturata ma deve tornare a una base amica prima dell'uso; una nave arresa non può essere catturata e deve conservare carburante sufficiente per raggiungere una propria base. Il Terran Space Patrol non si arrende.

La massa totale non supera la stiva; un oggetto non si divide tra navi. Solo un trasporto porta una base orbitale. Scanners, PM grapples, miniere automatiche, robot guards, ore e CT shard si usano negli scenari che li richiedono.

## 9. Eroismo, salvataggi e vittoria

Una nave che attacca sotto 1:1 e ottiene D2 o più diventa eroica, una sola volta, e ottiene +1 agli attacchi futuri. Lo stato completo deve essere salvabile tra fasi; ogni scelta e tiro entra nel log/replay. Le condizioni di vittoria sono dati dello scenario, non logica cablata nel motore.
