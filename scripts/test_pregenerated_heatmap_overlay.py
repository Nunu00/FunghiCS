#!/usr/bin/env python3
"""
Script per verificare la generazione asincrona della mappa di calore a 300x300 pixel (90.000 punti)
e la velocita di calcolo sul PC.
"""

import json
import os
import time
import math
import numpy as np
from scipy.spatial import KDTree

dem_path = r"C:\Antigravity\previsioni_funghi\FunghiCS\Resources\cosenza_dem.json"
with open(dem_path, "r", encoding="utf-8") as f:
    dem_data = json.load(f)

points = dem_data["points"]
print(f"[*] Caricati {len(points)} punti DEM INGV per test pre-calcolo heatmap...")

start_time = time.time()

# Costruzione KDTree
dem_coords = np.array([[p["lat"], p["lon"]] for p in points])
tree = KDTree(dem_coords)

width = 300
height = 300

min_lat, max_lat = dem_data["minLat"], dem_data["maxLat"]
min_lon, max_lon = dem_data["minLon"], dem_data["maxLon"]

lats_vec = np.linspace(max_lat, min_lat, height)
lons_vec = np.linspace(min_lon, max_lon, width)
grid_lon, grid_lat = np.meshgrid(lons_vec, lats_vec)
grid_points = np.column_stack([grid_lat.ravel(), grid_lon.ravel()])

distances_sq, indices = tree.query(grid_points)

elapsed = time.time() - start_time
print(f"[OK] Pre-calcolo di 90.000 pixel completato in {elapsed:.3f} secondi!")
