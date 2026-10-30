# Aufgaben und Reservierungen

Aktuell arbeitet Robert allein. GitHub-Issues sind die verbindliche Zuweisung; diese Liste beschreibt die Pakete.

Aktueller Schwerpunkt: **Godot mit Lebenspunkten**. Unity und Unreal bleiben zunächst auf Protokoll v1; Godot läuft mit v2. Historische Waffen sind in `docs/CANNONHILL_REFERENCE.md` erfasst, weitere Waffentypen sind noch nicht implementiert.

| ID | Aufgabe / Dateien | Abnahme | Verantwortlich | Status |
|---|---|---|---|---|
| M0 | Repo, Regeln, Startanleitungen | Öffentlicher Klon enthält keine Caches, Secrets oder großen Assets | Robert | Initialcommit |
| G1 | Godot-Sand und Kanonen: `godot/simulation.gd` | Sand bleibt erhalten, Kanone steht und sackt nach Untergrabung ab | Robert | Automatisiert geprüft |
| G2 | Godot-Ansicht und LAN: `godot/main.gd` | Zwei Prozesse tauschen Zustände und Feuerbefehle aus | Robert | Loopback und Ansicht geprüft |
| G3 | Godot-Lebenspunkte und Rundenende | Treffer, Explosionsabfall, Selbstschaden, Zerstörung und Neustart inkl. LAN | Robert | 29 Simulationstests, TCP-Integration und native Ansichten geprüft |
| G4 | Godot-Darstellung und Shared-Assets: `godot/main.gd`, `godot/shared_assets.gd`, `shared/assets/`, `asset-manifests/` | Vorschau, Effekte, Sounds aus gemeinsamem Ordner; ohne Protokolländerung | Robert | Automatisiert geprüft (macOS) |
| G5 | Godot-Waffen: `godot/simulation.gd`, `godot/main.gd`, `shared/` | Sieben Waffen/Hilfsmittel mit Munition, LAN v4 mit Ereignisprotokoll | Robert | Automatisiert geprüft (macOS) |
| U1 | Unity-Parität: `unity/Assets/` | Simulationstests, Windows-Build und LAN-Schnittstelle | Robert | Initialstand geprüft; Gesundheitsparität zurückgestellt |
| E1 | Unreal-Parität: `unreal/` | Kompilation, Play, Sand und Projektil, Host/Client | Robert | Quellprojekt; Engine fehlt |
| L1 | Echter LAN-Test / zwei PCs: `docs/VALIDATION.md` | Beide können gleichzeitig schießen; Trennung und Neuverbindung geprüft | Robert | Offen |
| P1 | Physik vertiefen: `godot/rigid_cannon.gd`, `godot/lab/`, `godot/simulation.gd`, `shared/physics-proposal-p1.md` | Freie Rotation, Radkontakt und Umkippen mit Testfällen, im Spiel | Robert | In Godot integriert (v3); Unity/Unreal-Port offen |
| V1 | Grafik verbessern | Vergleichbare Vorher/Nachher-Bilder je Engine; kleine freie Assets | Noch unbesetzt | Später |

## Reservierung

1. Issue sich selbst zuweisen und betroffene Dateien benennen, bevor die Bearbeitung beginnt.
2. Keine zweite aktive Aufgabe mit denselben Dateien. Abhängige Arbeit wartet auf Integration.
3. Branch `task/<issue>-<kurzname>`; gemeinsames `main` über einen Pull Request aktualisieren.
4. Projektkonfiguration, Protokoll und gemeinsame Regeln nur mit einer eigenen Integrationsaufgabe ändern.
5. Fertig bedeutet: Abnahme dokumentiert, Reviewer benannt, Änderungen integriert, Reservierung freigegeben.

Beim Einstieg des Kollegen zuerst ein vollständig abgegrenztes Paket reservieren. Auch unterschiedliche Engines haben gemeinsame Abhängigkeiten in `shared/`; diese gehören nicht gleichzeitig zu zwei Aufgaben.
