# Prompt/Istruzioni per Google Antigravity — App iOS Previsione Funghi (Cosenza) — Versione Finale

Compilazione 100% su GitHub Actions (Mac virtuale cloud), nessun Mac fisico, nessun account Apple Developer, nessuna spesa. Installazione sul device tramite SideStore (già configurato dall'utente).

---

## 0. Obiettivo del progetto

App SwiftUI **"FunghiCS"** per la provincia di Cosenza (bounding box: lat 39.05–40.15 N, lon 15.75–16.85 E — includendo Sila, Pollino, Catena Costiera, Serre Cosentine). Mostra una mappa MapKit con overlay colorato di probabilità di fruttificazione fungina nei punti salvati dall'utente, calcolata combinando dati meteo (pioggia/temperatura) con dati altimetrici locali (quota, pendenza, esposizione), calibrabile nel tempo con osservazioni personali sul campo. Notifiche locali quando un punto supera la soglia. Nessun backend server, nessun servizio a pagamento.

---

## 1. Stack tecnico

Swift 5.10+, SwiftUI, target iOS 17+, MapKit, SwiftData per persistenza (punti salvati e osservazioni), `URLSession` async/await per il fetch meteo, `UserNotifications` per gli alert locali, `BGAppRefreshTask` per il refresh periodico in background. Nessuna dipendenza di terze parti: tutto su framework di sistema Apple, per evitare complicazioni nella risoluzione dei package su CI.

---

## 2. Fonti dati gratuite

### 2.1 Meteo — Open-Meteo API
- Forecast + storico recente: `https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&daily=precipitation_sum,temperature_2m_max,temperature_2m_min&hourly=relative_humidity_2m,soil_moisture_0_to_1cm&past_days=16&forecast_days=7&timezone=Europe/Rome`. Gratuita, senza API key, fino a 10.000 chiamate/giorno per uso non commerciale.
- Storico lungo per calibrazione stagionale: endpoint `/v1/archive` (reanalysis dal 1940), da usare una volta per validare le soglie sui punti di Sila/Pollino/Catena Costiera.

### 2.2 Altimetria — TINITALY DEM (INGV)
DEM a risoluzione 10 metri per tutto il territorio italiano, gratuito su tinitaly.pi.ingv.it, il più preciso disponibile per l'Italia (molto meglio dei DEM globali SRTM/Copernicus a 30m). Formato GeoTIFF, UTM WGS84 zona 32N. Conversione offline con script Python (`rasterio` + `numpy`) in un file statico `cosenza_dem.json` incluso come risorsa nel bundle dell'app (griglia quota/pendenza/esposizione ritagliata sul bounding box di Cosenza).

### 2.3 Calibrazione storica — ARPACAL
Bollettini e serie storiche di pioggia per stazione in Calabria (arpacal.it), riferimento manuale per validazione, non richiede integrazione via codice.

---

## 3. Algoritmo di previsione

Implementa in Swift una funzione pura `calcolaProbabilitaFruttificazione(punto: PuntoInteresse, meteo: DatiMeteo) -> RisultatoPrevisione`:

1. **Soglia base**: 40–100 mm di pioggia cumulata negli ultimi 10–15 giorni (default 60 mm, configurabile).
2. **Correzione quota**: sopra 1.000 m, ritardo stagionale di innesco di 2-3 settimane e soglia pioggia -10%.
3. **Correzione esposizione**: versanti sud +15% soglia pioggia (maggiore evaporazione); nord base; est/ovest neutri.
4. **Correzione pendenza**: pendenza >20° soglia +10-20%; pendenza <5° soglia -5%.
5. **Stati temporali**: non favorevole / in preparazione (0-3gg dal superamento soglia) / buttata probabile (4-10gg) / in esaurimento (11-15gg).
6. **Calibrazione utente**: ogni osservazione salvata (trovato/non trovato, data, punto) modifica i moltiplicatori di soglia per quel punto specifico, persistiti in SwiftData.

Documenta nel codice che è un modello euristico basato su regole empiriche, da affinare con l'esperienza reale sul campo.

---

## 4. Struttura del repository

```
FunghiCS/
├── FunghiCS.xcodeproj
├── FunghiCS/
│   ├── App/
│   ├── Models/            (PuntoInteresse.swift, DatiMeteo.swift, Osservazione.swift, RisultatoPrevisione.swift)
│   ├── Services/           (MeteoService.swift, DEMService.swift, PrevisioneEngine.swift, NotificheService.swift)
│   ├── Views/              (MappaView.swift, DettaglioPuntoView.swift, ListaPuntiView.swift, AggiungiOsservazioneView.swift)
│   └── Resources/DEM/cosenza_dem.json
├── FunghiCSTests/
├── scripts/dem_to_json.py
├── .github/workflows/ios-build-unsigned.yml
└── README.md
```

---

## 5. Workflow GitHub Actions (Mac virtuale cloud, build senza firma)

Crea `.github/workflows/ios-build-unsigned.yml`:

```yaml
name: Build Unsigned IPA
on:
  push:
    branches: [main]
  workflow_dispatch: {}

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode version
        run: sudo xcode-select -s /Applications/Xcode.app

      - name: Resolve Swift Package dependencies
        run: xcodebuild -resolvePackageDependencies -project FunghiCS.xcodeproj -scheme FunghiCS

      - name: Run unit tests
        run: |
          xcodebuild test \
            -project FunghiCS.xcodeproj -scheme FunghiCS \
            -destination "platform=iOS Simulator,name=iPhone 15"

      - name: Archive without signing
        run: |
          xcodebuild archive \
            -project FunghiCS.xcodeproj -scheme FunghiCS \
            -configuration Release \
            -archivePath $PWD/build/FunghiCS.xcarchive \
            -sdk iphoneos \
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

      - name: Package unsigned IPA
        run: |
          cd build/FunghiCS.xcarchive/Products/Applications
          mkdir Payload
          mv FunghiCS.app Payload/
          zip -r ../../../FunghiCS.ipa Payload

      - name: Upload IPA artifact
        uses: actions/upload-artifact@v4
        with:
          name: FunghiCS-unsigned-ipa
          path: build/FunghiCS.ipa
          retention-days: 90
```

Note per l'agente:
- `-sdk iphoneos` (non simulator) nello step archive, per generare un binario compatibile con device reali.
- I test girano sul simulatore prima dell'archive, per non produrre pacchetti con errori logici.
- Nessun secret, certificato o chiave richiesta in nessuno step: il flusso resta gratuito al 100%.

---

## 6. Installazione sul device

L'utente installa il file `FunghiCS.ipa` scaricato dagli Artifacts del workflow tramite **SideStore**, già configurato sul proprio iPhone — nessuna istruzione aggiuntiva necessaria in questa fase.

---

## 7. Istruzioni comportamentali per l'agente Antigravity

- Costruisci in modo incrementale: scheletro progetto → modelli → servizi → viste → test → workflow.
- Verifica sempre che `xcodebuild build` funzioni prima di ogni commit.
- Non introdurre dipendenze SPM di terze parti non necessarie.
- Non generare mai step di firma, certificati, provisioning profile a pagamento o export per TestFlight: sono esplicitamente esclusi da questo progetto.
- Nel `README.md`, documenta: (1) come scaricare/convertire il DEM TINITALY con lo script Python, (2) come recuperare l'`.ipa` dagli Artifacts del workflow, (3) i limiti noti del modello previsionale euristico.
- Genera `scripts/dem_to_json.py` con `rasterio` + `numpy`: legge il GeoTIFF TINITALY, calcola pendenza ed esposizione con `numpy.gradient`, ritaglia sul bounding box di Cosenza, esporta il JSON a risoluzione ~10-30m.

---

## 8. Criteri di completamento

- [ ] L'app compila e gira sul simulatore iOS mostrando la mappa centrata su Cosenza.
- [ ] Aggiunta punti di interesse funzionante toccando la mappa.
- [ ] `PrevisioneEngine` calcola correttamente lo stato colorato usando dati Open-Meteo reali + DEM TINITALY statico.
- [ ] Unit test coprono almeno 5 casi (quota alta/bassa, esposizione nord/sud, pendenza alta/bassa).
- [ ] Workflow `ios-build-unsigned.yml` verde su ogni push, produce artifact `.ipa` scaricabile senza alcun riferimento a certificati o secrets.
- [ ] `.ipa` installato con successo tramite SideStore e funzionante su device reale (mappa, previsioni, notifiche locali).
- [ ] README completo con istruzioni per conversione DEM e recupero build dagli Artifacts.
