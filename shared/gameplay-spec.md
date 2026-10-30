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
- Der Initialstand hat keine Gesundheit, Siegbedingungen, KI, Waffenwahl oder Originalgrafiken.

Alle Engines verwenden dieses Modell in eigenem Quellcode. Das ist Grundlage für Parität und späteren Physikvergleich, noch keine Verwendung nativer Rigid-Body-Solver.

## Godot-Erweiterung: Lebenspunkte (v2)

Nur Godot erweitert den Initialstand vorerst:

- 1.000 Lebenspunkte je Kanone, auf null begrenzt.
- Runde Kanonen-Hitbox mit Radius 4 Zellen, pro Projektil-Unterteilschritt geprüft; tote Kanonen sind Wracks und keine Trefferziele.
- Direkter Treffer: genau 200 Schaden. Derselbe Treffer fügt dem direkten Ziel keinen zweiten Explosionsschaden zu.
- Explosionsradius 14 Zellen ab Hüllenrand. Schaden: `round(200 * max(0, 1 - max(0, Abstand_zum_Zentrum - 4) / 14))`.
- Selbstschaden ist möglich. Debug-Untergrabung verursacht keinen Schaden; Fall-/Aufprallschaden ist noch nicht enthalten.
- Nach allen Geschossen eines Schritts prüfen: eine lebende Kanone → Gewinner; keine → Unentschieden. Weitere Geschosse werden entfernt, neue Schüsse bis zum Neustart gesperrt. Sand und Wracks können weiter absacken.
- Neustart regeneriert Terrain, Kanonen, HP und Rundenstatus. Im LAN entscheidet ausschließlich der Host.

Dies ist eigenes Prototyp-Balancing; keine vollständige Originalphysik oder Waffenparität.

## Godot-Erweiterung: Starrkörper-Kanonen (v3)

- Kanonen nutzen das Modell aus `physics-proposal-p1.md` (`godot/rigid_cannon.gd`) statt der v1-Radstützpunkte. Startposition wie v1, Räder immer gebremst.
- Rohrrichtung = Zielrichtung aus v1, um die Chassisneigung gedreht. Drehpunkt Körper + (0, −2) gedreht, Mündung 7 Zellen weiter.
- Rückstoß beim Schuss: Impuls `−Rohrrichtung × Stärke × 0,03` an der Mündung.
- Gekippt (|Neigung| > 90°): keine Schüsse. Nach 3 s ununterbrochen gekippt wird die Kanone aufrecht auf die Oberfläche gesetzt (nicht als Wrack).
- Kanonen bleiben horizontal zwischen 4 und W−4.
