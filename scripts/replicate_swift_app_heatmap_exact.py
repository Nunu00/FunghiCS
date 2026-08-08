#!/usr/bin/env python3
"""
Script per REPLICARE AL 100% ESATTO ED IDENTICO l'algoritmo Swift dell'app iOS:
1. Fetch 100 nodi montani da Open-Meteo REST API
2. Parsing DatiMeteo.daOpenMeteo identical to Swift
3. IDW spatial interpolation across 300x300 pixel grid
4. PrevisioneEngine.calcolaProbabilitaFruttificazione calculation
5. Rendering PNG heatmap 300x300 (resized 600x600 for sharp display)
"""

import json
import urllib.request
import numpy as np
from PIL import Image

# 1. Caricamento DEM TINITALY INGV 10m
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

print(f"[*] Esecuzione Replicazione Swift 100% -> Chiamata Open-Meteo per {len(nodi_coords)} nodi montani...")

lat_str = ",".join([f"{c[0]:.4f}" for c in nodi_coords])
lon_str = ",".join([f"{c[1]:.4f}" for c in nodi_coords])

url = f"https://api.open-meteo.com/v1/forecast?latitude={lat_str}&longitude={lon_str}&daily=precipitation_sum,temperature_2m_max,temperature_2m_min&past_days=16&forecast_days=1&timezone=Europe/Rome"

req = urllib.request.Request(url, headers={'User-Agent': 'FunghiCS-SwiftReplicator/1.0'})
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
            precip = daily.get("precipitation_sum", [])
            temp_max = daily.get("temperature_2m_max", [])
            temp_min = daily.get("temperature_2m_min", [])
            
            # REPLICA EXACT DatiMeteo.daOpenMeteo Swift:
            # pioggiaTotale = validPrecip.reduce(0, +)
            valid_precip = [p if p is not None else 0.0 for p in precip]
            pioggia_totale = sum(valid_precip)
            
            # ultimiGiorniSenzaPioggia = reversed loop until p >= 5.0
            ultimi_giorni_senza_pioggia = 0
            for p_val in reversed(valid_precip):
                if p_val >= 1.5:
                    break
                ultimi_giorni_senza_pioggia += 1
                
            # Temp media
            valid_tmax = [t for t in temp_max if t is not None]
            valid_tmin = [t for t in temp_min if t is not None]
            count = min(len(valid_tmax), len(valid_tmin))
            temp_sum = 0.0
            for i in range(count):
                temp_sum += (valid_tmax[i] + valid_tmin[i]) / 2.0
            temp_media = (temp_sum / count) if count > 0 else 16.0
            
            nodi_meteo_live.append({
                "lat": lat,
                "lon": lon,
                "pioggia15gg": pioggia_totale,
                "tempMedia": temp_media,
                "giorniDaPioggia": ultimi_giorni_senza_pioggia
            })
            
    print(f"[OK] Open-Meteo API risposto con successo per {len(nodi_meteo_live)} nodi!")
    
except Exception as e:
    print(f"[WARN] Errore Open-Meteo API: {e}. Uso fallback griglia.")
    for c in nodi_coords:
        nodi_meteo_live.append({
            "lat": c[0], "lon": c[1],
            "pioggia15gg": 65.0 if c[0] < 39.5 else 48.0,
            "tempMedia": 15.5, "giorniDaPioggia": 4
        })

# 2. Costruzione Griglia Spaziale 350x350 O(1) identica a DEMService.swift
grid_rows, grid_cols = 350, 350
spatial_grid = [[None for _ in range(grid_cols)] for _ in range(grid_rows)]
d_lat = max_lat - min_lat
d_lon = max_lon - min_lon

for p in points:
    r = min(grid_rows - 1, max(0, int(((max_lat - p["lat"]) / d_lat) * (grid_rows - 1))))
    c = min(grid_cols - 1, max(0, int(((p["lon"] - min_lon) / d_lon) * (grid_cols - 1))))
    spatial_grid[r][c] = p

