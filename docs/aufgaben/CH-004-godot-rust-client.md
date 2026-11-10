# CH-004 · Godot und Browser am Rust-Server

- **Phase** Erledigt
- **Nächster Schritt** Die gemischte Partie auf zwei physischen Rechnern spielen. Unity und Unreal können danach als weitere Clients folgen.

## Research und Plan

Die Godot-Spielansicht soll als erster nativer Client den Rust-Spielserver verwenden. Sie zeigt dessen Terrain, Kanonen, Geschosse und Buffs und sendet Winkel, Stärke und Feuer. Die erste Verbindung erhält Spieler 1 und das Recht zum Neustart. Zu prüfen sind beide Rollen, Abwurfvorwarnung, Kisten, identisches Gelände und Wiederverbindung.

## Implement

Die Verbindung erfolgt mit einer WebSocket-Adresse im vorhandenen Adressfeld oder über `--rust-server=ws://HOST:8000/ws`. Der Adapter übersetzt den Rust-Zustand in die vorhandene Godot-Darstellung. Er validiert Terrain und Zustände und stellt getrennte Verbindungen erneut her. Die normale Spielszene wird auch im Integrationstest verwendet.

Rust-Snapshots und die Begrüßung kennzeichnen den Vertrag mit `protocol: 1`. Die Snapshots enthalten den Server-Tick. Rundennummern werden von Godot ausdrücklich als Ganzzahlen gesendet.

## Review

Der Integrationstest mit der echten Godot-Spielszene und einem zweiten WebSocket-Testclient hat beide Rollen bestanden. Godot sah beide Schüsse, Vorwarnung und Kiste. Der Terrain-Hash stimmte mit dem zweiten Client überein. Neustart und automatische Wiederverbindung wurden bestätigt. Zusätzlich hat die echte Chromium-Oberfläche als Spieler 1 mit der echten Godot-Szene als Spieler 2 bestanden. Der Browser sah beide Schüsse, der Godot-Client bestätigte Abwurf, Kiste, Neustart und Wiederverbindung. Der Browser lieferte in diesem kurzen Headless-Lauf eine p95-Framezeit von 16,8 ms, p95-Zeichenzeit von 0,3 ms und zwei gleichzeitig beobachtete Geschosse.

Der bisherige Godot-Health-LAN-Test sowie Rusts eigener LAN-Test bestanden ebenfalls. Sämtliche Clients liefen auf dem Stand-PC. Die zusätzliche Browserprüfung liegt unter `reports/mixed-browser-smoke.mjs`. Für den wiederholbaren Szenentest im Projektordner `node rust-web/mixed-smoke.mjs <Godot-Konsolen-EXE>` verwenden. Der Test startet und beendet den Rust-Server und die Godot-Prozesse selbst.

Die gemeinsame Partie verwendet derzeit den Rust-Regelsatz mit einer Standardwaffe. Die Tests belegen den Spielzustand und den Netzwerkablauf. Ein manueller Spieltest mit Tastatur/Maus auf zwei Geräten, Safari sowie die gemeinsame Anbindung von Unity und Unreal stehen aus.
