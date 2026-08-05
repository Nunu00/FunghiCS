import Foundation

// Structs matching Open-Meteo REST API payload
struct OpenMeteoResponse: Codable {
    let latitude: Double
    let longitude: Double
    let timezone: String
    let daily: DailyUnitsData?
    let hourly: HourlyUnitsData?
}

struct DailyUnitsData: Codable {
    let time: [String]
    let precipitation_sum: [Double?]?
    let temperature_2m_max: [Double?]?
    let temperature_2m_min: [Double?]?
}

struct HourlyUnitsData: Codable {
    let time: [String]
    let relative_humidity_2m: [Double?]?
    let soil_moisture_0_to_1cm: [Double?]?
}

// Domain representation used by PrevisioneEngine
struct DatiMeteo {
    let pioggiaCumulata15Giorni: Double  // mm di pioggia cumulati negli ultimi 15 giorni
    let temperaturaMedia: Double         // °C media recente
    let umiditaMedia: Double             // % media recente
    let umiditaSuolo: Double             // m³/m³ umidità superficiale suolo
    let giorniDaUltimaPioggiaSignificativa: Int // giorni trascorsi da un evento di pioggia > 5mm
    
    init(
        pioggiaCumulata15Giorni: Double,
        temperaturaMedia: Double,
        umiditaMedia: Double = 65.0,
        umiditaSuolo: Double = 0.25,
        giorniDaUltimaPioggiaSignificativa: Int = 3
    ) {
        self.pioggiaCumulata15Giorni = pioggiaCumulata15Giorni
        self.temperaturaMedia = temperaturaMedia
        self.umiditaMedia = umiditaMedia
        self.umiditaSuolo = umiditaSuolo
        self.giorniDaUltimaPioggiaSignificativa = giorniDaUltimaPioggiaSignificativa
    }
    
    // Factory methods from API response
    static func daOpenMeteo(_ response: OpenMeteoResponse) -> DatiMeteo {
        var pioggiaTotale: Double = 0.0
        var tempSum: Double = 0.0
        var tempCount: Int = 0
        var ultimiGiorniSenzaPioggia = 0
        var trovataPioggiaSignificativa = false
        
        if let daily = response.daily, let precip = daily.precipitation_sum {
            // Take past 15 days or total daily entries
            let validPrecip = precip.compactMap { $0 }
            pioggiaTotale = validPrecip.reduce(0, +)
            
            // Count days since last >5mm rain (traversed backwards)
            for p in validPrecip.reversed() {
                if p >= 5.0 {
                    trovataPioggiaSignificativa = true
                    break
                }
                ultimiGiorniSenzaPioggia += 1
            }
            
            if let tMax = daily.temperature_2m_max, let tMin = daily.temperature_2m_min {
                let validTMax = tMax.compactMap { $0 }
                let validTMin = tMin.compactMap { $0 }
                let count = min(validTMax.count, validTMin.count)
                for i in 0..<count {
                    tempSum += (validTMax[i] + validTMin[i]) / 2.0
                    tempCount += 1
                }
            }
        }
        
        var umiditaMediaVal = 65.0
        var umiditaSuoloVal = 0.25
        if let hourly = response.hourly {
            if let rh = hourly.relative_humidity_2m {
                let validRh = rh.compactMap { $0 }
                if !validRh.isEmpty {
                    umiditaMediaVal = validRh.reduce(0, +) / Double(validRh.count)
                }
            }
            if let sm = hourly.soil_moisture_0_to_1cm {
                let validSm = sm.compactMap { $0 }
                if !validSm.isEmpty {
                    umiditaSuoloVal = validSm.reduce(0, +) / Double(validSm.count)
                }
            }
        }
        
        let tempAvg = tempCount > 0 ? (tempSum / Double(tempCount)) : 16.0
        
        return DatiMeteo(
            pioggiaCumulata15Giorni: pioggiaTotale,
            temperaturaMedia: tempAvg,
            umiditaMedia: umiditaMediaVal,
            umiditaSuolo: umiditaSuoloVal,
            giorniDaUltimaPioggiaSignificativa: trovataPioggiaSignificativa ? ultimiGiorniSenzaPioggia : 15
        )
    }
}
