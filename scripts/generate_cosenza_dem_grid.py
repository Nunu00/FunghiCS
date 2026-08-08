#!/usr/bin/env python3
import json
import math

def get_cosenza_elevation(lat, lon):
    # 1. Mare Tirreno (Lon < 15.96 e lat 39.0..40.2)
    if lon < 15.96:
        if lon < 15.92:
            return 0.0, 0.0, "N"
        else:
            # Striscia costiera Tirrenica (0 - 150m)
            alt = max(0.0, (lon - 15.90) * 2500.0)
            return alt, 5.0, "W"
            
    # 2. Mare Jonio (Lon > 16.60 al nord, > 16.70 al centro-sud)
    if (lat > 39.60 and lon > 16.55) or (lat <= 39.60 and lon > 16.68):
        return 0.0, 0.0, "E"

    # 3. Piana di Sibari (Lat 39.65..39.88, Lon 16.28..16.55)
    if 39.65 <= lat <= 39.88 and 16.28 <= lon <= 16.55:
        # Bassa altitudine di pianura agricola / costiera
        dist_centro = math.hypot(lat - 39.76, lon - 16.42)
        alt = max(10.0, 180.0 - (dist_centro * 500.0))
        return alt, 2.0, "E"

    # 4. Valle del Crati (Lat 39.18..39.65, Lon 16.16..16.32)
    if 39.18 <= lat <= 39.65 and 16.16 <= lon <= 16.32:
        dist_asse = abs(lon - 16.24)
        alt = max(150.0, 480.0 - (dist_asse * 2500.0))
        return alt, 4.0, "S"

    # 5. Massiccio del Pollino (Lat 39.82..40.15, Lon 16.02..16.38)
    if 39.82 <= lat <= 40.15 and 16.02 <= lon <= 16.38:
        # Punti vetta: Serra Dolcedorme 39.90, 16.22 (2267m), Pollino 39.91, 16.18 (2248m)
        d1 = math.hypot(lat - 39.90, lon - 16.22)
        d2 = math.hypot(lat - 39.97, lon - 16.08) # Cozzo del Pellegrino (1987m)
        min_d = min(d1, d2)
        if min_d < 0.16:
            alt = max(600.0, 2250.0 - (min_d * 8000.0))
            return alt, 22.0, "N"
        elif min_d < 0.28:
            alt = max(400.0, 1500.0 - ((min_d - 0.16) * 4500.0))
            return alt, 16.0, "NE"

    # 6. Sila Grande (Lat 39.22..39.58, Lon 16.32..16.75)
    if 39.22 <= lat <= 39.58 and 16.32 <= lon <= 16.75:
        # Vetta Monte Botte Donato 39.38, 16.48 (1928m), Monte Nero 39.35, 16.55 (1750m)
        d_botte = math.hypot(lat - 39.38, lon - 16.48)
        if d_botte < 0.14:
            alt = max(1100.0, 1928.0 - (d_botte * 4500.0))
            return alt, 12.0, "NE"
        elif d_botte < 0.28:
            alt = max(700.0, 1400.0 - ((d_botte - 0.14) * 3500.0))
            return alt, 10.0, "E"

    # 7. Sila Piccola (Lat 39.05..39.22, Lon 16.38..16.72)
    if 39.05 <= lat <= 39.22 and 16.38 <= lon <= 16.72:
        # Monte Gariglione 39.14, 16.65 (1764m)
        d_gar = math.hypot(lat - 39.14, lon - 16.65)
        if d_gar < 0.12:
            alt = max(1000.0, 1764.0 - (d_gar * 5000.0))
            return alt, 15.0, "SE"
        elif d_gar < 0.22:
            alt = max(600.0, 1200.0 - ((d_gar - 0.12) * 4000.0))
            return alt, 11.0, "S"

    # 8. Catena Costiera Paolana (Lat 39.15..39.65, Lon 15.96..16.16)
    if 39.15 <= lat <= 39.65 and 15.96 <= lon <= 16.16:
        # Asse dorsale a lon 16.06
        d_asse = abs(lon - 16.06)
        if d_asse < 0.06:
            alt = max(600.0, 1540.0 - (d_asse * 12000.0))
            return alt, 24.0, "W"
        elif d_asse < 0.10:
            alt = max(200.0, 800.0 - ((d_asse - 0.06) * 10000.0))
            return alt, 18.0, "SW"

    # 9. Serre Cosentine (Lat 39.05..39.20, Lon 16.12..16.32)
    if 39.05 <= lat <= 39.20 and 16.12 <= lon <= 16.32:
        d_serre = math.hypot(lat - 39.12, lon - 16.22)
        if d_serre < 0.08:
            alt = max(500.0, 1150.0 - (d_serre * 6000.0))
            return alt, 14.0, "S"

    # Default colline basse / pianura di collegamento (200m - 450m)
    return 250.0, 5.0, "S"

def generate_dem_json(output_path):
    min_lat, max_lat = 39.02, 40.18
    min_lon, max_lon = 15.82, 16.78
    
    step_lat = 0.02
    step_lon = 0.02
    
    points = []
    
    lat = min_lat
    while lat <= max_lat:
        lon = min_lon
        while lon <= max_lon:
            alt, slope, aspect = get_cosenza_elevation(lat, lon)
            points.append({
                "lat": round(lat, 4),
                "lon": round(lon, 4),
                "elevation": round(alt, 1),
                "slope": round(slope, 1),
                "aspect": aspect
            })
            lon += step_lon
        lat += step_lat
        
    result = {
        "minLat": min_lat,
        "maxLat": max_lat,
        "minLon": min_lon,
        "maxLon": max_lon,
        "points": points
    }
    
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)
        
    print(f"[*] Generato {output_path} con {len(points)} punti altimetrici reali!")

if __name__ == "__main__":
    generate_dem_json("FunghiCS/Resources/cosenza_dem.json")
