#!/usr/bin/env python3
"""
Script per aggiornare cosenza_dem.json garantendo che OGNI punto appartenente ai bacini idrici dei laghi della Sila
(Lago Arvo, Lago Ampollino, Lago Cecita, Lago Ariamacina) sia classificato al 100% come CLC_512_Water_Bodies con K_veg = 0.00.
"""

import json

dem_path = r"C:\Antigravity\previsioni_funghi\FunghiCS\Resources\cosenza_dem.json"
with open(dem_path, "r", encoding="utf-8") as f:
    data = json.load(f)

points = data["points"]
print(f"[*] Aggiorno la maschera lacustre per i {len(points)} punti INGV...")

def is_lake_point(lat, lon, alt):
    # Lago Arvo (Sila Grande - Lorica): quota invaso ~1278m - 1315m
    if 39.220 <= lat <= 39.275 and 16.460 <= lon <= 16.560 and alt <= 1315.0:
        return True, "CLC_512_Water_Bodies", 0.00, "water"
    
    # Lago Ampollino (Sila Piccola - Trepidò): quota invaso ~1270m - 1300m
    if 39.115 <= lat <= 39.170 and 16.550 <= lon <= 16.650 and alt <= 1300.0:
        return True, "CLC_512_Water_Bodies", 0.00, "water"
        
    # Lago Cecita (Sila Grande - Camigliatello): quota invaso ~1140m - 1170m
    if 39.365 <= lat <= 39.430 and 16.495 <= lon <= 16.610 and alt <= 1170.0:
        return True, "CLC_512_Water_Bodies", 0.00, "water"
        
    # Lago Ariamacina (Sila Grande): quota invaso ~1310m - 1335m
    if 39.310 <= lat <= 39.355 and 16.520 <= lon <= 16.575 and alt <= 1335.0:
        return True, "CLC_512_Water_Bodies", 0.00, "water"
        
    return False, None, None, None

updated_lakes = 0
for p in points:
    is_lake, clc, kv, soil = is_lake_point(p["lat"], p["lon"], p["elevation"])
    if is_lake:
        p["clcClass"] = clc
        p["kVeg"] = kv
        p["soilType"] = soil
        updated_lakes += 1

with open(dem_path, "w", encoding="utf-8") as f:
    json.dump(data, f)

print(f"[OK] Aggiornamento completato! {updated_lakes} punti identificati al 100% come specchio d'acqua K_veg=0.00!")
