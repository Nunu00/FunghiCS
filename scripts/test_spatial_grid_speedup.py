#!/usr/bin/env python3
"""
Script per verificare la velocita del lookup O(1) con Griglia Spaziale 350x350
rispetto al ciclo lineare 109.329 punti.
"""

import json
import time
import numpy as np

dem_path = r"C:\Antigravity\previsioni_funghi\FunghiCS\Resources\cosenza_dem.json"
with open(dem_path, "r", encoding="utf-8") as f:
    dem_data = json.load(f)

points = dem_data["points"]
min_lat, max_lat = dem_data["minLat"], dem_data["maxLat"]
min_lon, max_lon = dem_data["minLon"], dem_data["maxLon"]

grid_rows = 350
grid_cols = 350

print(f"[*] Costruisco Griglia Spaziale O(1) per {len(points)} punti INGV...")

grid = [[None for _ in range(grid_cols)] for _ in range(grid_rows)]

t0 = time.time()
d_lat = max_lat - min_lat
d_lon = max_lon - min_lon

for p in points:
    r = min(349, max(0, int(((max_lat - p["lat"]) / d_lat) * 349.0)))
    c = min(349, max(0, int(((p["lon"] - min_lon) / d_lon) * 349.0)))
    grid[r][c] = p

t1 = time.time()
print(f"[OK] Griglia Spaziale 350x350 creata in {t1 - t0:.4f} secondi!")

# Test di 90.000 lookup
t2 = time.time()
lats = np.linspace(max_lat, min_lat, 300)
lons = np.linspace(min_lon, max_lon, 300)

found_count = 0
for lat in lats:
    r = min(349, max(0, int(((max_lat - lat) / d_lat) * 349.0)))
    for lon in lons:
        c = min(349, max(0, int(((lon - min_lon) / d_lon) * 349.0)))
        p = grid[r][c]
        if p is not None:
            found_count += 1

t3 = time.time()
print(f"[OK] 90.000 query eseguite in {t3 - t2:.4f} secondi! (Trovati {found_count} punti su 90.000)")
