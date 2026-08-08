import Foundation
import MapKit
import UIKit
import CoreGraphics

extension Notification.Name {
    static let heatmapDataUpdated = Notification.Name("HeatmapDataUpdatedNotification")
}

final class CosenzaHeatmapOverlay: NSObject, MKOverlay {
    let boundingMapRect: MKMapRect
    let coordinate: CLLocationCoordinate2D
    
    // Bounding Box Provincia di Cosenza e Basilicata (Est, Sud, Nord)
    static let minLat: Double = 38.80
    static let maxLat: Double = 40.35
    static let minLon: Double = 15.80
    static let maxLon: Double = 17.25
    
    override init() {
        let p1 = MKMapPoint(CLLocationCoordinate2D(latitude: CosenzaHeatmapOverlay.maxLat, longitude: CosenzaHeatmapOverlay.minLon))
        let p2 = MKMapPoint(CLLocationCoordinate2D(latitude: CosenzaHeatmapOverlay.minLat, longitude: CosenzaHeatmapOverlay.maxLon))
        
        let width = abs(p2.x - p1.x)
        let height = abs(p2.y - p1.y)
        let x = min(p1.x, p2.x)
        let y = min(p1.y, p2.y)
        
        self.boundingMapRect = MKMapRect(x: x, y: y, width: width, height: height)
        self.coordinate = CLLocationCoordinate2D(latitude: (CosenzaHeatmapOverlay.minLat + CosenzaHeatmapOverlay.maxLat) / 2.0,
                                                 longitude: (CosenzaHeatmapOverlay.minLon + CosenzaHeatmapOverlay.maxLon) / 2.0)
        super.init()
    }
}

final class CosenzaHeatmapOverlayRenderer: MKOverlayRenderer {
    var mostraMappaCalore: Bool = true
    var filtraSoloZoneIdonee: Bool = true
    
    private var cachedImage: CGImage? = nil
    private var lastNodeCount: Int = -1
    private var notificationObserver: NSObjectProtocol? = nil
    
