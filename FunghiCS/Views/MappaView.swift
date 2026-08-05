import SwiftUI
import MapKit
import SwiftData

struct MappaView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var punti: [PuntoInteresse]
    
    @State private var mostraMappaDiCalore = true
    @State private var filtraSoloZoneIdonee = true // Quota >= 800m
    
    @State private var puntoSelezionato: PuntoInteresse? = nil
    @State private var mostrandoFormNuovoPunto = false
    @State private var nomeNuovoPunto = ""
    @State private var latNuovoPunto = "39.33"
    @State private var lonNuovoPunto = "16.44"
    
    @State private var risultatiMeteoPunti: [UUID: RisultatoPrevisione] = [:]
    
    var body: some View {
        NavigationStack {
            ZStack {
                // MapKit nativo tramite UIViewRepresentable per rendering ultra-fluido a 60fps senza bordi a quadratini
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
                
                // Controlli Filtri e Legenda in Overlay
                VStack {
                    HStack {
                        // Toggle Filtri
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: $mostraMappaDiCalore) {
                                Label("Mappa Calore", systemImage: "square.grid.3x3.fill")
                                    .font(.caption).bold()
                            }
                            .tint(.green)
                            
                            Toggle(isOn: $filtraSoloZoneIdonee) {
                                Label("Filtro Quota >800m", systemImage: "mountain.2.fill")
                                    .font(.caption).bold()
                            }
                            .tint(.green)
                        }
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .shadow(radius: 2)
                        .padding(.leading, 12)
                        .padding(.top, 10)
                        
                        Spacer()
                        
                        // Legenda Fruttificazione
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Legenda Fruttificazione")
                                .font(.caption2)
                                .bold()
                            HStack { Circle().fill(Color.green).frame(width: 8, height: 8); Text("Buttata (>65%)").font(.caption2) }
                            HStack { Circle().fill(Color.orange).frame(width: 8, height: 8); Text("Preparazione").font(.caption2) }
                            HStack { Circle().fill(Color.yellow).frame(width: 8, height: 8); Text("Esaurimento").font(.caption2) }
                            HStack { Circle().fill(Color.gray).frame(width: 8, height: 8); Text("Non fav. (<30%)").font(.caption2) }
                        }
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .shadow(radius: 2)
                        .padding(.trailing, 12)
                        .padding(.top, 10)
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
                            TextField("Nome Punto (es. Monte Botte Donato)", text: $nomeNuovoPunto)
                            TextField("Latitudine", text: $latNuovoPunto)
                                .keyboardType(.decimalPad)
                            TextField("Longitudine", text: $lonNuovoPunto)
                                .keyboardType(.decimalPad)
                        }
                    }
                    .navigationTitle("Nuovo Punto")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Annulla") { mostrandoFormNuovoPunto = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Salva") {
                                if let lat = Double(latNuovoPunto), let lon = Double(lonNuovoPunto), !nomeNuovoPunto.isEmpty {
                                    creaEPopolaPunto(nome: nomeNuovoPunto, lat: lat, lon: lon)
                                    mostrandoFormNuovoPunto = false
                                }
                            }
                        }
                    }
                }
            }
            .task {
                await calcolaMeteoPunti()
            }
        }
    }
    
    private func calcolaMeteoPunti() async {
        for punto in punti {
            let meteo = await MeteoService.shared.fetchMeteo(latitude: punto.latitude, longitude: punto.longitude)
            let res = PrevisioneEngine.calcolaProbabilitaFruttificazione(punto: punto, meteo: meteo)
            risultatiMeteoPunti[punto.id] = res
        }
    }
    
    private func creaEPopolaPunto(nome: String, lat: Double, lon: Double) {
        let terrain = DEMService.shared.getTerrainData(latitude: lat, longitude: lon)
        let nuovoPunto = PuntoInteresse(
            nome: nome,
            latitude: lat,
            longitude: lon,
            quota: terrain.quota,
            pendenza: terrain.pendenza,
            esposizione: terrain.esposizione
        )
        modelContext.insert(nuovoPunto)
        
        Task {
            let meteo = await MeteoService.shared.fetchMeteo(latitude: lat, longitude: lon)
            let res = PrevisioneEngine.calcolaProbabilitaFruttificazione(punto: nuovoPunto, meteo: meteo)
            risultatiMeteoPunti[nuovoPunto.id] = res
        }
    }
}

