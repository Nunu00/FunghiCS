import Foundation
import MapKit
import UIKit
import CoreGraphics

extension Notification.Name {
    static let heatmapDataUpdated = Notification.Name("HeatmapDataUpdatedNotification")
}

enum TipoMappaOverlay: String, CaseIterable, Identifiable {
    case fruttificazione = "Fruttificazione"
    case precipitazioni = "Pioggia 15gg"
    
    var id: String { rawValue }
}

final class CosenzaHeatmapOverlay: NSObject, MKOverlay {
    let boundingMapRect: MKMapRect
    let coordinate: CLLocationCoordinate2D
    
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
    
    static var tipoMappaCorrente: TipoMappaOverlay = .fruttificazione
    static var sharedFruttificazioneCGImage: CGImage? = nil
    static var sharedPrecipitazioniCGImage: CGImage? = nil
    
    private var notificationObserver: NSObjectProtocol? = nil
    
    override init(overlay: MKOverlay) {
        super.init(overlay: overlay)
        
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .heatmapDataUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setNeedsDisplay()
        }
    }
    
    deinit {
        if let obs = notificationObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }
    
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard mostraMappaCalore else { return }
        
        let cgImage: CGImage?
        if CosenzaHeatmapOverlayRenderer.tipoMappaCorrente == .fruttificazione {
            cgImage = CosenzaHeatmapOverlayRenderer.sharedFruttificazioneCGImage
        } else {
            cgImage = CosenzaHeatmapOverlayRenderer.sharedPrecipitazioniCGImage
        }
        
        guard let imageToDraw = cgImage else { return }
        
        let overlayRect = self.overlay.boundingMapRect
        if !mapRect.intersects(overlayRect) { return }
        
        let drawRect = self.rect(for: overlayRect)
        
        context.saveGState()
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        context.interpolationQuality = .high
        
        context.translateBy(x: drawRect.origin.x, y: drawRect.origin.y + drawRect.size.height)
        context.scaleBy(x: 1.0, y: -1.0)
        let localDrawRect = CGRect(x: 0, y: 0, width: drawRect.size.width, height: drawRect.size.height)
        
        context.draw(imageToDraw, in: localDrawRect)
        context.restoreGState()
    }
}
