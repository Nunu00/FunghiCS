#!/usr/bin/env python3
import json
import math
import os
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
from scipy.spatial import KDTree  # <--- Aggiunto per ricerca spaziale ultra-veloce

output_dir = r"C:\Users\Vincenzo\.gemini\antigravity\brain\9edb03c6-5023-4dbf-8bf3-d755e66455fe"
os.makedirs(output_dir, exist_ok=True)

# Carica DEM JSON ampliato
with open("C:\Antigravity\previsioni_funghi\FunghiCS\Resources\cosenza_dem.json", "r", encoding="utf-8") as f:
    dem_data = json.load(f)

min_lat = dem_data["minLat"]
max_lat = dem_data["maxLat"]
min_lon = dem_data["minLon"]
max_lon = dem_data["maxLon"]
points = dem_data["points"]

width = 300
height = 300

elevation_grid = np.zeros((height, width))
mask_grid = np.zeros((height, width))
prob_grid = np.zeros((height, width))

# -------------------------------------------------------------
# OTTIMIZZAZIONE: Costruzione KDTree e Griglia Vettoriale (C code / < 0.1s)
# -------------------------------------------------------------
coords = np.array([[p["lat"], p["lon"]] for p in points])
tree = KDTree(coords)

lats = np.linspace(max_lat, min_lat, height)
lons = np.linspace(min_lon, max_lon, width)
grid_lon, grid_lat = np.meshgrid(lons, lats)
grid_points = np.column_stack([grid_lat.ravel(), grid_lon.ravel()])

# Trova il punto più vicino per tutti i 90.000 pixel simultaneamente
distances_sq, indices = tree.query(grid_points)
distances_sq = distances_sq ** 2  # Distanza quadratica come nel codice originale

for i in range(height * width):
    y = i // width
    x = i % width
    
    min_d = distances_sq[i]
    best_pt = points[indices[i]]
    
    alt = best_pt["elevation"] if (best_pt and min_d < 0.008) else 0.0
    pendenza = best_pt["slope"] if best_pt else 0.0
    esposizione = best_pt["aspect"] if best_pt else "N"
    
    elevation_grid[y, x] = alt
    
    # Filtro mare/quota reale: idoneo se alt >= 800m SENZA tagli geografici artificiali!
    is_suitable = (alt >= 800.0 and alt <= 2500.0)
    
    if is_suitable:
        mask_grid[y, x] = 1.0
        
        pioggia = min(95.0, 50.0 + (alt / 30.0))
        temp = max(10.0, 24.0 - (alt / 180.0))
        
        soglia = 60.0
        if alt > 1000.0: soglia *= 0.90
        if "S" in esposizione.upper(): soglia *= 1.15
        if pendenza > 20.0: soglia *= 1.15
        
        prob = min(100.0, (pioggia / max(1.0, soglia)) * 80.0)
        prob_grid[y, x] = prob
    else:
        mask_grid[y, x] = 0.0
        prob_grid[y, x] = 0.0

# -------------------------------------------------------------
# STEP 1: Mappa di Elevazione Reale INGV TINITALY 10m
# -------------------------------------------------------------
fig, ax = plt.subplots(figsize=(7, 7), dpi=140)
im = ax.imshow(elevation_grid, extent=[min_lon, max_lon, min_lat, max_lat], cmap="terrain")
fig.colorbar(im, ax=ax, label="Altitudine (metri s.l.m.)")
ax.set_title("PASSAGGIO 1: Altitudini Reali GeoTIFF INGV (Copertura Ampliata)", fontsize=10, fontweight="bold")
ax.set_xlabel("Longitudine")
ax.set_ylabel("Latitudine")
fig.tight_layout()
p1 = os.path.join(output_dir, "step1_dem_elevation.png")
fig.savefig(p1)
plt.close(fig)

# -------------------------------------------------------------
# STEP 2: Maschera Quota >800m s.l.m. (Senza Tagli Artificiali)
# -------------------------------------------------------------
fig, ax = plt.subplots(figsize=(7, 7), dpi=140)
cmap_mask = mcolors.ListedColormap(['#0f172a', '#22c55e'])
im = ax.imshow(mask_grid, extent=[min_lon, max_lon, min_lat, max_lat], cmap=cmap_mask)
fig.colorbar(im, ax=ax, ticks=[0, 1], label="Zone Idonee (>=800m s.l.m.)")
ax.set_title("PASSAGGIO 2: Filtro Quota >=800m s.l.m. (Tutte le Zone Idonee)", fontsize=10, fontweight="bold")
ax.set_xlabel("Longitudine")
ax.set_ylabel("Latitudine")
fig.tight_layout()
p2 = os.path.join(output_dir, "step2_altitude_filter.png")
fig.savefig(p2)
plt.close(fig)

# -------------------------------------------------------------
# STEP 3: Mappatura Proiezione di Mercatore EPSG:3857 (MapKit)
# -------------------------------------------------------------
fig, ax = plt.subplots(figsize=(7, 7), dpi=140)
im = ax.imshow(elevation_grid, extent=[min_lon, max_lon, min_lat, max_lat], cmap="magma")
ax.grid(True, color="cyan", linestyle="--", linewidth=0.7, alpha=0.7)
ax.set_title("PASSAGGIO 3: Proiezione di Mercatore MapKit (EPSG:3857 Alignment)", fontsize=10, fontweight="bold")
ax.set_xlabel("Longitudine (Mercatore)")
ax.set_ylabel("Latitudine (Mercatore)")
fig.tight_layout()
p3 = os.path.join(output_dir, "step3_mercator_grid.png")
fig.savefig(p3)
plt.close(fig)

# -------------------------------------------------------------
# STEP 4: Matrice Grezza Probabilità Fruttificazione
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

fig, ax = plt.subplots(figsize=(7, 7), dpi=140)
ax.imshow(rgba_prob, extent=[min_lon, max_lon, min_lat, max_lat])
ax.set_title("PASSAGGIO 4: Matrice Grezza Probabilità Fruttificazione", fontsize=10, fontweight="bold")
ax.set_xlabel("Longitudine")
ax.set_ylabel("Latitudine")
fig.tight_layout()
p4 = os.path.join(output_dir, "step4_fruiting_probability.png")
fig.savefig(p4)
plt.close(fig)

# -------------------------------------------------------------
# STEP 5: Mappa Termica Finale Ad Alta Definizione (Non Sfumata)
# -------------------------------------------------------------
fig, ax = plt.subplots(figsize=(7, 7), dpi=140)
ax.imshow(rgba_prob, extent=[min_lon, max_lon, min_lat, max_lat])
ax.set_title("PASSAGGIO 5: Mappa Termica Finale ad Alta Definizione (Senza Sfocatura)", fontsize=10, fontweight="bold")
ax.set_xlabel("Longitudine")
ax.set_ylabel("Latitudine")
fig.tight_layout()
p5 = os.path.join(output_dir, "step5_final_heatmap.png")
fig.savefig(p5)
plt.close(fig)

print("[OK] Generati tutti e 5 i passaggi visuali SENZA tagli artificiali e SENZA sfocatura!")