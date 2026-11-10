# Cannon Hill im Browser

Eigenständiger Prototyp für zwei Spieler an einer Tastatur oder in zwei Browsern im Heimnetz. Der Rust-Kern berechnet Sand, Geschosse, Treffer und Buffs mit 30 Schritten pro Sekunde. JavaScript übernimmt Eingaben und Canvas 2D. Die WebAssembly-Fassung nutzt direkte Exporte. Der optionale LAN-Server verwendet Axum und Tokio.

## Start unter Windows

Voraussetzungen: Rust mit Cargo, das WebAssembly-Ziel und Python 3 für den lokalen Entwicklungsserver.

```powershell
rustup target add wasm32-unknown-unknown
.\rust-web\Start.ps1
```

Im Browser `http://127.0.0.1:8000` öffnen. `-Port 8080` wählt einen anderen Port. Mit `-BuildOnly` landen die statischen Dateien in `dist/`.

Ins Spielfeld klicken. Pfeile stellen Winkel und Stärke ein, Leertaste feuert und Tab wechselt die Kanone. Der Wechsel ist auch per Schaltfläche möglich. Jede Kanone startet mit 1.000 LP. Eine Kiste fällt alle fünf Sekunden. Ein Treffer bringt bis zu 150 LP Reparatur, acht Sekunden Schild oder acht Sekunden Schnellfeuer. Eine Sekunde vor dem Abwurf markiert ein Pfeil am oberen Rand die Fallposition.

## Im Heimnetz spielen

Am Host im Projektordner:

```powershell
.\rust-web\Start.ps1 -Lan
```

Der erste Browser öffnet `http://127.0.0.1:8000`. Der zweite öffnet dieselbe Portnummer mit der IPv4-Adresse des Hosts im Heimnetz. Die Adresse steht am Host unter `ipconfig`. Bei einem anderen Port `-Port 8080` angeben. Falls Windows nachfragt, kann der Host den Zugriff im privaten Netz erlauben.

Die Reihenfolge beim Beitritt vergibt die zwei Kanonen. Nur Spieler 1 kann die Runde neu starten. Die Partie pausiert bei einer Trennung. Der getrennte Browser versucht sich erneut zu verbinden, und der nächste freie Platz wird vergeben. Wenn beide Spieler weg waren, entscheidet die Reihenfolge beim Wiederbeitritt über die Plätze.

## Lokal prüfen

```powershell
.\rust-web\Start.ps1 -BuildOnly
cargo build --locked --manifest-path rust-web/Cargo.toml --release --features lan --bin cannon-hill-lan
node .\rust-web\lan-smoke.mjs
```

Der Test braucht Node mit WebSocket-Client. Er startet und beendet seinen eigenen Server auf einem freien Loopback-Port. Mit `?perf=1` oder im LAN mit `?lan=1&perf=1` liefert `cannonHillPerformance()` in der Browser-Konsole Framezeit, Simulationszeit, Zeichenzeit und Terrain-Updates. Die Stichprobe enthält die letzten maximal 600 Frames.

## Gemischte Partie mit nativen Clients

Den Server mit `.\rust-web\Start.ps1 -Lan` starten. Im Godot-Spiel in das Adressfeld `ws://HOST-IP:8000/ws` eintragen und **Verbinden** wählen. Der Browser öffnet `http://HOST-IP:8000`. Die erste Verbindung erhält Spieler 1, die zweite Spieler 2. Spieler 1 kann die Runde neu starten. Beide sehen denselben Server-Spielstand.

Godot lässt sich auch direkt verbinden:

```powershell
godot --path .\godot -- --rust-server=ws://127.0.0.1:8000/ws
```

Der Integrationstest mit der echten Godot-Spielszene prüft beide Rollen. Als Argument die Godot-Konsolen-EXE angeben:

```powershell
node .\rust-web\mixed-smoke.mjs "C:\Pfad\zu\Godot_console.exe"
```

In Unity dieselbe WebSocket-Adresse eingeben und **Verbinden** wählen. Der Unity-Player akzeptiert auch `--rust-server=ws://HOST-IP:8000/ws`. Unreal als Spiel starten und `-RustServer=ws://HOST-IP:8000/ws` übergeben. In Unreal löst **R** den Neustart für Spieler 1 aus. Der gemeinsame Server bietet die Standardwaffe. Fahrsteuerung und Waffenwahl gehören zum separaten Unreal-Spielmodus.

## Auf dem Mac mit Safari spielen

Wenn ein anderer Rechner im Heimnetz schon hostet, in Safari `http://HOST-IP:8000` öffnen. Wenn der Mac selbst hostet, im Checkout mit installierter Rust-Toolchain ausführen:

```sh
rustup target add wasm32-unknown-unknown
sh rust-web/start.sh --lan
```

Auf dem Host dann `http://127.0.0.1:8000` öffnen. Weitere Geräte verwenden die LAN-IP des Hosts. Für zwei Kanonen an einer Tastatur kann der Mac mit `sh rust-web/start.sh --offline` und Python 3 starten.
