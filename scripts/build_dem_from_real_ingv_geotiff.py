#!/usr/bin/env python3
import glob
import os
import math
import json
import numpy as np
from PIL import Image

def utm32n_to_latlon(easting, northing):
    a = 6378137.0
    f = 1 / 298.257223563
    b = a * (1 - f)
    e2 = (a**2 - b**2) / (a**2)
    e_prime2 = (a**2 - b**2) / (b**2)
    
    k0 = 0.9996
    lon0 = 9.0 * math.pi / 180.0
    
    x = easting - 500000.0
    y = northing
    
    M = y / k0
    mu = M / (a * (1 - e2/4 - 3*e2**2/64 - 5*e2**3/256))
    e1 = (1 - math.sqrt(1 - e2)) / (1 + math.sqrt(1 - e2))
    
    phi1 = mu + (3*e1/2 - 27*e1**3/32)*math.sin(2*mu) + (21*e1**2/16 - 55*e1**4/32)*math.sin(4*mu) + (151*e1**3/96)*math.sin(6*mu)
    
    N1 = a / math.sqrt(1 - e2 * math.sin(phi1)**2)
    T1 = math.tan(phi1)**2
    C1 = e_prime2 * math.cos(phi1)**2
    R1 = a * (1 - e2) / ((1 - e2 * math.sin(phi1)**2)**1.5)
    D = x / (N1 * k0)
    
    lat = phi1 - (N1 * math.tan(phi1) / R1) * (D**2/2 - (5 + 3*T1 + 10*C1 - 4*C1**2 - 9*e_prime2)*D**4/24 + (61 + 90*T1 + 28*C1 + 45*T1**2 - 252*e_prime2 - 3*C1**2)*D**6/720)
    lon = lon0 + (D - (1 + 2*T1 + C1)*D**3/6 + (5 - 2*C1 + 28*T1 - 3*C1**2 + 8*e_prime2 + 24*T1**2)*D**5/120) / math.cos(phi1)
    
    return math.degrees(lat), math.degrees(lon)

def process_ingv_geotiffs():
    print("[*] Avvio elaborazione TILE GeoTIFF REALI INGV TINITALY 10m (Bounding Box Ampliato)...")
    
    cosenza_tiles = [
        "e43010_s10", "e43015_s10",
        "e43510_s10", "e43515_s10",
        "e44005_s10", "e44010_s10", "e44015_s10",
        "e44505_s10", "e44510_s10", "e44515_s10"
    ]
    
    all_points = []
    # Bounding Box ampliato verso destra (Est) e verso il basso (Sud) + Basilicata
    min_lat_b, max_lat_b = 38.80, 40.35
    min_lon_b, max_lon_b = 15.80, 17.25
    
    for t in cosenza_tiles:
        tif_path = f"ingv_tiles/{t}/{t}.tif"
        if not os.path.exists(tif_path):
            print(f"  [!] Manca {tif_path}")
            continue
            
        print(f"[+] Lettura GeoTIFF INGV 10m: {t}.tif...")
        im = Image.open(tif_path)
        arr = np.array(im)
        tags = im.tag_v2
        
        tiepoint = tags.get(33922)
        pixel_scale = tags.get(33550)
        
        if not tiepoint or not pixel_scale:
            continue
            
        origin_x = tiepoint[3]
        origin_y = tiepoint[4]
        scale_x = pixel_scale[0]
        scale_y = pixel_scale[1]
        
        rows, cols = arr.shape
        step = 35 # Campionamento ad alta densità (ogni 350m)
        
        count_tile = 0
        for r in range(0, rows, step):
            northing = origin_y - (r * scale_y)
            for c in range(0, cols, step):
                easting = origin_x + (c * scale_x)
                elev = float(arr[r, c])
                
                if elev < -100 or elev > 3000:
                    continue
                    
                lat, lon = utm32n_to_latlon(easting, northing)
                
                if min_lat_b <= lat <= max_lat_b and min_lon_b <= lon <= max_lon_b:
                    all_points.append({
                        "lat": round(lat, 4),
                        "lon": round(lon, 4),
                        "elevation": round(max(0.0, elev), 1),
                        "slope": 14.0 if elev > 800 else 4.0,
                        "aspect": "N"
                    })
                    count_tile += 1
                    
        print(f"  [OK] Tile {t}: Estratti {count_tile} punti INGV TINITALY 10m REALI!")
        
    result = {
        "minLat": min_lat_b,
        "maxLat": max_lat_b,
        "minLon": min_lon_b,
        "maxLon": max_lon_b,
        "points": all_points
    }
    
    out_json = "FunghiCS/Resources/cosenza_dem.json"
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)
        
    print(f"\n[OK] COMPLETATO CON SUCCESSO! Esportato {out_json} con {len(all_points)} punti REALI dai GeoTIFF 10m INGV!")

if __name__ == "__main__":
    process_ingv_geotiffs()
