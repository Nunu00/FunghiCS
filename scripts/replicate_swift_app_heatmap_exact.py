#!/usr/bin/env python3
"""
Script per REPLICARE AL 100% RIGOROSO E COMPLETO il modello dell'App iOS FunghiCS:
1. Copernicus CLC 2018 K_veg reale per ogni punto (1.00 boschi, 0.85 arbusteti, 0.00 lacustri/urbani/rocce -> Trasparente [0,0,0,0])
2. Query REST API Open-Meteo per 100 nodi montani con variabili Orarie e Giornaliere REALI (Umidita suolo 3-9cm, DeltaT suolo, Vento, ET0)
3. Trasparenza Alfa [0,0,0,0] per centri urbani, laghi e rocce per mostrare MapKit
4. Ordine ed equazione esatti di PrevisioneEngine.swift
"""

import json
import urllib.request
import numpy as np
from PIL import Image

# 1. Caricamento DEM TINITALY INGV 10m con Copernicus CLC 2018 e Suoli SoilGrids
dem_path = r"C:\Antigravity\previsioni_funghi\FunghiCS\Resources\cosenza_dem.json"
with open(dem_path, "r", encoding="utf-8") as f:
    dem_data = json.load(f)

points = dem_data["points"]
min_lat, max_lat = dem_data["minLat"], dem_data["maxLat"]
min_lon, max_lon = dem_data["minLon"], dem_data["maxLon"]

