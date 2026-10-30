# Prüfstand

Stand: 30.10.2026, Windows und macOS (Godot 4.7.2).

## Waffen G5, Godot v4 (macOS)

| Prüfung | Ergebnis |
|---|---|
| `tests/smoke.gd`, 65 Prüfungen | Bestanden, neu: Standardwaffe, Munition, ungültige Wahl, Raketenschub samt Vorschau, Granate prallt ab und zündet nach 2,5 s, Mega teilt sich in 6 Splitter mit 6 Einschlägen, Schneeball baut Sand ohne Schaden, Medipack, Schild über zwei Treffer, Snapshot mit Waffen/Munition/Schild/Geschossart, Ereignisprotokoll begrenzt, ungültige Waffe und Ereignistyp abgewiesen |
| `tools/test-lan.sh` | Drei Paare bestanden; neu: beide wählen Mega über TCP, Client spielt 2 Splits und 12 Einschläge exakt nach |
| Szene je Waffe 1–7 | Smoke-Läufe bestanden; Screenshots Granate und Mega angesehen (`docs/images/godot-weapons-mega.png`) |

## Integration G3 + G4 + P1, Godot v3 (macOS)

| Prüfung | Ergebnis |
|---|---|
| `tests/smoke.gd`, 44 Simulationsprüfungen | Bestanden: Sand, Ballistik, Effekte, Lebenspunkte und neu: Ruhe am Hang, Rohr relativ zum Chassis, Rückstoß schaukelt ohne Kippen, gekippt keine Schüsse, Aufrichten nach 3 s, einseitige Untergrabung kippt ins Loch, v3-Snapshot mit Starrkörperfeldern |
| `tests/rigid_cannon_test.gd`, 19 Prüfungen | Bestanden (Hang, einseitiger und vollständiger Bodenverlust, Kante, Fall, Rückstoß, Sand, Snapshot) |
| `tools/test-lan.sh` | Beide Paare bestanden: Szenen-Smoke mit Effekten beim Client; Gesundheits-TCP-Test 1000→0 LP, Gewinner, Neustart |
| Szene und Labor | Smoke-Läufe bestanden; Screenshot `docs/images/godot-v3-tilt.png` angesehen |
| Windows-Skripte (`*.ps1`) | Nicht ausgeführt (macOS) |

## Godot-Effekte G4 (macOS)

| Prüfung | Ergebnis |
|---|---|
| Godot 4.7.2, 18 Simulationsprüfungen | Bestanden, zusätzlich: Feuer-/Einschlagereignisse, Flugbahnvorschau trifft den echten Einschlag, Ereignisse nicht im Snapshot, Shared-Assets mit Prüfsumme außerhalb von `godot/` geladen |
| Godot-Szene headless und mit Fenster, 200 Schritte | Bestanden, ein Schuss, ein Einschlag, beide Sounds geladen |
| `tools/test-lan.sh`, Godot Host → Godot Client | Bestanden; Client rekonstruiert beide Schüsse und Einschläge als Effekte |
| Screenshots mit Vorschau und Einschlageffekt | Angesehen (`reports/godot-view.png`, `reports/godot-impact.png`, lokal) |
| Unity/Unreal mit den Godot-Änderungen | Nicht erneut geprüft; Protokoll v1 und Simulationsregeln sind unverändert |

## Aktuell: Godot mit Lebenspunkten

| Prüfung | Ergebnis |
|---|---|
| Godot 4.7.2, 29 Simulationsprüfungen | Bestanden: bisherige Sand-/Ballistiktests plus direkte Treffer, Distanzschaden, Selbstschaden, Tod, Gleichstand, Schusssperre, HP-Snapshot, Version und Neustart |
| Zwei Godot-Prozesse, `Test-GodotHealthLan.ps1` | Bestanden: Client und Host feuern über die reale TCP-Verbindung. Client sieht 1000→800→600→400→200→0 HP, Gewinner und Host-Neustart auf volle HP |
| Bisheriger Godot-LAN-Test, `Test-Lan.ps1` | Weiterhin bestanden: beide Spieler feuern, beide Einschläge werden übertragen |
| Native Szene, Schaden | Bestanden: 800/1000 LP, reduzierter Balken und Krater; Feuer-Button-Signal löst einen weiteren Schuss aus |
| Native Szene, zerstörte Kanone | Bestanden: 0/1000 LP, Wrack, Gewinnertext; Feuer-Button kann nach Rundenende keinen Schuss erzeugen |
| Visuelle Kontrolle | Vorher-, Schadens- und Sieger-Screenshots angesehen; HUD und Welt ohne Überlagerung |
| Unity und Unreal | In diesem Schritt unverändert; keine Gesundheitsparität behauptet |

