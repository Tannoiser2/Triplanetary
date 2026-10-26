# Manifesto asset e provenienza

## Politica

Gli allegati sono fonti di riferimento fornite dall'utente. Non vengono copiati in questo repository. Ogni integrazione grafica futura deve richiedere conferma dei diritti e conservare autore/licenza/URL/hash. La build pubblica deve funzionare con asset originali o autorizzati.

| File sorgente | SHA-256 | Uso effettuato | Stato diritti / azione |
|---|---|---|---|
| `triplanetary-manual.pdf` | `d6d06a6e5945ac21297bea2a31eb2758f7976beaddafff7d4a3757ea15c01b85` | fonte primaria, 16 pp, Updated Second Edition | © 1973, 1981 GDW dichiarato nel PDF; non ridistribuire senza permesso |
| `Triplanetary.pdf` | `c2ba251aab9d7265f499bcfa6e347e3afa026327d381980923483b223e21ad97` | scansione 9 pp, confronto | copyright dichiarato 1973/1981; non ridistribuire |
| `The_physics_of_triplanetary_(revised).pdf` | `03104a1f7af91d5c9d946cde90518fefcf64a83476f38fe002b5e92a78dd519f` | analisi/varianti, non normativa | autore indicato Brian McCue; licenza non presente; non ridistribuire |
| `tplan2018.pdf` | `18eb5fd05320f9240e4720356988c218d7f61cc1d2fffda515aa1c4975946b93` | ispezione pedine, 1 p | licenza non presente; non incluso |
| `Triplanetary_map_A4_starkiel_v1.jpg` | `402df6f12899a2e3c4d296e912324c7537202d543a857e0400c065229be07320` | riferimento mappa 1447×2048 | autore suggerito dal nome, licenza assente; non incluso |
| `Triplanetary (3384549662).ttsmod` | `15d449d427cea10fba72901d693ca7c512c389db67dcd094d27fe40dabcd42bc` | ispezione struttura TTS | provenienza Workshop ID 3384549662; verificare autore/licenza sulla pagina originale prima dell'uso |
| `pic4172329.jpg.webp` | `ba023f3956bf5377a4e6a96f5345972d65bfd495c5272e9c14e6695d27bb413e` | copertina nel menu e nella Ludoteca, inserita su richiesta esplicita dell'utente | immagine storica GDW fornita dall'utente; diritti dell'opera ai rispettivi autori/editori, uso non ufficiale e personale |

## Risultato ispezione TTS

Archivio ZIP valido con 2 Unity assetbundle, 6 immagini PNG, anteprima e `Mods/Workshop/3384549662.json`. Il JSON è troncato alla riga 1279 dentro il valore `LuaScript` dell'oggetto “Military”; non è quindi parsabile come salvataggio completo. Le risorse binarie possono contenere materiale di terzi e non sono state integrate. `TODO-ASSET TTS-01`: ottenere una esportazione integra o il workshop originale e verificarne licenza e attribution.

## Pipeline mappa proposta

1. Correggere orientamento e prospettiva solo su copia di lavoro.
2. Calibrare griglia con almeno tre centri esagonali distanti.
3. Trascrivere maschera bordo, corpi, dischi sub-hex, campi gravità/direzioni, basi, asteroidi e aree detector in un file dati originale.
4. Doppia revisione visiva indipendente e test di round-trip coordinate→pixel.
5. Conservare l'immagine solo come riferimento locale escluso da Git; distribuire la trascrizione solo dopo verifica legale che i dati possano essere usati.

## Asset sostitutivi

Per una release pubblica: griglia e simboli procedurali, silhouettes originali, nomi/testi solo quanto autorizzato, font con licenza compatibile, nessuna scansione o texture Workshop incorporata.

La precedente copertina sostitutiva resta disponibile come `assets/ui/menu-cover.svg`; la copertina richiesta dall'utente è conservata senza alterazioni sostanziali in `assets/ui/original-cover.webp` e `ludoteca/copertina.webp`.
