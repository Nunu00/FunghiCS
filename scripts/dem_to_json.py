#!/usr/bin/env python3
"""
Script per convertire un file DEM GeoTIFF di TINITALY (INGV) in cosenza_dem.json
per l'inclusione nel bundle dell'app iOS FunghiCS.

Requisiti:
    pip install rasterio numpy pyproj

Uso:
    python dem_to_json.py path/to/tinitaly_cosenza.tif path/to/cosenza_dem.json
"""

import sys
import json
import math
import numpy as np

def calculate_slope_and_aspect(elevation_matrix, dx=10.0, dy=10.0):
    """
    Calcola pendenza (gradi) ed esposizione (N, S, E, W, etc.) usando gradiente numerico.
    """
    gy, gx = np.gradient(elevation_matrix, dy, dx)
    slope_rad = np.arctan(np.sqrt(gx**2 + gy**2))
    slope_deg = np.degrees(slope_rad)
    
    aspect_rad = np.arctan2(-gx, gy)
    aspect_deg = np.degrees(aspect_rad) % 360.0
    
    return slope_deg, aspect_deg

def degrees_to_cardinal(deg):
    dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    ix = int((deg + 22.5) / 45.0) % 8
    return dirs[ix]

def process_dem_geotiff(input_tif_path, output_json_path, sample_step=10):
    try:
        import rasterio
        from pyproj import Transformer
    except ImportError:
        print("[!] Errore: Installare rasterio e pyproj per elaborare GeoTIFF reali:")
        print("    pip install rasterio pyproj numpy")
        sys.exit(1)
        
    print(f"[*] Apertura file DEM TINITALY GeoTIFF: {input_tif_path}")
    with rasterio.open(input_tif_path) as src:
        elevation = src.read(1)
        nodata = src.nodata
        
        transformer = Transformer.from_crs(src.crs, "EPSG:4326", always_xy=True)
        
        # Bounding box Cosenza
        min_lat_b, max_lat_b = 39.05, 40.15
        min_lon_b, max_lon_b = 15.75, 16.85
        
        slope_map, aspect_map = calculate_slope_and_aspect(elevation)
        
        points = []
        rows, cols = elevation.shape
        
        print(f"[*] Griglia DEM originale: {rows}x{cols}. Step campionamento: {sample_step}")
        
        for r in range(0, rows, sample_step):
            for c in range(0, cols, sample_step):
                val = elevation[r, c]
                if nodata is not None and val == nodata:
                    continue
                if val < -100 or val > 3000:
                    continue
                    
                x, y = src.xy(r, c)
                lon, lat = transformer.transform(x, y)
                
                if min_lat_b <= lat <= max_lat_b and min_lon_b <= lon <= max_lon_b:
                    s_val = float(slope_map[r, c])
                    a_deg = float(aspect_map[r, c])
                    cardinal = degrees_to_cardinal(a_deg)
                    
                    points.append({
                        "lat": round(lat, 5),
                        "lon": round(lon, 5),
                        "elevation": round(float(val), 1),
                        "slope": round(s_val, 1),
                        "aspect": cardinal
                    })
                    
        result = {
            "minLat": min_lat_b,
            "maxLat": max_lat_b,
            "minLon": min_lon_b,
            "maxLon": max_lon_b,
            "points": points
        }
        
        with open(output_json_path, "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2)
            
        print(f"[✓] Esportato {output_json_path} con successo! Totale punti: {len(points)}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Uso: python dem_to_json.py <input_geotiff> <output_json>")
        sys.exit(0)
    process_dem_geotiff(sys.argv[1], sys.argv[2])
