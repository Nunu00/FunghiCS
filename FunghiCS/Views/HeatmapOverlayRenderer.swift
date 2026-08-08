import Foundation
import MapKit
import UIKit
import CoreGraphics

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
    private var lastStateHash: Int = 0
    
    func invalidateCache() {
        cachedImage = nil
        setNeedsDisplay()
    }
    
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard mostraMappaCalore else { return }
        
        let overlayRect = self.overlay.boundingMapRect
        if !mapRect.intersects(overlayRect) { return }
        
        let stateHash = (mostraMappaCalore ? 1 : 0) ^ (filtraSoloZoneIdonee ? 2 : 0)
        if cachedImage == nil || lastStateHash != stateHash {
            cachedImage = generaBitmapCaloreContinuo()
            lastStateHash = stateHash
        }
        
        guard let cgImage = cachedImage else { return }
        
        let drawRect = self.rect(for: overlayRect)
        
        context.saveGState()
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        context.interpolationQuality = .high
        
        // CORREZIONE ASSE Y: Ribalta l'immagine in verticale per far coincidere il Nord in alto ed il Sud in basso
        context.translateBy(x: drawRect.origin.x, y: drawRect.origin.y + drawRect.size.height)
        context.scaleBy(x: 1.0, y: -1.0)
        let localDrawRect = CGRect(x: 0, y: 0, width: drawRect.size.width, height: drawRect.size.height)
        
        context.draw(cgImage, in: localDrawRect)
        context.restoreGState()
    }
    
    /// Genera la mappa di calore a 450x450 pixel usando la PROIEZIONE DI MERCATORE UFFICIALE MAPKIT per combaciare al 100% con la mappa
    private func generaBitmapCaloreContinuo() -> CGImage? {
        let width = 450
        let height = 450
        
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let overlayRect = self.overlay.boundingMapRect
        
        for y in 0..<height {
            // Conversione coordinata Y tramite Proiezione di Mercatore MapKit
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
                
                let idx = (y * width + x) * 4
                
                if eMare || quota == 0.0 {
                    // Mare o Costa: 100% Trasparente
                    pixels[idx]     = 0
                    pixels[idx + 1] = 0
                    pixels[idx + 2] = 0
                    pixels[idx + 3] = 0
                } else if !isIdonea {
                    // Bassa quota (<800m)
                    if filtraSoloZoneIdonee {
                        // Filtro >800m ATTIVO -> 100% Trasparente!
                        pixels[idx]     = 0
                        pixels[idx + 1] = 0
                        pixels[idx + 2] = 0
                        pixels[idx + 3] = 0
                    } else {
                        // Filtro >800m DISATTIVATO -> Grigio/Azzurro trasparente per evidenziare le valli
                        pixels[idx]     = 160 // R
                        pixels[idx + 1] = 180 // G
                        pixels[idx + 2] = 220 // B
                        pixels[idx + 3] = 75  // Alpha
                    }
                } else {
                    // Zona Montana/Boschiva (>=800m s.l.m.) -> Calcolo Fruttificazione Reale
                    let pioggiaBase = 28.0
                    let pioggiaQuota = min(85.0, pioggiaBase + max(0.0, (quota - 800.0) / 45.0))
                    let tempQuota = max(8.0, 22.0 - max(0.0, (quota - 800.0) / 160.0))
                    
                    let meteoLocale = DatiMeteo(
                        pioggiaCumulata15Giorni: pioggiaQuota,
                        temperaturaMedia: tempQuota,
                        giorniDaUltimaPioggiaSignificativa: 5
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
                        // Verde Buttata Probabile (>65%)
                        pixels[idx]     = 34  // R
                        pixels[idx + 1] = 197 // G
                        pixels[idx + 2] = 94  // B
                        pixels[idx + 3] = 160 // Alpha
                    } else if prob >= 48 {
                        // Arancione In Preparazione (48-64%)
                        pixels[idx]     = 249 // R
                        pixels[idx + 1] = 115 // G
                        pixels[idx + 2] = 22  // B
                        pixels[idx + 3] = 160 // Alpha
                    } else if prob >= 30 {
                        // Giallo In Esaurimento (30-47%)
                        pixels[idx]     = 234 // R
                        pixels[idx + 1] = 179 // G
                        pixels[idx + 2] = 8   // B
                        pixels[idx + 3] = 150 // Alpha
                    } else {
                        // Grigio Non Favorevole (<30%)
                        pixels[idx]     = 156 // R
                        pixels[idx + 1] = 163 // G
                        pixels[idx + 2] = 175 // B
                        pixels[idx + 3] = 110 // Alpha
                    }
                }
            }
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let cfData = CFDataCreate(kCFAllocatorDefault, &pixels, pixels.count),
              let dataProvider = CGDataProvider(data: cfData) else {
            return nil
        }
        
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
    
    private func sfocaBitmap(pixels: [UInt8], width: Int, height: Int) -> [UInt8] {
        var output = pixels
        
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = (y * width + x) * 4
                if pixels[idx + 3] == 0 { continue }
                
                var rSum = 0, gSum = 0, bSum = 0, aSum = 0
                var count = 0
                
                for dy in -1...1 {
                    for dx in -1...1 {
                        let nIdx = ((y + dy) * width + (x + dx)) * 4
                        let alpha = Int(pixels[nIdx + 3])
                        if alpha > 0 {
                            rSum += Int(pixels[nIdx])
                            gSum += Int(pixels[nIdx + 1])
                            bSum += Int(pixels[nIdx + 2])
                            aSum += alpha
                            count += 1
                        }
                    }
                }
                
                if count > 0 {
                    output[idx]     = UInt8(rSum / count)
                    output[idx + 1] = UInt8(gSum / count)
                    output[idx + 2] = UInt8(bSum / count)
                    output[idx + 3] = UInt8(aSum / count)
                }
            }
        }
        return output
    }
}