Godot nutzt inzwischen Protokoll v3 (v2 plus Starrkörper). Die nachfolgenden Engineübergreifenden Tests belegen **nur den Initialstand mit v1**, nicht Kompatibilität der aktuellen Godot-Erweiterung.

Lokale neue Nachweise: `reports/godot-health-tests.log`, `health-lan-{host,client}.log`, `godot-health-scene.log`, `godot-victory-scene.log` und `godot-health-{before,after,victory}.png`. Zwei kleine geprüfte Ergebnisbilder liegen unter `docs/images/`. Echte Tastatur-/Mausbedienung auf zwei physischen Rechnern und Langzeittest bleiben offen.

## Initialstand 717005d (historischer Prüfstand, Protokoll v1)

| Prüfung | Ergebnis |
|---|---|
| Godot 4.7.2, 12 Simulationsprüfungen | Bestanden: Sanderhaltung, Fels, Auflage, Untergrabung, Nachrutschen, Schuss, Cooldown, Flug, Einschlag, Snapshot und Version; frühere Angabe 13 war ein Zählfehler |
| Godot-Szene, 200 Simulationsschritte mit automatischem Schuss | Bestanden, ein Einschlag |
| Unity 6000.6.3f1, 8 Simulationsprüfungen | Bestanden |
| Unity Windows x64 Development Build | Erfolgreich, lokal unter `builds/unity/CannonHill.exe` |
| Unity-Spielstart, 200 Schritte mit automatischem Schuss | Erfolgreich, ein Einschlag |
| Godot Host → Godot Client | Zwei getrennte Prozesse; je ein Schuss pro Spieler, beide Einschläge auf Host und Client bestätigt |
| Unity Host → Godot Client | Derselbe Loopback-Test bestanden |
| Godot Host → Unity Client | Derselbe Loopback-Test bestanden |
| Unity Host → Unity Client | Derselbe Loopback-Test mit dem finalen Build bestanden |
| Spielansichten Godot und Unity | Native Viewport-Screenshots nach 60 Simulationsschritten angesehen: Gelände, beide Kanonen, Projektil und HUD sichtbar |
| Unreal | C++-Quellprojekt vorhanden; keine nutzbare Unreal-Engine installiert, daher **nicht kompiliert oder gestartet** |

Unreal benötigt UE 5.4+ und deren C++-Toolchain. Engine-Version noch nicht verbindlich festgelegt. Auch die Unreal-LAN-Implementierung ist bis zum Build und Prozess-Test unbestätigt.

Unitys Build lief außerhalb der Sandbox mit der vorhandenen Unity-Personal-Lizenz. Ein Sandbox-Lizenzfehler und ein falscher Paketname wurden vor dem erfolgreichen Build behoben. Godot-Sandboxläufe meldeten Zugriffsbeschränkungen für Benutzer-Cache und Zertifikatsspeicher; die Simulationstests und die gerenderte Szene liefen trotzdem erfolgreich. Die LAN-Tests liefen außerhalb der Netzwerksandbox.

Lokal liegen Nachweise in `reports/`: `unity-build.log`, `unity-runtime.log`, `godot-runtime.log`, `lan-{host,client}.log`, `{unity-godot,godot-unity,unity-unity}-{host,client}.log` und die beiden Screenshots. Diese Logs enthalten teilweise Rechnerdetails und werden nicht veröffentlicht.

Die automatischen LAN-Läufe testen Zustandsübertragung und Schüsse über `127.0.0.1`. Sie testen weder Windows-Firewall noch einen zweiten physischen Rechner. Bedienung per Tastatur/Maus und Langzeitverhalten sind noch manuell abzunehmen.

## Manuelle Abnahme auf zwei PCs (noch offen)

- [ ] Gleiche Revision starten; Host auf PC 1, Client mit dessen LAN-IP auf PC 2.
- [ ] Beide Kanonen zielen und schießen gleichzeitig, ohne Zugwechsel.
- [ ] Einschlag, Krater und absackende Kanonen auf beiden Rechnern sichtbar.
- [ ] Host-Neustart wird auf Client übernommen.
- [ ] Dritter Client wird abgewiesen.
- [ ] Trennung, erneute Verbindung und Host-Beenden ergeben verständliche Zustände.
- [ ] Je verfügbarem Enginepaar beide Host-Richtungen testen.

Automatisierte Loopback-Tests ersetzen diese Abnahme nicht. Native Rigid-Body-Physik und freie Rotation gehören nicht zum aktuellen Modell.
