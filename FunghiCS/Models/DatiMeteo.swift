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
    let wind_speed_10m_max: [Double?]?
    let et0_fao_evapotranspiration: [Double?]?
}

struct HourlyUnitsData: Codable {
    let time: [String]
    let relative_humidity_2m: [Double?]?
    let soil_moisture_0_to_1cm: [Double?]?
    let soil_moisture_3_to_9cm: [Double?]?
    let soil_temperature_0_to_10cm: [Double?]?
}

// Domain representation used by PrevisioneEngine
struct DatiMeteo {
    let pioggiaCumulata15Giorni: Double  // mm di pioggia cumulati negli ultimi 15 giorni
    let temperaturaMedia: Double         // °C media recente
    let umiditaMedia: Double             // % media recente
    let umiditaSuoloMiceliare: Double     // m³/m³ umidità del suolo a 3-9 cm
    let temperaturaSuolo: Double         // °C temperatura del terreno a 0-10 cm
    let deltaTSuolo: Double              // °C shock termico terreno
    let velocitaVentoMax: Double         // km/h velocità del vento
    let evapotraspirazioneET0: Double    // mm/giorno evapotraspirazione
    let giorniDaUltimaPioggiaSignificativa: Int // giorni trascorsi da un evento di pioggia > 5mm
    
    init(
        pioggiaCumulata15Giorni: Double,
        temperaturaMedia: Double,
        umiditaMedia: Double = 65.0,
        umiditaSuoloMiceliare: Double = 0.25,
        temperaturaSuolo: Double = 15.0,
        deltaTSuolo: Double = 0.0,
        velocitaVentoMax: Double = 10.0,
        evapotraspirazioneET0: Double = 2.5,
        giorniDaUltimaPioggiaSignificativa: Int = 3
    ) {
        self.pioggiaCumulata15Giorni = pioggiaCumulata15Giorni
        self.temperaturaMedia = temperaturaMedia
        self.umiditaMedia = umiditaMedia
        self.umiditaSuoloMiceliare = umiditaSuoloMiceliare
        self.temperaturaSuolo = temperaturaSuolo
        self.deltaTSuolo = deltaTSuolo
        self.velocitaVentoMax = velocitaVentoMax
        self.evapotraspirazioneET0 = evapotraspirazioneET0
        self.giorniDaUltimaPioggiaSignificativa = giorniDaUltimaPioggiaSignificativa
    }
    
    // Factory methods from API response
    static func daOpenMeteo(_ response: OpenMeteoResponse) -> DatiMeteo {
        var pioggiaTotale: Double = 0.0
        var tempSum: Double = 0.0
        var tempCount: Int = 0
        var ultimiGiorniSenzaPioggia = 0
        var ventoMax: Double = 10.0
        var et0Val: Double = 2.5
        
        if let daily = response.daily {
            if let precip = daily.precipitation_sum {
                let validPrecip = precip.compactMap { $0 }
                pioggiaTotale = validPrecip.reduce(0, +)
                
                for p in validPrecip.reversed() {
                    if p >= 5.0 { break }
                    ultimiGiorniSenzaPioggia += 1
                }
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
            
            if let winds = daily.wind_speed_10m_max {
                let validWinds = winds.compactMap { $0 }
                if let maxW = validWinds.max() { ventoMax = maxW }
            }
            
            if let ets = daily.et0_fao_evapotranspiration {
                let validEts = ets.compactMap { $0 }
                if let maxE = validEts.max() { et0Val = maxE }
            }
        }
        
        var umiditaMediaVal = 65.0
        var umiditaSuoloMiceliareVal = 0.25
        var tempSuoloVal = 15.0
        var deltaT = 0.0
        
        if let hourly = response.hourly {
            if let rh = hourly.relative_humidity_2m {
                let validRh = rh.compactMap { $0 }
                if !validRh.isEmpty {
                    umiditaMediaVal = validRh.reduce(0, +) / Double(validRh.count)
                }
            }
            
            if let sm = hourly.soil_moisture_3_to_9cm ?? hourly.soil_moisture_0_to_1cm {
                let validSm = sm.compactMap { $0 }
                if !validSm.isEmpty {
                    umiditaSuoloMiceliareVal = validSm.reduce(0, +) / Double(validSm.count)
                }
            }
            
            if let st = hourly.soil_temperature_0_to_10cm {
                let validSt = st.compactMap { $0 }
                if !validSt.isEmpty {
                    tempSuoloVal = validSt.reduce(0, +) / Double(validSt.count)
                    if validSt.count >= 96 {
                        let stPrima = validSt.prefix(48).reduce(0, +) / 48.0
                        let stDopo = validSt.suffix(48).reduce(0, +) / 48.0
                        deltaT = max(0.0, stPrima - stDopo)
                    }
                }
            }
        }
        
        let tempAvg = tempCount > 0 ? (tempSum / Double(tempCount)) : 16.0
        
        return DatiMeteo(
            pioggiaCumulata15Giorni: pioggiaTotale,
            temperaturaMedia: tempAvg,
            umiditaMedia: umiditaMediaVal,
            umiditaSuoloMiceliare: umiditaSuoloMiceliareVal,
            temperaturaSuolo: tempSuoloVal,
            deltaTSuolo: deltaT,
            velocitaVentoMax: ventoMax,
            evapotraspirazioneET0: et0Val,
            giorniDaUltimaPioggiaSignificativa: ultimiGiorniSenzaPioggia
        )
    }
}