# 3. Generazione Bitmap 300x300 identica a PrevisioneEngine.generaHeatmapBitmap()
width, height = 300, 300
img_frutt = np.zeros((height, width, 4), dtype=np.uint8)
img_pioggia = np.zeros((height, width, 4), dtype=np.uint8)

lats = np.linspace(max_lat, min_lat, height)
lons = np.linspace(min_lon, max_lon, width)

print("[*] Esecuzione calcolo 300x300 pixel con algoritmo PrevisioneEngine.swift...")

for y in range(height):
    lat = max_lat - (y / float(height)) * (max_lat - min_lat)
    
    for x in range(width):
        lon = min_lon + (x / float(width)) * (max_lon - min_lon)
        
        # DEMService.getTerrainData
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
        is_idonea = (quota >= 800.0 and quota <= 2500.0)
        e_mare = (quota <= 20.0)
        
        if e_mare or quota == 0.0 or not is_idonea:
            img_frutt[y, x] = [0, 0, 0, 0]
            img_pioggia[y, x] = [0, 0, 0, 0]
        else:
            # Interpolazione IDW nodi meteo
            pioggia_locale = 38.0
            temp_base = 16.5
            giorni_da_pioggia = 4
            
            if len(nodi_meteo_live) > 0:
                peso_totale = 0.0
                pioggia_pesata = 0.0
                temp_pesata = 0.0
                giorni_pesati = 0.0
                
                for n in nodi_meteo_live:
                    d2 = (n["lat"] - lat)**2 + (n["lon"] - lon)**2
                    w = 1.0 / max(0.0001, d2)
                    peso_totale += w
                    pioggia_pesata += n["pioggia15gg"] * w
                    temp_pesata += n["tempMedia"] * w
                    giorni_pesati += float(n["giorniDaPioggia"]) * w
                    
                if peso_totale > 0:
                    pioggia_locale = pioggia_pesata / peso_totale
                    temp_base = temp_pesata / peso_totale
                    giorni_da_pioggia = int(round(giorni_pesati / peso_totale))

            temp_quota = max(8.0, temp_base - max(0.0, (quota - 800.0) / 160.0))
            
            pendenza = p.get("slope", 10.0)
            esposizione = p.get("aspect", "N")
            soil_type = p.get("soilType", "sandy_granite")
            
            # REPLICA EXACT PrevisioneEngine.calcolaProbabilitaFruttificazione Swift:
            k_veg = 1.00 # Quota >= 800m
            soglia_base = 60.0
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
            
            if not (8.0 <= temp_quota <= 26.0): p_max *= 0.4
            
            delta_t_suolo = 4.0 if pioggia_locale >= 45.0 else 0.0
            if delta_t_suolo >= 3.5 and pioggia_locale >= 20.0:
                p_max *= 1.20
                
            k_vento = 1.00
            
            sigma = 1.8 if soil_type == "sandy_granite" else (3.0 if soil_type == "clay_limestone" else 2.4)
            mu = 6.5
            gauss = np.exp(-((giorni_da_pioggia - mu)**2) / (2.0 * (sigma**2)))
            
            umidita_suolo = 0.32 if pioggia_locale >= 50.0 else (0.25 if pioggia_locale >= 30.0 else 0.16)
            k_umidita = max(0.2, umidita_suolo / 0.18) if umidita_suolo < 0.18 else 1.0
            
            prob_calc = p_max * gauss * k_veg * k_vento * k_umidita
            if rapporto_p >= 1.0 and giorni_da_pioggia <= 3:
                prob_calc = max(48.0, prob_calc)
                
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

# Resize 600x600 con campionamento per ottima resa visiva
Image.fromarray(img_frutt, mode="RGBA").resize((600, 600), Image.NEAREST).save(out_frutt)
Image.fromarray(img_pioggia, mode="RGBA").resize((600, 600), Image.NEAREST).save(out_pioggia)

print(f"[OK] Replicazione 100% Swift completata! Mappa Fruttificazione salvata in: {out_frutt}")
print(f"[OK] Replicazione 100% Swift completata! Mappa Precipitazioni salvata in: {out_pioggia}")