// MARK: - UIViewRepresentable Wrapper per MapKit
struct MapViewRepresentable: UIViewRepresentable {
    let punti: [PuntoInteresse]
    let risultatiMeteoPunti: [UUID: RisultatoPrevisione]
    let mostraMappaDiCalore: Bool
    let filtraSoloZoneIdonee: Bool
    let onSelectPunto: (PuntoInteresse) -> Void
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        
        // Centrato sulla provincia di Cosenza
        let center = CLLocationCoordinate2D(latitude: 39.35, longitude: 16.30)
        let span = MKCoordinateSpan(latitudeDelta: 0.95, longitudeDelta: 0.95)
        mapView.setRegion(MKCoordinateRegion(center: center, span: span), animated: false)
        
        // Aggiungi l'overlay della mappa di calore unica sfumata
        let heatmapOverlay = CosenzaHeatmapOverlay()
        mapView.addOverlay(heatmapOverlay, level: .aboveRoads)
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Aggiorna lo stato del renderer dell'overlay se le impostazioni cambiano
        if let renderer = context.coordinator.heatmapRenderer {
            if renderer.mostraMappaCalore != mostraMappaDiCalore || renderer.filtraSoloZoneIdonee != filtraSoloZoneIdonee {
                renderer.mostraMappaCalore = mostraMappaDiCalore
                renderer.filtraSoloZoneIdonee = filtraSoloZoneIdonee
                renderer.invalidateCache()
            }
        }
        
        // Aggiorna gli annotatori dei punti salvati dall'utente
        context.coordinator.aggiornaAnnotations(mapView: mapView, punti: punti, risultati: risultatiMeteoPunti)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewRepresentable
        var heatmapRenderer: CosenzaHeatmapOverlayRenderer? = nil
        private var currentPuntiIds: Set<UUID> = []
        
        init(parent: MapViewRepresentable) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is CosenzaHeatmapOverlay {
                let renderer = CosenzaHeatmapOverlayRenderer(overlay: overlay)
                renderer.mostraMappaCalore = parent.mostraMappaDiCalore
                renderer.filtraSoloZoneIdonee = parent.filtraSoloZoneIdonee
                self.heatmapRenderer = renderer
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func aggiornaAnnotations(mapView: MKMapView, punti: [PuntoInteresse], risultati: [UUID: RisultatoPrevisione]) {
            let pIds = Set(punti.map { $0.id })
            if pIds == currentPuntiIds { return }
            currentPuntiIds = pIds
            
            // Rimuovi annotation esistenti tranne l'overlay
            mapView.removeAnnotations(mapView.annotations)
            
            for punto in punti {
                let ann = PuntoAnnotation(punto: punto)
                mapView.addAnnotation(ann)
            }
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let puntoAnn = annotation as? PuntoAnnotation else { return nil }
            let identifier = "PuntoFunghiAnnotation"
            
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
            if view == nil {
                view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view?.canShowCallout = true
            } else {
                view?.annotation = annotation
            }
            
            let res = parent.risultatiMeteoPunti[puntoAnn.punto.id]
            let prob = res?.probabilitaPercentuale ?? 60
            let colore = res?.stato.colore ?? .green
            
            view?.glyphText = "\(prob)%"
            view?.markerTintColor = UIColor(colore)
            view?.titleVisibility = .visible
            
            return view
        }
        
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let puntoAnn = view.annotation as? PuntoAnnotation {
                parent.onSelectPunto(puntoAnn.punto)
                mapView.deselectAnnotation(view.annotation, animated: true)
            }
        }
    }
}

final class PuntoAnnotation: NSObject, MKAnnotation {
    let punto: PuntoInteresse
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?
    
    init(punto: PuntoInteresse) {
        self.punto = punto
        self.coordinate = CLLocationCoordinate2D(latitude: punto.latitude, longitude: punto.longitude)
        self.title = punto.nome
        self.subtitle = "Quota: \(Int(punto.quota))m s.l.m."
        super.init()
    }
}
