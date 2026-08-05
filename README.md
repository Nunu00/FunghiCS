# FunghiCS 🍄 — App iOS Previsione Funghi Provincia di Cosenza

**FunghiCS** è un'applicazione iOS nativa (SwiftUI, iOS 17+, SwiftData, MapKit) progettata per prevedere la fruttificazione fungina nella provincia di Cosenza (Sila Grande, Sila Piccola, Pollino, Catena Costiera e Serre Cosentine).

L'app opera **senza alcun backend a pagamento, senza API key e senza costi di licenza Apple Developer**, sfruttando la compilazione automatizzata e gratuita su **GitHub Actions (macOS virtual cloud)** ed il sideloading tramite **SideStore**.

---

## 🌟 Caratteristiche principali

- 🗺️ **Mappa Interattiva MapKit**: Visualizza i punti d'interesse salvati con badge di probabilità fruttificazione colorati (Verde = Buttata, Arancione = In preparazione, Giallo = In esaurimento, Grigio = Non favorevole).
- ⛅ **Integrazione Open-Meteo REST API**: Recupera automaticamente precipitazioni cumulate negli ultimi 15 giorni, temperature min/max e umidità del suolo senza bisogno di API key.
- ⛰️ **Altimetria e Morfologia TINITALY (INGV)**: Griglia altimetrica a 10m della provincia di Cosenza inclusa nel bundle (`cosenza_dem.json`) per il calcolo di quota, pendenza ed esposizione del terreno.
- 🧠 **Algoritmo Euristico Avanzato**:
  - Soglia base di precipitazione (default 60 mm / 15 giorni).
  - Riduzione della soglia e ritardo temporale di innesco sopra i 1.000 metri s.l.m.
  - Correzione per evaporazione su versanti Sud (+15% pioggia richiesta).
  - Correzione per dilavamento su pendenze >20° (+15% pioggia richiesta) e ristagno su pianori <5°.
- 🎯 **Calibrazione Automatica su Osservazioni Utente**: Registra le tue uscite sul campo (trovato/non trovato, kg raccolti, specie) per far ricalibrare automaticamente i coefficienti di soglia da SwiftData.
- 🔔 **Notifiche Locali**: Alert automatici quando un punto supera la soglia di probabilità del 70%.

---

## 🛠️ Come Convertire il DEM TINITALY (GeoTIFF -> JSON)

L'app contiene già un file di griglia di esempio `cosenza_dem.json`. Per rigenerarlo partendo dal file GeoTIFF originale TINITALY distribuito dall'INGV:

1. Scarica il riquadro GeoTIFF della Calabria dal sito INGV TINITALY (`tinitaly.pi.ingv.it`).
2. Installa le dipendenze Python:
   ```bash
   pip install rasterio numpy pyproj
   ```
3. Esegui lo script di conversione specificando il file GeoTIFF ed il percorso di destinazione nell'app:
   ```bash
   python scripts/dem_to_json.py path/to/tinitaly_calabria.tif FunghiCS/Resources/DEM/cosenza_dem.json
   ```

---

## 🚀 Come Scaricare l'IPA ed Installare con SideStore

1. **Workflow GitHub Actions**: Ad ogni push sul ramo `main`, il workflow `.github/workflows/ios-build-unsigned.yml` esegue i test ed effettua la build senza firma (`CODE_SIGNING_ALLOWED=NO`).
2. **Download Artifact**:
   - Vai nella scheda **Actions** del repository GitHub.
   - Clicca sull'ultima esecuzione completata con successo.
   - Nella sezione **Artifacts** in fondo alla pagina, scarica l'archivio `FunghiCS-unsigned-ipa.zip`.
3. **Installazione su Device**:
   - Estrai il file `FunghiCS.ipa`.
   - Invialo al tuo iPhone (via AirDrop, Files, o iCloud Drive).
   - Apri **SideStore** sul tuo iPhone, premi `+` e seleziona `FunghiCS.ipa` per firmarlo localmente ed installarlo gratuitamente sul device.

---

## ⚠️ Limiti del Modello e Disclaimer

- L'algoritmo di previsione è un **modello euristico basato su regole fisiche ed empiriche** (microclima, termometria e idrologia del suolo).
- Non garantisce con certezza matematica la presenza di corpi fruttiferi, che dipende anche da fattori microbiologici e di pressione antropica.
- Si raccomanda di utilizzare le osservazioni sul campo nell'app per affinare progressivamente i parametri di sensibilità dei propri punti preferiti.
