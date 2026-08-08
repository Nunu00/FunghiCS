#!/usr/bin/env python3
"""
Script per simulare e validare la generazione della Mappa Radar Precipitazioni 15gg (mm)
ed esportare l'immagine dimostrativa dell'overlay.
"""

import numpy as np
from PIL import Image

width, height = 300, 300
img = np.zeros((height, width, 4), dtype=np.uint8)

# Coordinate Cosenza DEM bounds
min_lat, max_lat = 38.80, 40.35
min_lon, max_lon = 15.80, 17.25

lats = np.linspace(max_lat, min_lat, height)
lons = np.linspace(min_lon, max_lon, width)

# Generazione simulata griglia pioggia 15gg (con picchi sulla Sila e sul Pollino)
for y, lat in enumerate(lats):
    for x, lon in enumerate(lons):
        # Simula accumuli pioggia 15gg (10mm - 90mm)
        d_sila = np.sqrt((lat - 39.30)**2 + (lon - 16.45)**2)
        d_pollino = np.sqrt((lat - 39.88)**2 + (lon - 16.18)**2)
        
        pioggia = 15.0 + 75.0 * np.exp(-d_sila / 0.30) + 65.0 * np.exp(-d_pollino / 0.25)
        
        # Filtro mare/costa
        if lat < 38.95 and lon < 16.1:
            img[y, x] = [0, 0, 0, 0]
        else:
            if pioggia >= 70.0:
                img[y, x] = [30, 64, 175, 210]  # Blu Scuro Elettrico (Abbondante)
            elif pioggia >= 45.0:
                img[y, x] = [6, 182, 212, 200]  # Azzurro Ciano Intenso (Ottima)
            elif pioggia >= 25.0:
                img[y, x] = [16, 185, 129, 190] # Verde Smeraldo (Moderata)
            elif pioggia >= 10.0:
                img[y, x] = [234, 179, 8, 170]  # Giallo Sabbia (Scarsa)
            else:
                img[y, x] = [156, 163, 175, 120] # Grigio (Assente)

pil_img = Image.fromarray(img, mode="RGBA")
out_path = r"C:\Users\Vincenzo\.gemini\antigravity\brain\9edb03c6-5023-4dbf-8bf3-d755e66455fe\step_rain_matrix.png"
pil_img.save(out_path)
print(f"[OK] Salvata dimostrazione Mappa Precipitazioni 15gg: {out_path}")
