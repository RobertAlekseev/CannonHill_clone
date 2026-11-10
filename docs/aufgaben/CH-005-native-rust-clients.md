# CH-005 · Unity und Unreal am gemeinsamen Rust-Server

- **Phase** Erledigt
- **Nächster Schritt** Auf macOS und mit einem zweiten Gerät im Heimnetz spielen.

## Research und Plan

Godot und der Browser verwenden bereits Rust-WebSocket v1. Unity und Unreal sollen die gleichen Serverzustände darstellen und Eingaben an den Rust-Server senden. Die bisherigen Spielmodi bleiben über ihre üblichen Einstiege erreichbar. Der Checkout soll auf dem Mac einen Startbefehl für Safari bereitstellen.

## Implement

Unity verbindet über das Adressfeld oder `--rust-server=ws://HOST-IP:8000/ws`. Unreal nimmt `-RustServer=ws://HOST-IP:8000/ws` an. Beide Clients übernehmen Terrain, Kanonen, Geschosse und Kisten aus den Schnappschüssen. Spieler 1 darf die Runde neu starten. Die Serverpartie verwendet den Rust-Regelsatz mit einer Standardwaffe.

## Review

Unity 6000.6.3f1 als Windows-Player und Unreal 5.8 als Development Editor wurden gebaut. Beide nativen Spielprozesse haben jeweils gegen einen WebSocket-Testclient am Rust-Server gespielt. Beide Schüsse, Abwurfvorwarnung und Kiste waren sichtbar. Ein direkter Test mit Unity als Spieler 1 und Unreal als Spieler 2 bestand ebenfalls. Beide sahen die zwei Schüsse, Vorwarnung und Kiste in derselben Partie. Der Rust-Web-LAN-Test hat Pause, Wiederbeitritt und Neustart erneut bestätigt. Er prüft auch, dass ein Browser-Origin ohne passenden Port abgelehnt wird.

Der macOS-Startbefehl wurde im Windows-Shell-Test bis zum WebAssembly-Build geprüft. Native Mac-Builds, Safari und der Spieltest auf zwei physischen Geräten stehen aus.
