# CH-001 · Rust-Web-Sand unter Last

- **Phase** Erledigt
- **Zuständig** Robert und der Coding-Agent dieses Projekts
- **Nächster Schritt** Bei einem konkreten Ziel für größere Karten die Ticks mit bewegtem Sand separat profilieren.

## Research

Die Standardkarte hat 240 × 128 Zellen. Der größere Testbuild hat 960 × 512 Zellen, also die sechzehnfache Fläche. Der Beschusstest nutzt die regulären Kanonen. Ein zusätzlicher synthetischer Lastfall füllt vor jedem Tick auf 32 Geschosse nahe der Mitte auf. Der Test misst Simulation in Node mit festem Seed, ohne Canvas und ohne Netzwerk.

Die Vollscan-Referenz zeigte auf der großen Karte selbst in Ruhe mehrere Millisekunden pro Tick. Das Sandraster wird auch dann vollständig gelesen, wenn keine Zelle mehr rutschen kann.

## Plan

Nach einem vollständigen Durchlauf ohne Bewegung die Rastersuche aussetzen. Wenn ein Krater Sand entfernt, die Suche im nächsten Tick wieder aufnehmen. Solange Sand rutscht, dieselbe Reihenfolge und dieselben Regeln verwenden.

Abnahme: Weniger Simulationszeit in Ruhe. Terrain, Kanonen, Geschosse, Kiste und Rundenergebnis müssen in allen Vergleichsticks mit dem Referenzbuild übereinstimmen.

## Implement

`rust-web/src/lib.rs` merkt sich, ob Sand noch aktiv ist. Die Benchmark-Features erlauben die größere Karte, künstlichen Beschuss und einen erzwungenen Vollscan als Referenz. Diese Funktionen sind auf Benchmark-Builds beschränkt.

Der normale Browser-Build lässt sich mit `.\rust-web\Start.ps1 -BuildOnly` bauen. Für einen reproduzierbaren Vergleich der großen Karte im Projektordner:

```powershell
cargo rustc --locked --manifest-path rust-web/Cargo.toml --release --target wasm32-unknown-unknown --features bench-large,bench-full-scan --lib -- -C link-arg=-z -C link-arg=stack-size=4194304
Copy-Item rust-web/target/wasm32-unknown-unknown/release/cannon_hill_web.wasm rust-web/target/baseline-large.wasm
cargo rustc --locked --manifest-path rust-web/Cargo.toml --release --target wasm32-unknown-unknown --features bench-large --lib -- -C link-arg=-z -C link-arg=stack-size=4194304
Copy-Item rust-web/target/wasm32-unknown-unknown/release/cannon_hill_web.wasm rust-web/target/optimized-large.wasm
node rust-web/benchmark.mjs rust-web/target/optimized-large.wasm rust-web/target/baseline-large.wasm
```

Für die Standardgröße `bench` und `bench-full-scan` verwenden, ohne zusätzliche Stack-Einstellung. Der normale Browser-Build liegt getrennt unter `dist/`.

## Review

Stand-PC, Xeon X5670, WebAssembly-Release. Je 1.500 Ticks pro Szenario und Build, Referenz und Änderung im selben Lauf gemessen. Zeiten in Millisekunden pro Tick.

| Karte | Last | p50 vorher → nachher | p95 vorher → nachher |
| --- | --- | ---: | ---: |
| 240 × 128 | Ruhe | 0,259 → 0,001 | 0,428 → 0,001 |
| 240 × 128 | Beschuss | 0,201 → 0,177 | 0,367 → 0,348 |
| 240 × 128 | 32 Geschosse | 0,159 → 0,140 | 0,294 → 0,299 |
| 960 × 512 | Ruhe | 3,878 → <0,001 | 5,230 → 0,001 |
| 960 × 512 | Beschuss | 3,962 → 3,880 | 5,304 → 5,522 |
| 960 × 512 | 32 Geschosse | 3,916 → 0,005 | 5,224 → 5,386 |

Der Gewinn kommt aus ausgelassenen Scans bei ruhendem Gelände. Die p95-Zeiten unter Last zeigen keinen verlässlichen Gewinn, wenn Sand weiter in Bewegung bleibt. Für alle sechs Szenarien stimmten Gelände und sichtbarer Zustand in jeweils 300 Ticks mit der ursprünglichen Vollscan-Referenz überein. Der normale WebAssembly-Build und sein Benchmark liefen erfolgreich. Die Ergebnisse belegen Simulationszeiten auf diesem Rechner, keine FPS oder LAN-Leistung.