    override init(overlay: MKOverlay) {
        super.init(overlay: overlay)
        
        // Ascolta aggiornamenti meteo per invalidare la cache e ridisegnare la mappa
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .heatmapDataUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.invalidateCache()
        }
    }
    
    deinit {
        if let obs = notificationObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }
    
    func invalidateCache() {
        cachedImage = nil
        lastNodeCount = -1
        setNeedsDisplay()
    }
    
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard mostraMappaCalore else { return }
        
        let overlayRect = self.overlay.boundingMapRect
        if !mapRect.intersects(overlayRect) { return }
        
        let currentNodesCount = MeteoService.nodiGrigliaSpaziale.count
        if cachedImage == nil || lastNodeCount != currentNodesCount {
            cachedImage = generaBitmapCaloreContinuo()
            lastNodeCount = currentNodesCount
        }
        
        guard let cgImage = cachedImage else { return }
        
        let drawRect = self.rect(for: overlayRect)
        
        context.saveGState()
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        context.interpolationQuality = .high
        
        // Ribalta l'asse Y per far coincidere il Nord in alto ed il Sud in basso
        context.translateBy(x: drawRect.origin.x, y: drawRect.origin.y + drawRect.size.height)
        context.scaleBy(x: 1.0, y: -1.0)
        let localDrawRect = CGRect(x: 0, y: 0, width: drawRect.size.width, height: drawRect.size.height)
        
        context.draw(cgImage, in: localDrawRect)
        context.restoreGState()
    }
    
    /// Genera la mappa di calore a 450x450 pixel allocando memoria nativa heap via CGContext(data: nil)
    private func generaBitmapCaloreContinuo() -> CGImage? {
        let width = 450
        let height = 450
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        // Allocazione nativa gestita da CoreGraphics (data: nil) -> Previene deallocazioni premature e crash al ritorno alla home
        guard let bitmapContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        
        guard let rawPointer = bitmapContext.data else { return nil }
        let pixels = rawPointer.bindMemory(to: UInt8.self, capacity: width * height * 4)
        
        let overlayRect = self.overlay.boundingMapRect
        
        for y in 0..<height {
            let mapY = overlayRect.origin.y + (Double(y) / Double(height)) * overlayRect.size.height
            
            for x in 0..<width {
                let mapX = overlayRect.origin.x + (Double(x) / Double(width)) * overlayRect.size.width
                
                let mapPoint = MKMapPoint(x: mapX, y: mapY)
                let coord = mapPoint.coordinate
                let lat = coord.latitude
                let lon = coord.longitude
                
                let terrain = DEMService.shared.getTerrainData(latitude: lat, longitude: lon)
                let quota = terrain.quota
                let isIdonea = DEMService.shared.isQuotaIdonea(quota: quota)
                let eMare = DEMService.shared.isAreaMareOCosta(lat: lat, lon: lon, quota: quota)
                let k_veg = terrain.kVeg
                
                let idx = (y * width + x) * 4
                
                if eMare || quota == 0.0 || k_veg <= 0.0 {
                    // Mare, Costa o Superficie Non Boschiva (Copernicus K_veg = 0.0): 100% Trasparente
                    pixels[idx]     = 0
                    pixels[idx + 1] = 0
                    pixels[idx + 2] = 0
                    pixels[idx + 3] = 0
                } else if !isIdonea {
                    pixels[idx]     = 0
                    pixels[idx + 1] = 0
                    pixels[idx + 2] = 0
                    pixels[idx + 3] = 0
                } else {
                    // Zona Montana/Boschiva (>=800m s.l.m.) -> Calcolo Fruttificazione Reale da Griglia Spaziale
                    let nodi = MeteoService.nodiGrigliaSpaziale
                    
                    var pioggiaLocale = 28.0
                    var tempBase = 16.5
                    var giorniDaPioggia = 5
                    
                    if !nodi.isEmpty {
                        var pesoTotale = 0.0
                        var pioggiaPesata = 0.0
                        var tempPesata = 0.0
                        
                        for n in nodi {
                            let d2 = (n.lat - lat)*(n.lat - lat) + (n.lon - lon)*(n.lon - lon)
                            let w = 1.0 / max(0.0001, d2)
                            pesoTotale += w
                            pioggiaPesata += n.pioggia15gg * w
                            tempPesata += n.tempMedia * w
                        }
                        
                        if pesoTotale > 0 {
                            pioggiaLocale = pioggiaPesata / pesoTotale
                            tempBase = tempPesata / pesoTotale
                        }
                    }
                    
                    let tempQuota = max(8.0, tempBase - max(0.0, (quota - 800.0) / 160.0))
                    let meteoLocale = DatiMeteo(
                        pioggiaCumulata15Giorni: pioggiaLocale,
                        temperaturaMedia: tempQuota,
                        umiditaMedia: 65.0,
                        umiditaSuoloMiceliare: 0.25,
                        temperaturaSuolo: tempQuota,
                        deltaTSuolo: 0.0,
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
                    
                    if prob >= 65 {
                        // Verde Buttata Probabile (>65%) - Opacità 200 per massima visibilità
                        pixels[idx]     = 34  // R
                        pixels[idx + 1] = 197 // G
                        pixels[idx + 2] = 94  // B
                        pixels[idx + 3] = 200 // Alpha
                    } else if prob >= 48 {
                        // Arancione In Preparazione (48-64%)
                        pixels[idx]     = 249 // R
                        pixels[idx + 1] = 115 // G
                        pixels[idx + 2] = 22  // B
                        pixels[idx + 3] = 200 // Alpha
                    } else if prob >= 30 {
                        // Giallo In Esaurimento (30-47%)
                        pixels[idx]     = 234 // R
                        pixels[idx + 1] = 179 // G
                        pixels[idx + 2] = 8   // B
                        pixels[idx + 3] = 190 // Alpha
                    } else {
                        // Grigio Non Favorevole (<30%)
                        pixels[idx]     = 156 // R
                        pixels[idx + 1] = 163 // G
                        pixels[idx + 2] = 175 // B
                        pixels[idx + 3] = 140 // Alpha
                    }
                }
            }
        }
        
        return bitmapContext.makeImage()
    }
}
