import XCTest
@testable import FunghiCS

final class PrevisioneEngineTests: XCTestCase {
    
    // Test Case 1: Correzione Quota Alta vs Bassa
    func testCorrezioneQuota() {
        let puntoBasso = PuntoInteresse(nome: "Basso", latitude: 39.3, longitude: 16.2, quota: 850.0, pendenza: 10.0, esposizione: "N")
        let puntoAlto = PuntoInteresse(nome: "Alto", latitude: 39.3, longitude: 16.5, quota: 1300.0, pendenza: 10.0, esposizione: "N")
        
        let meteo = DatiMeteo(pioggiaCumulata15Giorni: 55.0, temperaturaMedia: 16.0)
        
        let resBasso = PrevisioneEngine.calcolaProbabilitaFruttificazione(punto: puntoBasso, meteo: meteo)
        let resAlto = PrevisioneEngine.calcolaProbabilitaFruttificazione(punto: puntoAlto, meteo: meteo)
        
        XCTAssertEqual(resAlto.ritardoGiorniQuota, 14)
        XCTAssertEqual(resBasso.ritardoGiorniQuota, 0)
        XCTAssertLessThan(resAlto.sogliaRichiesta, resBasso.sogliaRichiesta)
    }
    
    // Test Case 2: Correzione Esposizione Nord vs Sud
    func testCorrezioneEsposizione() {
        let puntoNord = PuntoInteresse(nome: "Versante Nord", latitude: 39.3, longitude: 16.3, quota: 900.0, pendenza: 10.0, esposizione: "N")
        let puntoSud = PuntoInteresse(nome: "Versante Sud", latitude: 39.3, longitude: 16.3, quota: 900.0, pendenza: 10.0, esposizione: "S")
        
        let meteo = DatiMeteo(pioggiaCumulata15Giorni: 60.0, temperaturaMedia: 16.0)
        
        let resNord = PrevisioneEngine.calcolaProbabilitaFruttificazione(punto: puntoNord, meteo: meteo)
        let resSud = PrevisioneEngine.calcolaProbabilitaFruttificazione(punto: puntoSud, meteo: meteo)
        
        XCTAssertGreaterThan(resSud.sogliaRichiesta, resNord.sogliaRichiesta)
    }
    
    // Test Case 3: Correzione Pendenza Ripida vs Pianeggiante
    func testCorrezionePendenza() {
        let puntoRipido = PuntoInteresse(nome: "Ripido", latitude: 39.3, longitude: 16.3, quota: 900.0, pendenza: 25.0, esposizione: "N")
        let puntoPiano = PuntoInteresse(nome: "Pianeggiante", latitude: 39.3, longitude: 16.3, quota: 900.0, pendenza: 3.0, esposizione: "N")
        
        let meteo = DatiMeteo(pioggiaCumulata15Giorni: 60.0, temperaturaMedia: 16.0)
        
        let resRipido = PrevisioneEngine.calcolaProbabilitaFruttificazione(punto: puntoRipido, meteo: meteo)
        let resPiano = PrevisioneEngine.calcolaProbabilitaFruttificazione(punto: puntoPiano, meteo: meteo)
        
        XCTAssertGreaterThan(resRipido.sogliaRichiesta, resPiano.sogliaRichiesta)
    }
    
    // Test Case 4: Stati Temporali Fruttificazione
    func testStatiTemporali() {
        let punto = PuntoInteresse(nome: "Test Point", latitude: 39.3, longitude: 16.3, quota: 900.0, pendenza: 10.0, esposizione: "N")
        
        let meteoButtata = DatiMeteo(pioggiaCumulata15Giorni: 70.0, temperaturaMedia: 16.0, giorniDaUltimaPioggiaSignificativa: 5)
        let resButtata = PrevisioneEngine.calcolaProbabilitaFruttificazione(punto: punto, meteo: meteoButtata)
        XCTAssertEqual(resButtata.stato, .buttataProbabile)
        
        let meteoScarsa = DatiMeteo(pioggiaCumulata15Giorni: 20.0, temperaturaMedia: 16.0, giorniDaUltimaPioggiaSignificativa: 5)
        let resScarsa = PrevisioneEngine.calcolaProbabilitaFruttificazione(punto: punto, meteo: meteoScarsa)
        XCTAssertEqual(resScarsa.stato, .nonFavorevole)
    }
    
    // Test Case 5: Ricalibrazione con Osservazioni Utente
    func testCalibrazioneUtente() {
        let punto = PuntoInteresse(nome: "Test Calibrazione", latitude: 39.3, longitude: 16.3, moltiplicatoreSoglia: 1.0)
        let obsPos = Osservazione(data: Date(), trovato: true, quantitaKg: 1.5, specie: "Porcino", punto: punto)
        punto.osservazioni.append(obsPos)
        
        PrevisioneEngine.ricalibraMoltiplicatore(punto: punto)
        XCTAssertLessThan(punto.moltiplicatoreSoglia, 1.0)
    }
    
    // Test Case 6: Filtro Quota Idonea (>=800m) e Maschera Mare
    func testFiltroQuotaIdoneaEMascheraMare() {
        let dem = DEMService.shared
        XCTAssertFalse(dem.isQuotaIdonea(quota: 400.0)) // 400m -> sotto la quota di 800m
        XCTAssertTrue(dem.isQuotaIdonea(quota: 950.0))  // 950m -> quota idonea
        
        // Verfica maschera mare sul Tirreno
        XCTAssertTrue(dem.isAreaMareOCosta(lat: 39.5, lon: 15.8, quota: 950.0))
        
        let griglia = dem.generaGrigliaTerritorio(stepGradiente: 0.1)
        XCTAssertFalse(griglia.isEmpty)
    }
}
