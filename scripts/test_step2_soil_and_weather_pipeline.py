#!/usr/bin/env python3
"""
Script per verificare sul PC lo STEP 2 del Modello Avanzato:
- Umidità del Suolo a 3-9 cm (soil_moisture_3_to_9cm)
- Temperatura del Terreno a 0-10 cm (soil_temperature_0_to_10cm)
- Shock Termico del Suolo (Delta T >= 3.5°C) -> Bonus +20%
- Ampiezza Gaussiana adattata alla Trama del Suolo (sigma_sabbia=1.8 vs sigma_argilla=3.0)
- Evapotraspirazione (ET0) e Vento Secco (K_vento)
"""

import json
import urllib.request
import os
import math
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
from scipy.spatial import KDTree

output_dir = r"C:\Users\Vincenzo\.gemini\antigravity\brain\9edb03c6-5023-4dbf-8bf3-d755e66455fe"
os.makedirs(output_dir, exist_ok=True)

# 1. Carica DEM INGV arricchito con K_veg e Suoli
dem_path = r"C:\Antigravity\previsioni_funghi\FunghiCS\Resources\cosenza_dem.json"
with open(dem_path, "r", encoding="utf-8") as f:
    dem_data = json.load(f)

min_lat, max_lat = dem_data["minLat"], dem_data["maxLat"]
min_lon, max_lon = dem_data["minLon"], dem_data["maxLon"]
points = dem_data["points"]

# 2. Seleziona i 100 nodi boschivi (K_veg = 1.0)
mountain_forest_points = [p for p in points if p.get("kVeg", 0.0) == 1.0]
indices_step = np.linspace(0, len(mountain_forest_points) - 1, 100, dtype=int)
selected_nodes = [mountain_forest_points[i] for i in indices_step]

lat_str = ",".join(str(p["lat"]) for p in selected_nodes)
lon_str = ",".join(str(p["lon"]) for p in selected_nodes)

# Query Open-Meteo REST API per Pioggia, Vento, Umidità Suolo 3-9cm, Temp Suolo 0-10cm ed ET0
url = f"https://api.open-meteo.com/v1/forecast?latitude={lat_str}&longitude={lon_str}&daily=precipitation_sum,wind_speed_10m_max,et0_fao_evapotranspiration&hourly=soil_moisture_3_to_9cm,soil_temperature_0_to_10cm&past_days=16&forecast_days=1&timezone=Europe/Rome"

print("[*] STEP 2: Scaricamento live Dati Suolo & Meteo Avanzati (Umidità Suolo 3-9cm, Temp Suolo 0-10cm, Vento, ET0)...")
req = urllib.request.Request(url, headers={'User-Agent': 'FunghiCS/1.0'})
nodes_step2 = []

with urllib.request.urlopen(req) as resp:
    data = json.loads(resp.read().decode('utf-8'))
    for idx, item in enumerate(data):
        lat = item["latitude"]
        lon = item["longitude"]
        
        # Precipitazioni
        daily_precip = item["daily"]["precipitation_sum"]
        total_rain = sum(p for p in daily_precip if p is not None)
        
        # Vento massimo ed Evapotraspirazione
        wind_max = max(w for w in item["daily"]["wind_speed_10m_max"] if w is not None) if item["daily"].get("wind_speed_10m_max") else 10.0
        et0_max = max(e for e in item["daily"]["et0_fao_evapotranspiration"] if e is not None) if item["daily"].get("et0_fao_evapotranspiration") else 2.5
        
        # Umidità Suolo 3-9 cm (Media recente)
        hourly_sm = item["hourly"].get("soil_moisture_3_to_9cm", [])
        valid_sm = [s for s in hourly_sm if s is not None]
        sm_avg = np.mean(valid_sm[-48:]) if valid_sm else 0.25 # ultimi 2 giorni
        
        # Temperatura Suolo 0-10 cm (Media recente e calcolo Shock Termico Delta T)
        hourly_st = item["hourly"].get("soil_temperature_0_to_10cm", [])
        valid_st = [t for t in hourly_st if t is not None]
        st_avg = np.mean(valid_st[-48:]) if valid_st else 15.0
        
        # Calcolo Shock Termico: Differenza di temperatura suolo prima vs dopo la pioggia
        delta_t_suolo = 0.0
        if len(valid_st) >= 96:
            st_prima = np.mean(valid_st[:48])
            st_dopo = np.mean(valid_st[-48:])
            delta_t_suolo = max(0.0, st_prima - st_dopo)
            
        nodes_step2.append({
            "lat": lat,
            "lon": lon,
            "rain": total_rain,
            "wind": wind_max,
            "et0": et0_max,
            "soil_moisture": sm_avg,
            "soil_temp": st_avg,
            "delta_t": delta_t_suolo,
            "soil_type": selected_nodes[idx].get("soilType", "sandy_granite")
        })

