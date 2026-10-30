# Prüfstand

Stand: 30.10.2026, Windows und macOS (Godot 4.7.2).

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

Godot nutzt jetzt Protokoll v2. Die nachfolgenden Engineübergreifenden Tests belegen **nur den Initialstand mit v1**, nicht Kompatibilität der aktuellen Godot-Erweiterung.

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
