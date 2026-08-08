import SwiftUI
import MapKit
import SwiftData

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
            }
            .navigationTitle("FunghiCS — Previsione Cosenza")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
                                    let p = PuntoInteresse(
                                        nome: nomeNuovoPunto.isEmpty ? "Punto Personalizzato" : nomeNuovoPunto,
                                        latitude: lat,
                                        longitude: lon,
                                        quota: terrain.quota,
                                        pendenza: terrain.pendenza,
                                        esposizione: terrain.esposizione
                                    )
                                    modelContext.insert(p)
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
}

// Representable MapKit Nativo
struct MapViewRepresentable: UIViewRepresentable {
    let punti: [PuntoInteresse]
    let risultatiMeteoPunti: [UUID: RisultatoPrevisione]
    let mostraMappaDiCalore: Bool
    let filtraSoloZoneIdonee: Bool
    let onSelectPunto: (PuntoInteresse) -> Void
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        
        let center = CLLocationCoordinate2D(latitude: 39.30, longitude: 16.45)
        let span = MKCoordinateSpan(latitudeDelta: 0.90, longitudeDelta: 0.90)
        let region = MKCoordinateRegion(center: center, span: span)
        mapView.setRegion(region, animated: false)
        
        mapView.showsUserLocation = true
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = true
        
        let overlay = CosenzaHeatmapOverlay()
        mapView.addOverlay(overlay, level: .aboveLabels)
        
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
        mapView.addGestureRecognizer(tapGesture)
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        let existingAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(existingAnnotations)
        
        for p in punti {
            let anno = PuntoAnnotation(punto: p)
            mapView.addAnnotation(anno)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewRepresentable
        
        init(_ parent: MapViewRepresentable) {
            self.parent = parent
        }
        
        @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let touchPoint = gesture.location(in: mapView)
            
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
