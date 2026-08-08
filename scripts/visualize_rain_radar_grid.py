#!/usr/bin/env python3
import urllib.request
import json
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

# 1. Carica DEM INGV reale per selezionare nodi SOLO in montagna (>=800m)
with open(r"C:\Antigravity\previsioni_funghi\FunghiCS\Resources\cosenza_dem.json", "r", encoding="utf-8") as f:
    dem_data = json.load(f)

min_lat, max_lat = dem_data["minLat"], dem_data["maxLat"]
min_lon, max_lon = dem_data["minLon"], dem_data["maxLon"]
points = dem_data["points"]

# 2. Seleziona 64 nodi ad alta densità CONFINATI ESCLUSIVAMENTE NELLE ZONE MONTANE >= 800m s.l.m.
mountain_points = [p for p in points if p["elevation"] >= 800.0]
print(f"[*] Trovati {len(mountain_points)} punti INGV in montagna (>=800m). Seleziono 64 nodi distribuite sui massicci...")

# Campionamento uniforme di 64 nodi tra i soli punti montani (Sila, Pollino, Catena Costiera, Basilicata)
indices_step = np.linspace(0, len(mountain_points) - 1, 64, dtype=int)
selected_mountain_nodes = [mountain_points[i] for i in indices_step]

lat_str = ",".join(str(p["lat"]) for p in selected_mountain_nodes)
lon_str = ",".join(str(p["lon"]) for p in selected_mountain_nodes)

url = f"https://api.open-meteo.com/v1/forecast?latitude={lat_str}&longitude={lon_str}&daily=precipitation_sum&past_days=15&forecast_days=1&timezone=Europe/Rome"

print("[*] Scaricamento live di 64 nodi montani (>=800m) in 1 SINGOLA chiamata HTTP...")
req = urllib.request.Request(url, headers={'User-Agent': 'FunghiCS/1.0'})
nodes = []

with urllib.request.urlopen(req) as resp:
    data = json.loads(resp.read().decode('utf-8'))
    for idx, item in enumerate(data):
        lat = item["latitude"]
        lon = item["longitude"]
        daily_precip = item["daily"]["precipitation_sum"]
        total_rain = sum(p for p in daily_precip if p is not None)
        alt = selected_mountain_nodes[idx]["elevation"]
        nodes.append({"lat": lat, "lon": lon, "rain": total_rain, "alt": alt})

print(f"[OK] Ricevuti {len(nodes)} nodi montani (>=800m) live in UN'UNICA CHIAMATA HTTP!")

# 3. Costruzione KDTree DEM INGV
dem_coords = np.array([[p["lat"], p["lon"]] for p in points])
tree = KDTree(dem_coords)

width = 320
height = 320

rain_grid = np.zeros((height, width))
prob_grid = np.zeros((height, width))
mask_grid = np.zeros((height, width))

lats_vec = np.linspace(max_lat, min_lat, height)
lons_vec = np.linspace(min_lon, max_lon, width)
grid_lon, grid_lat = np.meshgrid(lons_vec, lats_vec)
grid_points = np.column_stack([grid_lat.ravel(), grid_lon.ravel()])

distances_sq, indices = tree.query(grid_points)
distances_sq = distances_sq ** 2

node_coords = np.array([[n["lat"], n["lon"]] for n in nodes])
node_rains = np.array([n["rain"] for n in nodes])

for i in range(height * width):
    y = i // width
    x = i % width
    
    lat_p = grid_lat[y, x]
    lon_p = grid_lon[y, x]
    
    # Quota INGV
    min_d = distances_sq[i]
    best_pt = points[indices[i]]
    alt = best_pt["elevation"] if (best_pt and min_d < 0.008) else 0.0
    pendenza = best_pt["slope"] if best_pt else 0.0
    esposizione = best_pt["aspect"] if best_pt else "N"
    
    if alt >= 800.0 and alt <= 2500.0:
        mask_grid[y, x] = 1.0
        
        # Interpolazione Pioggia IDW dai soli nodi montani
        dists2 = (node_coords[:, 0] - lat_p)**2 + (node_coords[:, 1] - lon_p)**2
        weights = 1.0 / np.maximum(0.0001, dists2)
        rain_val = np.sum(node_rains * weights) / np.sum(weights)
        rain_grid[y, x] = rain_val
        
        temp_quota = max(8.0, 22.0 - max(0.0, (alt - 800.0) / 160.0))
        
        soglia = 60.0
        if alt > 1000.0: soglia *= 0.90
        if "S" in esposizione.upper(): soglia *= 1.15
        if pendenza > 20.0: soglia *= 1.15
        
        prob = min(100.0, (rain_val / max(1.0, soglia)) * 80.0)
        prob_grid[y, x] = prob
    else:
        mask_grid[y, x] = 0.0
        prob_grid[y, x] = 0.0
        rain_grid[y, x] = 0.0

# -------------------------------------------------------------
# GRAFICO 1: Mappa Reale delle Precipitazioni (64 Nodi Montani >=800m)
# -------------------------------------------------------------
fig, ax = plt.subplots(figsize=(8, 8), dpi=150)
im = ax.imshow(rain_grid, extent=[min_lon, max_lon, min_lat, max_lat], cmap="Blues")
cb = fig.colorbar(im, ax=ax, label="Precipitazioni Cumulate (mm negli ultimi 15 giorni)")
ax.set_title("Mappa Pioggia 64 Nodi Concentrati in Montagna >=800m s.l.m.", fontsize=10, fontweight="bold")
ax.set_xlabel("Longitudine")
ax.set_ylabel("Latitudine")

# Disegna i nodi meteo concentrati nei boschi montani
for n in nodes:
    ax.scatter(n["lon"], n["lat"], color="red", s=22, zorder=5)
    ax.annotate(f'{n["rain"]:.1f}m', (n["lon"], n["lat"]), color="darkblue", fontsize=6, fontweight="bold", ha="center", va="bottom")

fig.tight_layout()
p_rain = os.path.join(output_dir, "step_rain_matrix.png")
fig.savefig(p_rain)
plt.close(fig)

# -------------------------------------------------------------
# GRAFICO 2: Mappa Termica Fruttificazione dai 64 Nodi Montani
# -------------------------------------------------------------
rgba_prob = np.zeros((height, width, 4))
for y in range(height):
    for x in range(width):
        p = prob_grid[y, x]
        m = mask_grid[y, x]
        if m == 0:
            rgba_prob[y, x] = [0, 0, 0, 0]
        elif p >= 65:
            rgba_prob[y, x] = [0.13, 0.77, 0.37, 0.85] # Verde
        elif p >= 48:
            rgba_prob[y, x] = [0.98, 0.45, 0.09, 0.85] # Arancione
        elif p >= 30:
            rgba_prob[y, x] = [0.92, 0.70, 0.03, 0.85] # Giallo
        else:
            rgba_prob[y, x] = [0.61, 0.64, 0.69, 0.60] # Grigio

fig, ax = plt.subplots(figsize=(8, 8), dpi=150)
ax.imshow(rgba_prob, extent=[min_lon, max_lon, min_lat, max_lat])
ax.set_title("Mappa Calore Fruttificazione (Derivata da 64 Nodi Montani >=800m)", fontsize=10, fontweight="bold")
ax.set_xlabel("Longitudine")
ax.set_ylabel("Latitudine")
fig.tight_layout()
p_prob = os.path.join(output_dir, "step_rain_fruiting_heatmap.png")
fig.savefig(p_prob)
plt.close(fig)

print("[OK] Generati con successo 64 nodi concentrati ESCLUSIVAMENTE sui boschi montani >=800m!")
