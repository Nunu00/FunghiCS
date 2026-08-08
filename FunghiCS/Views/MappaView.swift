import SwiftUI
import MapKit
import SwiftData
import UIKit

struct MappaView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var punti: [PuntoInteresse]
    
    // Mappa di calore e filtro quota permanentemente attivi
    private let mostraMappaDiCalore = true
    private let filtraSoloZoneIdonee = true
    
    @State private var tipoMappa: TipoMappaOverlay = .fruttificazione
    
    @State private var puntoSelezionato: PuntoInteresse? = nil
    @State private var mostrandoFormNuovoPunto = false
    @State private var nomeNuovoPunto = ""
    @State private var latNuovoPunto = "39.33"
    @State private var lonNuovoPunto = "16.44"
    
    @State private var mostrandoCSVExport = false
    @State private var testoCSVGenerato = ""
    @State private var messaggioNotifica = ""
    @State private var mostraNotificaCopiato = false
    
    @State private var risultatiMeteoPunti: [UUID: RisultatoPrevisione] = [:]
    
    var body: some View {
        NavigationStack {
            ZStack {
                // MapKit nativo tramite UIViewRepresentable per rendering ultra-fluido e tocchi diretti sulla mappa
                MapViewRepresentable(
                    punti: punti,
                    risultatiMeteoPunti: risultatiMeteoPunti,
                    mostraMappaDiCalore: mostraMappaDiCalore,
                    filtraSoloZoneIdonee: filtraSoloZoneIdonee,
                    onSelectPunto: { punto in
                        self.puntoSelezionato = punto
                    }
                )
                .ignoresSafeArea(edges: [.bottom, .horizontal])
                
                // Selettore della Modalità Mappa e Legenda Dinamica
                VStack {
                    // Segmented Control Trasparente in alto
                    Picker("Tipo Mappa", selection: $tipoMappa) {
                        Text("🍄 Fruttificazione").tag(TipoMappaOverlay.fruttificazione)
                        Text("🌧️ Pioggia 15gg").tag(TipoMappaOverlay.precipitazioni)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .onChange(of: tipoMappa) { _, nuovoTipo in
                        CosenzaHeatmapOverlayRenderer.tipoMappaCorrente = nuovoTipo
                        NotificationCenter.default.post(name: .heatmapDataUpdated, object: nil)
                    }
                    
                    HStack {
                        Spacer()
                        
                        // Legenda Dinamica in base al tipo di mappa selezionato
                        VStack(alignment: .leading, spacing: 4) {
                            if tipoMappa == .fruttificazione {
                                Text("Legenda Fruttificazione")
                                    .font(.caption2)
                                    .bold()
                                HStack { Circle().fill(Color.green).frame(width: 8, height: 8); Text("Buttata (>65%)").font(.caption2) }
                                HStack { Circle().fill(Color.orange).frame(width: 8, height: 8); Text("Preparazione (48-64%)").font(.caption2) }
                                HStack { Circle().fill(Color.yellow).frame(width: 8, height: 8); Text("Esaurimento (30-47%)").font(.caption2) }
                                HStack { Circle().fill(Color.gray).frame(width: 8, height: 8); Text("Non fav. (<30%)").font(.caption2) }
                            } else {
                                Text("Legenda Pioggia 15gg")
                                    .font(.caption2)
                                    .bold()
                                HStack { Circle().fill(Color.blue).frame(width: 8, height: 8); Text("Abbondante (≥70mm)").font(.caption2) }
                                HStack { Circle().fill(Color.cyan).frame(width: 8, height: 8); Text("Ottima (45-69mm)").font(.caption2) }
                                HStack { Circle().fill(Color.teal).frame(width: 8, height: 8); Text("Moderata (25-44mm)").font(.caption2) }
                                HStack { Circle().fill(Color.yellow).frame(width: 8, height: 8); Text("Scarsa (10-24mm)").font(.caption2) }
                                HStack { Circle().fill(Color.gray).frame(width: 8, height: 8); Text("Assente (<10mm)").font(.caption2) }
                            }
                        }
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .shadow(radius: 2)
                        .padding(.trailing, 12)
                        .padding(.top, 4)
                    }
                    
                    Spacer()
                }
                
                // Toast di Notifica Copia CSV
                if mostraNotificaCopiato {
                    VStack {
                        Spacer()
                        Text(messaggioNotifica)
                            .font(.subheadline)
                            .bold()
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.black.opacity(0.85))
                            .cornerRadius(20)
                            .shadow(radius: 5)
                            .padding(.bottom, 30)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("FunghiCS — Previsione Cosenza")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        generaCSVMatricePixelBitmap()
                    } label: {
                        Label("Esporta CSV Pixel", systemImage: "doc.matrix.fill")
                            .font(.caption)
                            .bold()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        mostrandoFormNuovoPunto = true
                    } label: {
                        Label("Aggiungi Punto", systemImage: "plus.circle.fill")
                            .font(.headline)
                    }
                }
            }
            .sheet(item: $puntoSelezionato) { punto in
                DettaglioPuntoView(punto: punto)
            }
            .sheet(isPresented: $mostrandoCSVExport) {
                NavigationStack {
                    VStack(spacing: 12) {
                        Text("Matrice CSV Pixel della Mappa di Calore calcolata dall'App (Copia ed incolla nella chat per confronto 1:1):")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                            .padding(.top, 8)
                        
                        TextEditor(text: $testoCSVGenerato)
                            .font(.system(.caption2, design: .monospaced))
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                            .padding(.horizontal)
                        
                        Button {
                            UIPasteboard.general.string = testoCSVGenerato
                            mostraToast("✅ CSV Pixel copiato negli appunti!")
                        } label: {
                            Label("Copia CSV Pixel negli Appunti", systemImage: "doc.on.doc.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                    }
                    .navigationTitle("📋 Export CSV Pixel Mappa")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Chiudi") { mostrandoCSVExport = false }
                        }
                    }
                }
            }
            .sheet(isPresented: $mostrandoFormNuovoPunto) {
                NavigationStack {
                    Form {
                        Section("Dati Nuovo Punto Funghi") {
                            TextField("Nome del punto (es. Pineta Lorica)", text: $nomeNuovoPunto)
                            TextField("Latitudine", text: $latNuovoPunto)
                                .keyboardType(.decimalPad)
                            TextField("Longitudine", text: $lonNuovoPunto)
                                .keyboardType(.decimalPad)
                        }
                    }
                    .navigationTitle("Nuovo Punto")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Annulla") { mostrandoFormNuovoPunto = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Salva") {
                                if let lat = Double(latNuovoPunto), let lon = Double(lonNuovoPunto) {
                                    let terrain = DEMService.shared.getTerrainData(latitude: lat, longitude: lon)
                                    let nuovo = PuntoInteresse(
                                        nome: nomeNuovoPunto.isEmpty ? "Punto Salvato" : nomeNuovoPunto,
                                        latitude: lat,
                                        longitude: lon,
                                        quota: terrain.quota,
                                        pendenza: terrain.pendenza,
                                        esposizione: terrain.esposizione
                                    )
                                    modelContext.insert(nuovo)
                                    mostrandoFormNuovoPunto = false
                                    nomeNuovoPunto = ""
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// Genera la matrice CSV esatta dei pixel della Mappa di Calore (punti montani prioritari in cima)
    private func generaCSVMatricePixelBitmap() {
        struct PixelCSV {
            let y: Int
            let x: Int
            let lat: Double
            let lon: Double
            let quota: Double
            let pioggiaLocale: Double
            let giorniDaPioggia: Int
            let prob: Int
            let statoColore: String
            let hexColor: String
            let isMontano: Bool
        }
        
        var pixelList: [PixelCSV] = []
        
        let width = 300
        let height = 300
        let minLat: Double = 38.80
        let maxLat: Double = 40.35
        let minLon: Double = 15.80
        let maxLon: Double = 17.25
        
        let nodi = MeteoService.nodiGrigliaSpaziale
        let step = 4
        
        for y in stride(from: 0, to: height, by: step) {
            let lat = maxLat - (Double(y) / Double(height)) * (maxLat - minLat)
            
            for x in stride(from: 0, to: width, by: step) {
                let lon = minLon + (Double(x) / Double(width)) * (maxLon - minLon)
                
                let terrain = DEMService.shared.getTerrainData(latitude: lat, longitude: lon)
                let quota = terrain.quota
                let isIdonea = DEMService.shared.isQuotaIdonea(quota: quota)
                let eMare = DEMService.shared.isAreaMareOCosta(lat: lat, lon: lon, quota: quota)
                
                if eMare || quota == 0.0 || !isIdonea {
                    let px = PixelCSV(y: y, x: x, lat: lat, lon: lon, quota: quota, pioggiaLocale: 0.0, giorniDaPioggia: 0, prob: 0, statoColore: "Trasparente", hexColor: "#00000000", isMontano: false)
                    pixelList.append(px)
                } else {
                    var pioggiaLocale = 38.0
                    var tempBase = 16.5
                    var giorniDaPioggia = 4
                    
                    if !nodi.isEmpty {
                        var pesoTotale = 0.0
                        var pioggiaPesata = 0.0
                        var tempPesata = 0.0
                        var giorniDaPioggiaPesati = 0.0
                        
                        for n in nodi {
                            let d2 = (n.lat - lat)*(n.lat - lat) + (n.lon - lon)*(n.lon - lon)
                            let w = 1.0 / max(0.0001, d2)
                            pesoTotale += w
                            pioggiaPesata += n.pioggia15gg * w
                            tempPesata += n.tempMedia * w
                            giorniDaPioggiaPesati += Double(n.giorniDaPioggia) * w
                        }
                        
                        if pesoTotale > 0 {
                            pioggiaLocale = pioggiaPesata / pesoTotale
                            tempBase = tempPesata / pesoTotale
                            giorniDaPioggia = Int(round(giorniDaPioggiaPesati / pesoTotale))
                        }
                    }
                    
                    let tempQuota = max(8.0, tempBase - max(0.0, (quota - 800.0) / 160.0))
                    let meteoLocale = DatiMeteo(
                        pioggiaCumulata15Giorni: pioggiaLocale,
                        temperaturaMedia: tempQuota,
                        umiditaMedia: 65.0,
                        umiditaSuoloMiceliare: pioggiaLocale >= 50.0 ? 0.32 : (pioggiaLocale >= 30.0 ? 0.25 : 0.16),
                        temperaturaSuolo: tempQuota,
                        deltaTSuolo: pioggiaLocale >= 45.0 ? 4.0 : 0.0,
                        velocitaVentoMax: 10.0,
                        evapotraspirazioneET0: 2.5,
                        giorniDaUltimaPioggiaSignificativa: giorniDaPioggia
                    )
                    
                    let pTemp = PuntoInteresse(
                        nome: "Pixel",
                        latitude: lat,
                        longitude: lon,
                        quota: quota,
                        pendenza: terrain.pendenza,
                        esposizione: terrain.esposizione
                    )
                    let res = PrevisioneEngine.calcolaProbabilitaFruttificazione(punto: pTemp, meteo: meteoLocale)
                    let prob = res.probabilitaPercentuale
                    
                    let statoColore: String
                    let hexColor: String
                    
                    if prob >= 65 {
                        statoColore = "Verde_Buttata"
                        hexColor = "#22C55EC8"
                    } else if prob >= 48 {
                        statoColore = "Arancione_Preparazione"
                        hexColor = "#F97316C8"
                    } else if prob >= 30 {
                        statoColore = "Giallo_Esaurimento"
                        hexColor = "#EAB308BE"
                    } else {
                        statoColore = "Grigio_NonFavorevole"
                        hexColor = "#9CA3AF8C"
                    }
                    
                    let px = PixelCSV(y: y, x: x, lat: lat, lon: lon, quota: quota, pioggiaLocale: pioggiaLocale, giorniDaPioggia: giorniDaPioggia, prob: prob, statoColore: statoColore, hexColor: hexColor, isMontano: true)
                    pixelList.append(px)
                }
            }
        }
        
        // Ordiniamo: Prima i punti montani (Quota >= 800m) ordinati per probabilità decrescente, poi i punti trasparenti
        let pixelOrdinati = pixelList.sorted { (p1, p2) -> Bool in
            if p1.isMontano != p2.isMontano {
                return p1.isMontano && !p2.isMontano
            }
            return p1.prob > p2.prob
        }
        
        var csvLines: [String] = []
        csvLines.append("GridY,GridX,Lat,Lon,Quota,PioggiaLocale,GiorniSenzaPioggia,Probabilita,StatoColore,HexColor")
        
        for p in pixelOrdinati {
            let line = String(format: "%d,%d,%.4f,%.4f,%.1f,%.1f,%d,%d,%@,%@",
                              p.y, p.x, p.lat, p.lon, p.quota, p.pioggiaLocale, p.giorniDaPioggia, p.prob, p.statoColore, p.hexColor)
            csvLines.append(line)
        }
        
        let csvCompleto = csvLines.joined(separator: "\n")
        self.testoCSVGenerato = csvCompleto
        
        // Copia automatica negli appunti di iOS
        UIPasteboard.general.string = csvCompleto
        mostrandoCSVExport = true
        mostraToast("📋 CSV Pixel Mappa di Calore copiato negli appunti!")
    }
    
    private func mostraToast(_ messaggio: String) {
        self.messaggioNotifica = messaggio
        withAnimation {
            self.mostraNotificaCopiato = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                self.mostraNotificaCopiato = false
            }
        }
    }
}

// MARK: - UIViewRepresentable MKMapView
struct MapViewRepresentable: UIViewRepresentable {
    let punti: [PuntoInteresse]
    let risultatiMeteoPunti: [UUID: RisultatoPrevisione]
    let mostraMappaDiCalore: Bool
    let filtraSoloZoneIdonee: Bool
    let onSelectPunto: (PuntoInteresse) -> Void
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.mapType = .standard
        
        // Inquadratura iniziale sulla Provincia di Cosenza e Sila
        let center = CLLocationCoordinate2D(latitude: 39.33, longitude: 16.44)
        let span = MKCoordinateSpan(latitudeDelta: 0.9, longitudeDelta: 0.9)
        let region = MKCoordinateRegion(center: center, span: span)
        mapView.setRegion(region, animated: false)
        
        // Aggiunta dell'Overlay Mappa di Calore Fruttificazione / Precipitazioni
        let heatmapOverlay = CosenzaHeatmapOverlay()
        mapView.addOverlay(heatmapOverlay, level: .aboveRoads)
        
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
        mapView.addGestureRecognizer(tapGesture)
        
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        let currentAnnotations = uiView.annotations.compactMap { $0 as? PuntoAnnotation }
        uiView.removeAnnotations(currentAnnotations)
        
        let newAnnotations = punti.map { PuntoAnnotation(punto: $0) }
        uiView.addAnnotations(newAnnotations)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewRepresentable
        
        init(_ parent: MapViewRepresentable) {
            self.parent = parent
            super.init()
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleHeatmapDataUpdated),
                name: .heatmapDataUpdated,
                object: nil
            )
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        @objc private func handleHeatmapDataUpdated() {
            DispatchQueue.main.async {
                // Forziamo il ridisegno dell'overlay MapKit nativo
            }
        }
        
        @objc func handleMapTap(_ gestureRecognizer: UITapGestureRecognizer) {
            guard let mapView = gestureRecognizer.view as? MKMapView else { return }
            let touchPoint = gestureRecognizer.location(in: mapView)
            
            for annotation in mapView.annotations {
                if let view = mapView.view(for: annotation) {
                    let frameInMap = view.convert(view.bounds, to: mapView)
                    if frameInMap.contains(touchPoint) {
                        return
                    }
                }
            }
            
            let coordinate = mapView.convert(touchPoint, toCoordinateFrom: mapView)
            let lat = coordinate.latitude
            let lon = coordinate.longitude
            
            let terrain = DEMService.shared.getTerrainData(latitude: lat, longitude: lon)
            
            let massiccio: String
            if lat >= 39.70 {
                massiccio = "Massiccio del Pollino"
            } else if 39.05 <= lat && lat <= 39.60 && lon >= 16.25 {
                massiccio = "Altopiano della Sila"
            } else {
                massiccio = "Catena Costiera"
            }
            
            let nomeIniziale = "\(massiccio) (\(Int(terrain.quota))m s.l.m.)"
            
            let puntoToccato = PuntoInteresse(
                nome: nomeIniziale,
                latitude: lat,
                longitude: lon,
                quota: terrain.quota,
                pendenza: terrain.pendenza,
                esposizione: terrain.esposizione
            )
            
            parent.onSelectPunto(puntoToccato)
            
            // Geocodifica Inversa Asincrona (CLGeocoder) per estrarre la località/comune reale
            let geocoder = CLGeocoder()
            let location = CLLocation(latitude: lat, longitude: lon)
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                if let place = placemarks?.first {
                    let localita = place.locality ?? place.name ?? place.subLocality ?? massiccio
                    puntoToccato.nome = "\(localita) (\(Int(terrain.quota))m s.l.m.)"
                }
            }
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let customOverlay = overlay as? CosenzaHeatmapOverlay {
                let renderer = CosenzaHeatmapOverlayRenderer(overlay: customOverlay)
                renderer.mostraMappaCalore = parent.mostraMappaDiCalore
                renderer.filtraSoloZoneIdonee = parent.filtraSoloZoneIdonee
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            
            let identifier = "PuntoAnnotationView"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
            
            if annotationView == nil {
                annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = true
                annotationView?.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
            } else {
                annotationView?.annotation = annotation
            }
            
            annotationView?.markerTintColor = .systemGreen
            annotationView?.glyphImage = UIImage(systemName: "leaf.fill")
            
            return annotationView
        }
        
        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
            if let anno = view.annotation as? PuntoAnnotation {
                parent.onSelectPunto(anno.punto)
            }
        }
    }
}

class PuntoAnnotation: NSObject, MKAnnotation {
    let punto: PuntoInteresse
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?
    
    init(punto: PuntoInteresse) {
        self.punto = punto
        self.coordinate = CLLocationCoordinate2D(latitude: punto.latitude, longitude: punto.longitude)
        self.title = punto.nome
        self.subtitle = "\(Int(punto.quota))m s.l.m."
        super.init()
    }
}