print(f"[OK] Ricevuti con successo dati Suolo & Meteo per tutti i {len(nodes_step2)} nodi montani!")

# 3. Costruzione KDTree DEM INGV
dem_coords = np.array([[p["lat"], p["lon"]] for p in points])
tree = KDTree(dem_coords)

width = 350
height = 350

prob_grid = np.zeros((height, width))
sm_grid = np.zeros((height, width))
st_grid = np.zeros((height, width))

lats_vec = np.linspace(max_lat, min_lat, height)
lons_vec = np.linspace(min_lon, max_lon, width)
grid_lon, grid_lat = np.meshgrid(lons_vec, lats_vec)
grid_points = np.column_stack([grid_lat.ravel(), grid_lon.ravel()])

distances_sq, indices = tree.query(grid_points)
distances_sq = distances_sq ** 2

node_coords = np.array([[n["lat"], n["lon"]] for n in nodes_step2])

for i in range(height * width):
    y = i // width
    x = i % width
    
    lat_p = grid_lat[y, x]
    lon_p = grid_lon[y, x]
    
    min_d = distances_sq[i]
    best_pt = points[indices[i]]
    
    alt = best_pt["elevation"] if (best_pt and min_d < 0.008) else 0.0
    pendenza = best_pt["slope"] if best_pt else 0.0
    esposizione = best_pt["aspect"] if best_pt else "N"
    k_veg = best_pt.get("kVeg", 0.0) if best_pt else 0.0
    soil_type = best_pt.get("soilType", "sandy_granite") if best_pt else "sandy_granite"
    
    if k_veg > 0.0 and alt >= 600.0:
        # Interpolazione pesata IDW dai nodi suolo/meteo
        dists2 = (node_coords[:, 0] - lat_p)**2 + (node_coords[:, 1] - lon_p)**2
        weights = 1.0 / np.maximum(0.0001, dists2)
        w_sum = np.sum(weights)
        
        rain_val = np.sum(np.array([n["rain"] for n in nodes_step2]) * weights) / w_sum
        sm_val = np.sum(np.array([n["soil_moisture"] for n in nodes_step2]) * weights) / w_sum
        st_val = np.sum(np.array([n["soil_temp"] for n in nodes_step2]) * weights) / w_sum
        wind_val = np.sum(np.array([n["wind"] for n in nodes_step2]) * weights) / w_sum
        delta_t_val = np.sum(np.array([n["delta_t"] for n in nodes_step2]) * weights) / w_sum
        
        sm_grid[y, x] = sm_val
        st_grid[y, x] = st_val
        
        # 1. Soglia Pioggia base
        soglia = 60.0
        if alt > 1000.0: soglia *= 0.90
        if "S" in esposizione.upper(): soglia *= 1.15
        if pendenza > 20.0: soglia *= 1.15
        
        p_max = min(100.0, (rain_val / max(1.0, soglia)) * 85.0)
        
        # 2. Bonus Shock Termico del Suolo (+20% se Delta T >= 3.5°C)
        if delta_t_val >= 3.5 and rain_val >= 20.0:
            p_max *= 1.20
        
        # 3. Penalizzazione Vento Secco (se Vento > 22 km/h)
        k_vento = 0.70 if wind_val > 22.0 else 1.00
        
        # 4. Finestra Gaussiana adattata alla Trama del Suolo
        # Sila (sandy_granite): sigma = 1.8 (finestra stretta)
        # Pollino (clay_limestone): sigma = 3.0 (finestra ampia)
        sigma = 1.8 if soil_type == "sandy_granite" else (3.0 if soil_type == "clay_limestone" else 2.4)
        t = 6.0 # picco attuale
        mu = 6.5
        
        gauss_factor = math.exp(-((t - mu)**2) / (2.0 * (sigma**2)))
        
        # 5. Check Umidità Suolo 3-9cm (se < 0.18 m³/m³ il micelio va in quiescenza)
        k_suolo_umidita = max(0.2, min(1.0, sm_val / 0.18)) if sm_val < 0.18 else 1.0
        
        # 6. Check Temperatura Suolo 0-10cm (range ideale 10°C - 22°C)
        k_suolo_temp = 1.0
        if st_val < 8.0 or st_val > 26.0:
            k_suolo_temp = 0.4
        
        prob_finale = p_max * gauss_factor * k_veg * k_vento * k_suolo_umidita * k_suolo_temp
        prob_grid[y, x] = min(100.0, max(0.0, prob_finale))
    else:
        prob_grid[y, x] = 0.0

