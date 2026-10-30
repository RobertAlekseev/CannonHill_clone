# Aufgaben und Reservierungen

Aktuell arbeitet Robert allein. GitHub-Issues sind die verbindliche Zuweisung; diese Liste beschreibt die Pakete.

| ID | Aufgabe / Dateien | Abnahme | Verantwortlich | Status |
|---|---|---|---|---|
| M0 | Repo, Regeln, Startanleitungen | Öffentlicher Klon enthält keine Caches, Secrets oder großen Assets | Robert | Initialcommit |
| G1 | Godot-Sand und Kanonen: `godot/simulation.gd` | Sand bleibt erhalten, Kanone steht und sackt nach Untergrabung ab | Robert | Automatisiert geprüft |
| G2 | Godot-Ansicht und LAN: `godot/main.gd` | Zwei Prozesse tauschen Zustände und Feuerbefehle aus | Robert | Loopback und Ansicht geprüft |
| U1 | Unity-Parität: `unity/Assets/` | Simulationstests, Windows-Build und LAN-Schnittstelle | Robert | Build, Tests und beide LAN-Richtungen geprüft |
| E1 | Unreal-Parität: `unreal/` | Kompilation, Play, Sand und Projektil, Host/Client | Robert | Quellprojekt; Engine fehlt |
| L1 | Echter LAN-Test / zwei PCs: `docs/VALIDATION.md` | Beide können gleichzeitig schießen; Trennung und Neuverbindung geprüft | Robert | Offen |
| P1 | Physik vertiefen: `godot/lab/`, `godot/tests/rigid_cannon_test.gd`, `shared/physics-proposal-p1.md` | Vorschlag für freie Rotation, Radkontakt und Umkippen mit kleinem Testfall | Robert | Vorschlag und Godot-Labor geprüft; Integration offen |
| V1 | Grafik verbessern | Vergleichbare Vorher/Nachher-Bilder je Engine; kleine freie Assets | Noch unbesetzt | Später |

## Reservierung

1. Issue sich selbst zuweisen und betroffene Dateien benennen, bevor die Bearbeitung beginnt.
2. Keine zweite aktive Aufgabe mit denselben Dateien. Abhängige Arbeit wartet auf Integration.
3. Branch `task/<issue>-<kurzname>`; gemeinsames `main` über einen Pull Request aktualisieren.
4. Projektkonfiguration, Protokoll und gemeinsame Regeln nur mit einer eigenen Integrationsaufgabe ändern.
5. Fertig bedeutet: Abnahme dokumentiert, Reviewer benannt, Änderungen integriert, Reservierung freigegeben.

Beim Einstieg des Kollegen zuerst ein vollständig abgegrenztes Paket reservieren. Auch unterschiedliche Engines haben gemeinsame Abhängigkeiten in `shared/`; diese gehören nicht gleichzeitig zu zwei Aufgaben.
