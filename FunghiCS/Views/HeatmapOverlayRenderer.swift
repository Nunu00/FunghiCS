import Foundation
import MapKit
import UIKit
import CoreGraphics

final class CosenzaHeatmapOverlay: NSObject, MKOverlay {
    let boundingMapRect: MKMapRect
    let coordinate: CLLocationCoordinate2D
    
    // Bounding Box Provincia di Cosenza
    static let minLat: Double = 39.02
    static let maxLat: Double = 40.18
    static let minLon: Double = 15.82
    static let maxLon: Double = 16.78
    
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
        
        context.draw(cgImage, in: drawRect)
        context.restoreGState()
    }
    
    /// Genera la mappa di calore come bitmap sfumata continua (senza bordi a quadratini)
    private func generaBitmapCaloreContinuo() -> CGImage? {
        let width = 220
        let height = 240
        
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let meteoGenerale = DatiMeteo(pioggiaCumulata15Giorni: 64.0, temperaturaMedia: 15.8)
        
        let latSpan = CosenzaHeatmapOverlay.maxLat - CosenzaHeatmapOverlay.minLat
        let lonSpan = CosenzaHeatmapOverlay.maxLon - CosenzaHeatmapOverlay.minLon
        
        for y in 0..<height {
            // Nota: Y cresce verso il basso nei sistemi di coordinate grafiche
            let lat = CosenzaHeatmapOverlay.maxLat - (Double(y) / Double(height)) * latSpan
            
            for x in 0..<width {
                let lon = CosenzaHeatmapOverlay.minLon + (Double(x) / Double(width)) * lonSpan
                
                let terrain = DEMService.shared.getTerrainData(latitude: lat, longitude: lon)
                let quota = terrain.quota
                let isIdonea = DEMService.shared.isQuotaIdonea(quota: quota)
                let eMare = DEMService.shared.isAreaMareOCosta(lat: lat, lon: lon, quota: quota)
                
                let idx = (y * width + x) * 4
                
                if eMare {
                    // Mare o Costa: 100% Trasparente
                    pixels[idx]     = 0
                    pixels[idx + 1] = 0
                    pixels[idx + 2] = 0
                    pixels[idx + 3] = 0
                } else if !isIdonea {
                    // Bassa quota (<800m)
                    if filtraSoloZoneIdonee {
                        // Se il filtro >800m è ATTIVO: 100% Trasparente
                        pixels[idx]     = 0
                        pixels[idx + 1] = 0
                        pixels[idx + 2] = 0
                        pixels[idx + 3] = 0
                    } else {
                        // Se il filtro >800m è DISATTIVATO: Grigio/Azzurro trasparente
                        pixels[idx]     = 180 // R
                        pixels[idx + 1] = 190 // G
                        pixels[idx + 2] = 210 // B
                        pixels[idx + 3] = 70  // Alpha
                    }
                } else {
                    // Zona Montana/Boschiva (>=800m s.l.m.) -> Calcolo Probabilità Fruttificazione
                    let pTemp = PuntoInteresse(
                        nome: "Pixel",
                        latitude: lat,
                        longitude: lon,
                        quota: quota,
                        pendenza: terrain.pendenza,
                        esposizione: terrain.esposizione
                    )
                    let res = PrevisioneEngine.calcolaProbabilitaFruttificazione(punto: pTemp, meteo: meteoGenerale)
                    let prob = res.probabilitaPercentuale
                    
                    if prob >= 65 {
                        // Verde Buttata Probabile
                        pixels[idx]     = 34  // R
                        pixels[idx + 1] = 197 // G
                        pixels[idx + 2] = 94  // B
                        pixels[idx + 3] = 150 // Alpha
                    } else if prob >= 45 {
                        // Arancione In Preparazione
                        pixels[idx]     = 249 // R
                        pixels[idx + 1] = 115 // G
                        pixels[idx + 2] = 22  // B
                        pixels[idx + 3] = 150 // Alpha
                    } else if prob >= 30 {
                        // Giallo In Esaurimento
                        pixels[idx]     = 234 // R
                        pixels[idx + 1] = 179 // G
                        pixels[idx + 2] = 8   // B
                        pixels[idx + 3] = 150 // Alpha
                    } else {
                        // Grigio Non Favorevole
                        pixels[idx]     = 156 // R
                        pixels[idx + 1] = 163 // G
                        pixels[idx + 2] = 175 // B
                        pixels[idx + 3] = 110 // Alpha
                    }
                }
            }
        }
        
        // Applicazione filtro di sfocatura per rendere la mappa termica 100% continua e senza bordi
        var sfumato = sfocaBitmap(pixels: pixels, width: width, height: height)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let cfData = CFDataCreate(kCFAllocatorDefault, &sfumato, sfumato.count),
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
    
    /// Sfocatura box-blur 3x3 per eliminare bordi rigidi
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
