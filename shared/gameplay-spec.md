# Referenzmodell v1

- Welt: 240 × 128 Zellen; eine Zelle = 0,25 m. Bildschirmkoordinaten, X nach rechts, Y nach unten.
- Zeitschritt: 1/30 s. Schwerkraft: 39,24 Zellen/s² = 9,81 m/s².
- Material: 0 Luft, 1 Sand, 2 Fels. Unterste vier Reihen sind Fels.
- Terrainoberfläche: `int(81 + 10 sin(0.035x) + 5 sin(0.081x))`.
- Sand: pro Schritt von unten nach oben, Scanrichtung abwechselnd; unten frei → fallen, sonst freie Diagonale suchen. Ein Korn bewegt sich höchstens eine Zeile.
- Kanonen: X=40 und X=200; Radstützpunkte X±3, Auflage drei Zellen unter dem Körperzentrum; höchster Radkontakt trägt. Neigung wird auf ±0,5 rad begrenzt und ist visuell. Keine freie Körperrotation.
- Winkel: 5–85°, jeweils nach innen gerichtet. Anfang 45°. Stärke: 15–90 Zellen/s, Anfang 55.
- Mündung: Körperposition + (0,−1) + Richtung × 7. Nachladezeit: 0,7 s; maximal 32 aktive Geschosse.
- Flug: zuerst vy += g*dt; dann Bewegung mit Unterteilung auf höchstens eine halbe Zelle. Bodenprobe pro Teilstück. Maximalalter 12 s.
- Einschlag: Kreisradius 10 Zellen, ausschließlich Sand entfernen. Sand fällt anschließend nach.
- Debug „Boden lösen“: Radius 12 bei Kanone+(0,8). Nur offline oder Host.
- Keine Gesundheit, Siegbedingungen, KI, Waffenwahl oder Originalgrafiken in dieser Stufe.

Alle Engines verwenden dieses Modell in eigenem Quellcode. Das ist Grundlage für Parität und späteren Physikvergleich, noch keine Verwendung nativer Rigid-Body-Solver.