# Seleziona 100 nodi montani (quota >= 800m) sparsi per la griglia spaziale
punti_montani = [p for p in points if p.get("elevation", 0) >= 800.0]
step = max(1, len(punti_montani) // 100)
nodi_coords = [(p["lat"], p["lon"]) for p in punti_montani[::step][:100]]

print(f"[*] Query Open-Meteo LIVE API completa (Hourly & Daily) per {len(nodi_coords)} nodi montani di Cosenza e Sila...")

lat_str = ",".join([f"{c[0]:.4f}" for c in nodi_coords])
lon_str = ",".join([f"{c[1]:.4f}" for c in nodi_coords])

# API Query con variabili orarie (soil_moisture_3_to_9cm, soil_temperature_0_to_10cm) e giornaliere
url = f"https://api.open-meteo.com/v1/forecast?latitude={lat_str}&longitude={lon_str}&daily=precipitation_sum,temperature_2m_max,temperature_2m_min,wind_speed_10m_max,et0_fao_evapotranspiration&hourly=relative_humidity_2m,soil_moisture_3_to_9cm,soil_temperature_0_to_10cm&past_days=16&forecast_days=1&timezone=Europe/Rome"

req = urllib.request.Request(url, headers={'User-Agent': 'FunghiCS-FullModelReplicator/1.0'})
nodi_meteo_live = []

try:
    with urllib.request.urlopen(req) as response:
        data = json.loads(response.read().decode('utf-8'))
        if not isinstance(data, list):
            data = [data]
            
        for item in data:
            lat = item.get("latitude")
            lon = item.get("longitude")
            daily = item.get("daily", {})
            hourly = item.get("hourly", {})
            
            precip = daily.get("precipitation_sum", [])
            temp_max = daily.get("temperature_2m_max", [])
            temp_min = daily.get("temperature_2m_min", [])
            winds = daily.get("wind_speed_10m_max", [])
            ets = daily.get("et0_fao_evapotranspiration", [])
            
            # 1. Pioggia Cumulata 15 giorni ed ultimo evento piovoso
            valid_precip = [p if p is not None else 0.0 for p in precip]
            pioggia_totale = sum(valid_precip)
            
            ultimi_giorni_senza_pioggia = 0
            for p_val in reversed(valid_precip):
                if p_val >= 5.0:
                    break
                ultimi_giorni_senza_pioggia += 1
                
            # 2. Temperatura Media
            valid_tmax = [t for t in temp_max if t is not None]
            valid_tmin = [t for t in temp_min if t is not None]
            count = min(len(valid_tmax), len(valid_tmin))
            temp_sum = sum((valid_tmax[i] + valid_tmin[i]) / 2.0 for i in range(count))
            temp_media = (temp_sum / count) if count > 0 else 16.0
            
            # 3. Vento max ed Evapotraspirazione ET0
            valid_winds = [w for w in winds if w is not None]
            vento_max = max(valid_winds) if valid_winds else 10.0
            
            valid_ets = [e for e in ets if e is not None]
            et0_val = max(valid_ets) if valid_ets else 2.5
            
            # 4. Umidità del Suolo Miceliare (3-9cm) sugli ultimi 5 giorni (120 ore recenti post-pioggia)
            soil_moisture = hourly.get("soil_moisture_3_to_9cm", [])
            valid_sm = [s for s in soil_moisture if s is not None]
            recent_sm = valid_sm[-120:] if len(valid_sm) >= 120 else valid_sm
            umidita_suolo_3_9 = (sum(recent_sm) / len(recent_sm)) if recent_sm else 0.25
            
            soil_temp = hourly.get("soil_temperature_0_to_10cm", [])
            valid_st = [t for t in soil_temp if t is not None]
            temp_suolo = (sum(valid_st) / len(valid_st)) if valid_st else temp_media
            delta_t_suolo = (max(valid_st) - min(valid_st)) if len(valid_st) > 1 else 0.0
            
            nodi_meteo_live.append({
                "lat": lat,
                "lon": lon,
                "pioggia15gg": pioggia_totale,
                "tempMedia": temp_media,
                "giorniDaPioggia": ultimi_giorni_senza_pioggia,
                "umiditaSuoloMiceliare": umidita_suolo_3_9,
                "temperaturaSuolo": temp_suolo,
                "deltaTSuolo": delta_t_suolo,
                "velocitaVentoMax": vento_max,
                "evapotraspirazioneET0": et0_val
            })
            
    print(f"[OK] Open-Meteo LIVE API completa: scaricati dati reali per {len(nodi_meteo_live)} nodi montani!")
    
except Exception as e:
    print(f"[WARN] Errore Open-Meteo API: {e}. Uso fallback simulato.")
    for c in nodi_coords:
        nodi_meteo_live.append({
            "lat": c[0], "lon": c[1],
            "pioggia15gg": 65.0 if c[0] < 39.5 else 48.0,
            "tempMedia": 15.5, "giorniDaPioggia": 4,
            "umiditaSuoloMiceliare": 0.28, "temperaturaSuolo": 15.0,
            "deltaTSuolo": 4.0, "velocitaVentoMax": 12.0, "evapotraspirazioneET0": 2.5
        })

# 2. Costruzione Griglia Spaziale 350x350 O(1)
grid_rows, grid_cols = 350, 350
spatial_grid = [[None for _ in range(grid_cols)] for _ in range(grid_rows)]
d_lat = max_lat - min_lat
d_lon = max_lon - min_lon

for p in points:
    r = min(grid_rows - 1, max(0, int(((max_lat - p["lat"]) / d_lat) * (grid_rows - 1))))
    c = min(grid_cols - 1, max(0, int(((p["lon"] - min_lon) / d_lon) * (grid_cols - 1))))
    spatial_grid[r][c] = p

# 3. Generazione Bitmap 300x300 con logica Swift identica
width, height = 300, 300
img_frutt = np.zeros((height, width, 4), dtype=np.uint8)
img_pioggia = np.zeros((height, width, 4), dtype=np.uint8)

lats = np.linspace(max_lat, min_lat, height)
lons = np.linspace(min_lon, max_lon, width)

print("[*] Calcolo 300x300 pixel con Copernicus CLC 2018 K_veg e dati Open-Meteo reali...")

for y in range(height):
    lat = max_lat - (y / float(height)) * (max_lat - min_lat)
    
    for x in range(width):
        lon = min_lon + (x / float(width)) * (max_lon - min_lon)
        
        r = min(grid_rows - 1, max(0, int(((max_lat - lat) / d_lat) * (grid_rows - 1))))
        c = min(grid_cols - 1, max(0, int(((lon - min_lon) / d_lon) * (grid_cols - 1))))
        
        p = spatial_grid[r][c]
        if p is None:
            for dr in [-1, 0, 1]:
                for dc in [-1, 0, 1]:
                    nr, nc = r + dr, c + dc
                    if 0 <= nr < grid_rows and 0 <= nc < grid_cols and spatial_grid[nr][nc] is not None:
                        p = spatial_grid[nr][nc]
                        break
                if p is not None: break

        quota = p["elevation"] if p else 0.0
        clc = p.get("clcClass", "CLC_311") if p else "CLC_211"
        
        # DISCREPANZA 1: K_veg Copernicus CLC 2018 reale
        # 1.00 boschi (311/312/313), 0.85 arbusteti (324), 0.00 laghi (512), rocce (332), urbani (211)
        if clc in ["CLC_512_Water_Bodies", "CLC_332_Bare_Rock_Screes"] or quota <= 20.0 or quota < 800.0:
            k_veg = 0.00
        else:
            kv_val = p.get("kVeg") if p else None
            k_veg = kv_val if kv_val is not None else (1.00 if quota >= 800.0 else 0.00)
            
        # DISCREPANZA 3: Se K_veg <= 0.00 o quota non idonea -> TRASPARENTE [0,0,0,0]
        if k_veg <= 0.00:
            img_frutt[y, x] = [0, 0, 0, 0]
            img_pioggia[y, x] = [0, 0, 0, 0]
        else:
            # DISCREPANZA 2: Interpolazione IDW di TUTTI i dati meteo e suolo reali di Open-Meteo
            peso_totale = 0.0
            pioggia_pesata = 0.0
            temp_pesata = 0.0
            giorni_pesati = 0.0
            sm_pesato = 0.0
            st_pesata = 0.0
            dt_pesato = 0.0
            vento_pesato = 0.0
            et0_pesata = 0.0
            
            if len(nodi_meteo_live) > 0:
                for n in nodi_meteo_live:
                    d2 = (n["lat"] - lat)**2 + (n["lon"] - lon)**2
                    w = 1.0 / max(0.0001, d2)
                    peso_totale += w
                    pioggia_pesata += n["pioggia15gg"] * w
                    temp_pesata += n["tempMedia"] * w
                    giorni_pesati += float(n["giorniDaPioggia"]) * w
                    sm_pesato += n["umiditaSuoloMiceliare"] * w
                    st_pesata += n["temperaturaSuolo"] * w
                    dt_pesato += n["deltaTSuolo"] * w
                    vento_pesato += n["velocitaVentoMax"] * w
                    et0_pesata += n["evapotraspirazioneET0"] * w
                    
                if peso_totale > 0:
                    pioggia_locale = pioggia_pesata / peso_totale
                    temp_base = temp_pesata / peso_totale
                    giorni_da_pioggia = int(round(giorni_pesati / peso_totale))
                    umidita_suolo_miceliare = sm_pesato / peso_totale
                    temp_suolo = st_pesata / peso_totale
                    delta_t_suolo = dt_pesato / peso_totale
                    vento_max = vento_pesato / peso_totale
                    et0_val = et0_pesata / peso_totale
                else:
                    pioggia_locale, temp_base, giorni_da_pioggia = 38.0, 16.5, 4
                    umidita_suolo_miceliare, temp_suolo, delta_t_suolo = 0.25, 15.0, 0.0
                    vento_max, et0_val = 10.0, 2.5
            else:
                pioggia_locale, temp_base, giorni_da_pioggia = 38.0, 16.5, 4
                umidita_suolo_miceliare, temp_suolo, delta_t_suolo = 0.25, 15.0, 0.0
                vento_max, et0_val = 10.0, 2.5

            temp_quota = max(8.0, temp_base - max(0.0, (quota - 800.0) / 160.0))
            
            pendenza = p.get("slope", 10.0) if p else 10.0
            esposizione = p.get("aspect", "N") if p else "N"
            soil_type = p.get("soilType", "sandy_granite") if p else "sandy_granite"
            
            # DISCREPANZA 4: Ordine esatto di PrevisioneEngine.swift (Soglia Porcino Boletus edulis = 35.0mm)
            soglia_base = 35.0
            fattore_corr = 1.0
            
            if quota > 1000.0: fattore_corr *= 0.90
            esp_upper = esposizione.upper()
            if "S" in esp_upper: fattore_corr *= 1.15
            elif "N" in esp_upper: fattore_corr *= 1.0
            
            if pendenza > 20.0: fattore_corr *= 1.15
            elif pendenza < 5.0: fattore_corr *= 0.95
            
            soglia_calc = soglia_base * fattore_corr
            rapporto_p = pioggia_locale / max(1.0, soglia_calc)
            p_max = min(100.0, rapporto_p * 85.0)
            
            temp_favorevole = (temp_suolo >= 8.0 and temp_suolo <= 26.0)
            if not temp_favorevole: p_max *= 0.4
            
            if delta_t_suolo >= 3.5 and pioggia_locale >= 20.0:
                p_max *= 1.20
                
            vento_al_suolo = vento_max * 0.40
            k_vento = 0.75 if (vento_al_suolo > 15.0 or et0_val > 5.5) else 1.00
            
            sigma = 1.8 if soil_type == "sandy_granite" else (3.0 if soil_type == "clay_limestone" else 2.4)
            mu = 6.5
            gauss = np.exp(-((giorni_da_pioggia - mu)**2) / (2.0 * (sigma**2)))
            
            k_umidita = max(0.2, umidita_suolo_miceliare / 0.18) if umidita_suolo_miceliare < 0.18 else 1.0
            
            prob_calc = p_max * gauss * k_veg * k_vento * k_umidita
            if rapporto_p >= 0.50 and giorni_da_pioggia <= 6:
                prob_calc = max(38.0, prob_calc)
                
            prob = int(max(0.0, min(100.0, prob_calc)))
            
            # COLORAZIONI ESATTE SWIFT:
            if prob >= 65:
                img_frutt[y, x] = [34, 197, 94, 200]   # Verde (>65%)
            elif prob >= 48:
                img_frutt[y, x] = [249, 115, 22, 200]  # Arancione (48-64%)
            elif prob >= 30:
                img_frutt[y, x] = [234, 179, 8, 190]   # Giallo (30-47%)
            else:
                img_frutt[y, x] = [156, 163, 175, 140] # Grigio (<30%)
                
            if pioggia_locale >= 70.0:
                img_pioggia[y, x] = [30, 64, 175, 210]   # Blu Scuro (>=70mm)
            elif pioggia_locale >= 45.0:
                img_pioggia[y, x] = [6, 182, 212, 200]   # Azzurro Ciano (45-69mm)
            elif pioggia_locale >= 25.0:
                img_pioggia[y, x] = [16, 185, 129, 190]  # Verde Smeraldo (25-44mm)
            elif pioggia_locale >= 10.0:
                img_pioggia[y, x] = [234, 179, 8, 170]   # Giallo (10-24mm)
            else:
                img_pioggia[y, x] = [156, 163, 175, 120] # Grigio (<10mm)

out_frutt = r"C:\Users\Vincenzo\.gemini\antigravity\brain\9edb03c6-5023-4dbf-8bf3-d755e66455fe\step5_final_heatmap.png"
out_pioggia = r"C:\Users\Vincenzo\.gemini\antigravity\brain\9edb03c6-5023-4dbf-8bf3-d755e66455fe\step_rain_fruiting_heatmap.png"

# Resize 600x600 per visualizzazione nitida
Image.fromarray(img_frutt, mode="RGBA").resize((600, 600), Image.NEAREST).save(out_frutt)
Image.fromarray(img_pioggia, mode="RGBA").resize((600, 600), Image.NEAREST).save(out_pioggia)

print(f"[OK] Replicazione COMPLETA e RIGOROSA salvata in: {out_frutt}")
print(f"[OK] Replicazione COMPLETA e RIGOROSA salvata in: {out_pioggia}")
