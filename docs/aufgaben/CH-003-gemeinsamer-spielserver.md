# CH-003 · Unreal-LAN und gemeinsamer Spielserver

- **Phase** Erledigt
- **Nächster Schritt** Godot als spielbaren Client an den gemeinsamen Rust-Server anbinden und das Heimnetz mit zwei physischen Geräten prüfen.

## Research

Godot v4, Unity v5 und Unreal v6 nutzen jeweils JSON über TCP. Ihre Nachrichtenfelder und Fähigkeiten unterscheiden sich. Rust-Web sendet Eingaben und Schnappschüsse über WebSocket und verwendet binäre Terrainpakete. Heute erwartet jede Fassung die eigene Nachrichtenform. Unreal-Simulation und Netzwerk liefen im Zeichenaufruf des HUD. Ein Verbindungsversuch ohne Grafikausgabe konnte den TCP-Listener erreichen, erhielt jedoch keinen Zustand.

## Plan

Zuerst zwei Unreal-Spielprozesse über TCP verbinden. Der Gast muss seine Bewegung, die gewählte schwere Waffe, beide Schüsse und Einschläge sowie die fallende Kiste im Host-Zustand sehen. Danach Rust-Web über die Ethernet-Adresse des Stand-PCs prüfen.

Für engineübergreifende Partien einen gemeinsamen, versionierten Vertrag und genau eine autoritative Simulation vorsehen. Der Server vergibt Spielerplätze und berechnet Sand, Schüsse, Buffs und Rundenausgang. Die Clients schicken nur Eingaben und zeichnen die Schnappschüsse. Als erstes dieselben WebSocket-Nachrichten für Rust-Web und einen nativen Godot-Client verwenden. Damit können wir Transport und Spielregeln in einer gemischten Partie testen. Unity und Unreal folgen mit eigenen Darstellungsadaptern.

Der bestehende Rust-Server eignet sich als erste Referenz, weil er den Spielkern bereits verwendet. Go ist eine sinnvolle Option für Lobby, Matchmaking oder Weiterleitung, falls diese Schicht später unabhängig betrieben werden soll. Wenn der autoritative Server selbst Go sein soll, brauchen wir einen abgeglichenen Port der Spielregeln oder eine Schnittstelle zum Rust-Kern. Ein Übersetzer für die vier alten Protokolle würde die unterschiedlichen Regeln und fehlenden Fähigkeiten nicht auflösen.

Für die erste gemischte Partie den Funktionsumfang vorab festlegen. Eine gemeinsame Waffen- und Bewegungsregel wird nötig, wenn Unreal-Fahren und Waffenwahl Teil derselben Partie werden sollen. Jede Verbindung prüft die Protokollversion und der Server entscheidet über erlaubte Eingaben. Abnahme: Rust-Web gegen Godot, beide Rollen, zwei echte Geräte, dasselbe Gelände, Treffer, Buffs, Neustart und Wiederbeitritt. Danach Last und Datenrate pro Partie messen.

## Implement

Die Unreal-Simulation und Netzwerkverarbeitung laufen im Actor-Tick. Der Gast prüft die IPv4-Adresse vor dem Verbindungsaufbau und wartet auf Schreibbereitschaft. Der Host kann ein reguläres TCP-Ende erkennen und den Platz freigeben.

Der erste Lauf mit echter Verbindung scheiterte beim Laden des Gasts. Mehrere vollständige Spielstände lagen gleichzeitig im TCP-Empfangspuffer und wurden zusammen gegen das Limit einer einzelnen Nachricht geprüft. Der Empfänger verarbeitet jetzt vollständige Zeilen schon während des Lesens und begrenzt jede Nachricht einzeln. Der LAN-Smoke-Modus ist auf Entwicklungsbuilds begrenzt. Das Testskript startet getrennte Host- und Gastprozesse und prüft den Abschlussmarker des Gasts.

## Review

Der UE-5.8-Development-Editor-Build und der Test mit zwei separaten Unreal-Spielprozessen bestanden. Beim Gast kamen beide Schüsse und Einschläge an. Der Gast fuhr von X=200 auf X=189,60, die schwere Waffe war aktiv, und der Kisten-Snapshot lag in Tick 151 vor. Wiederholung im Projektordner mit `.\tools\Test-UnrealLan.ps1`. Nachweise: `reports/unreal-lan-e99c28df-host.log` und `reports/unreal-lan-e99c28df-guest.log`. Grafik, manuelle Eingaben und ein zweiter Rechner waren nicht Teil dieses Headless-Tests.

Rust-Web hat mit zwei WebSocket-Clients über die Ethernet-IP des Stand-PCs bestanden. Beide Clients liefen auf demselben Rechner. Der Test bestätigte Schüsse, Terrain, Kisten, Pause, Wiederbeitritt und Host-Neustart. Die Nutzdatenrate im geskripteten Beschuss betrug 7,2 kB/s je Gast. Firewall und zweiter physischer Rechner bleiben offen.

Ein lokaler Protokollversuch mit Godot 4.7.2 und einem zweiten WebSocket-Testclient am Rust-Server war erfolgreich. Godot hat Terrainpakete validiert, selbst gefeuert und beide Geschosse im gemeinsamen Zustand gesehen. Dabei muss die von Godots JSON-Parser gelesene Rundennummer vor dem Senden als Ganzzahl serialisiert werden. Die Probe liegt lokal in `reports/godot-rust-ws-probe.gd` und `reports/godot-rust-ws-probe.mjs`. Die Godot-Spielansicht ist noch nicht an dieses Protokoll angebunden.