# -------------------------------------------------------------
# GRAFICO 1: Mappa Umidità del Suolo a 3-9 cm (m³/m³)
# -------------------------------------------------------------
fig, ax = plt.subplots(figsize=(8, 8), dpi=150)
im = ax.imshow(sm_grid, extent=[min_lon, max_lon, min_lat, max_lat], cmap="YlGnBu")
cb = fig.colorbar(im, ax=ax, label="Umidità dello Strato Miceliare a 3-9 cm (m³/m³)")
ax.set_title("STEP 2A: Mappa Umidità del Suolo a 3-9 cm (Open-Meteo REST)", fontsize=9, fontweight="bold")
ax.set_xlabel("Longitudine")
ax.set_ylabel("Latitudine")
fig.tight_layout()
p_sm = os.path.join(output_dir, "step2_soil_moisture.png")
fig.savefig(p_sm)
plt.close(fig)

# -------------------------------------------------------------
# GRAFICO 2: Mappa Termica Fruttificazione STEP 2 (Modello Completo)
# -------------------------------------------------------------
rgba_prob = np.zeros((height, width, 4))
for y in range(height):
    for x in range(width):
        p = prob_grid[y, x]
        if p < 30:
            rgba_prob[y, x] = [0, 0, 0, 0] # Trasparente
        elif p >= 65:
            rgba_prob[y, x] = [0.13, 0.77, 0.37, 0.85] # Verde
        elif p >= 48:
            rgba_prob[y, x] = [0.98, 0.45, 0.09, 0.85] # Arancione
        else:
            rgba_prob[y, x] = [0.92, 0.70, 0.03, 0.85] # Giallo

fig, ax = plt.subplots(figsize=(8, 8), dpi=150)
ax.imshow(rgba_prob, extent=[min_lon, max_lon, min_lat, max_lat])
ax.set_title("STEP 2B: Mappa Calore Fruttificazione Avanzata (Dati Suolo, Vento & Shock Termico)", fontsize=9, fontweight="bold")
ax.set_xlabel("Longitudine")
ax.set_ylabel("Latitudine")
fig.tight_layout()
p_prob = os.path.join(output_dir, "step_rain_fruiting_heatmap.png")
fig.savefig(p_prob)
plt.close(fig)

print("[OK] Generati con successo tutti i grafici di verifica dello STEP 2 sul PC!")
