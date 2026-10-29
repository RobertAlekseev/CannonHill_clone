# Prüfstand

Stand: 29.10.2026, Windows, Initialprototyp.

| Prüfung | Ergebnis |
|---|---|
| Godot 4.7.2, 13 Simulationsprüfungen | Bestanden: Sanderhaltung, Fels, Auflage, Untergrabung, Nachrutschen, Schuss, Cooldown, Flug, Einschlag, Snapshot und Version |
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
