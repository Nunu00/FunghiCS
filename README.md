# FunghiCS 🍄 — App iOS Previsione Funghi Professionale ad Alta Risoluzione

**FunghiCS** è un'applicazione iOS nativa (SwiftUI, iOS 17+, SwiftData, MapKit) di livello professionale-scientifico progettata per prevedere la fruttificazione fungina (porcini, galletti e specie eduli) nella **Provincia di Cosenza e Basilicata** (Sila Grande, Sila Greca, Sila Piccola, Massiccio del Pollino, Catena Costiera Paolana e Serre Cosentine).

L'app opera **senza alcun backend a pagamento, senza API key e senza costi di licenza Apple Developer**, sfruttando la compilazione automatizzata su **GitHub Actions** ed il sideloading gratuito su iPhone tramite **SideStore**.

---

## 🌟 Caratteristiche Tecniche e Scientifiche Avanzate

### 🛰️ 1. Copertura Forestale Satellitare Copernicus CLC 2018 ($K_{\text{veg}}$)
- Integrata offline su **109.329 punti di rilevamento** dell'altimetria **INGV TINITALY 10m**.
- Distingue con precisione le faggete, castagneti e pinete di Pino Laricio ($K_{\text{veg}} = 1.00$) da pascoli ($0.05$), pareti di roccia nuda ($0.00$), corpi idrici/laghi della Sila ($0.00$) ed aree urbane/agricole ($0.00$), azzerando i falsi positivi sulle aree non boschive.

### 🌧️ 2. Griglia Meteo Spaziale a 100 Nodi (Risoluzione $2\text{km}$)
- Scarica in **1 singola chiamata HTTP batch** la situazione meteo di **100 nodi montani ad alta densità** nei boschi ($\ge 800\text{m}$).
- Risolve con precisione chirurgica le **celle temporalesche estive localizzate** (dati radar/satellite ICON-D2).

### 🧬 3. Modello ad Incubazione con Curva a Campana di Gauss
- Modello biometrico basato sulla funzione gaussiana $P(t) = P_{\max} \cdot \exp\left(-\frac{(t - \mu)^2}{2\sigma^2}\right)$ con picco di buttata a $\mu = 6,5$ giorni dal temporale.
- **Trama del Suolo SoilGrids ($\sigma_{\text{suolo}}$)**: $\sigma = 1.8$ giorni per i suoli granitico-sabbiosi della Sila (drenaggio rapido) e $\sigma = 3.0$ giorni per i suoli argillosi del Pollino (ritenzione prolungata).

### 💧 4. Umidità dello Strato Miceliare a 3-9 cm & Shock Termico ($\Delta T$)
- **Umidità Suolo 3-9 cm (`soil_moisture_3_to_9cm`)**: Analisi della reale penetrazione dell'acqua fino alle iphe del micelio.
- **Shock Termico ($\Delta T_{\text{suolo}} \ge 3,5^\circ\text{C}$)**: Assegnazione automatica del **+20% di bonus** per drop termici del suolo causati da temporali estivi.
- **Penalizzazione Vento Secco ($K_{\text{vento}}$)**: Riduzione della probabilità in caso di vento forte ($>22\text{ km/h}$) o alta evapotraspirazione ($ET_0$).

### 👆 5. Mappa Interattiva MapKit & Tocco Diretto
- Mappa di calore ad alta definizione con pixel nitidi e non sfumati.
- **Tocco Diretto sulla Mappa**: Toccando un qualsiasi punto della mappa di calore si apre la scheda dettagliata con il meteo live, il tipo di bosco Copernicus ed il terreno per quella coordinata esatta.

---

## 📐 Struttura del Progetto

```
previsioni_funghi/
├── FunghiCS/
│   ├── App/                  (FunghiCSApp.swift)
│   ├── Models/               (PuntoInteresse.swift, DatiMeteo.swift, Osservazione.swift, RisultatoPrevisione.swift)
│   ├── Services/             (DEMService.swift, MeteoService.swift, PrevisioneEngine.swift, NotificheService.swift)
│   ├── Views/                (MappaView.swift, DettaglioPuntoView.swift, ListaPuntiView.swift, HeatmapOverlayRenderer.swift, SplashScreenView.swift)
│   └── Resources/
│       └── cosenza_dem.json  (109.329 punti INGV 10m arricchiti con K_veg Copernicus e SoilGrids)
├── FunghiCSTests/            (PrevisioneEngineTests.swift)
├── scripts/                  (Script Python di verifica ed elaborazione dati GIS/Meteo)
└── .github/workflows/        (ios-build-unsigned.yml - Workflow CI GitHub Actions)
```

---

## 🚀 Come Scaricare l'IPA ed Installare con SideStore

1. **Workflow GitHub Actions**: Ad ogni commit sul ramo `main`, il workflow `.github/workflows/ios-build-unsigned.yml` esegue i test ed effettua la build automatica senza firma.
2. **Download Artifact**:
   - Vai nella scheda **Actions** del repository GitHub: [Nunu00/FunghiCS Actions](https://github.com/Nunu00/FunghiCS/actions).
   - Clicca sull'ultima esecuzione completata con successo.
   - Nella sezione **Artifacts** in fondo alla pagina, scarica l'archivio `FunghiCS-unsigned-ipa`.
3. **Installazione su Device (SideStore / AltStore)**:
   - Decomprimi il file `FunghiCS.ipa`.
   - Apri **SideStore** sul tuo iPhone, premi `+` e seleziona `FunghiCS.ipa` per installarlo gratuitamente sul device.

---

## 🔬 Note di Modellazione Scientifica

- L'algoritmo combina le equazioni di trasporto di massa ed idrologia del suolo con le serie storiche meteorologiche ed altimetriche ufficiali INGV TINITALY 10m.
- Si raccomanda di utilizzare la funzione di registrazione delle osservazioni sul campo per affinare tramite SwiftData i parametri di calibrazione personalizzata del micelio per i propri punti segreti.
