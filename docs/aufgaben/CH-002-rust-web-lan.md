# CH-002 · Rust-Web-LAN, Framezeiten und Buff-Vorwarnung

- **Phase** Erledigt
- **Nächster Schritt** Auf zwei physischen Rechnern im Heimnetz spielen.

## Research und Plan

Zwei Browser sollen dieselbe Partie über einen Host im Heimnetz spielen. Der Host soll Eingaben, Gelände, Treffer und Buffs zentral berechnen. Zur Abnahme gehören zwei Schüsse, Geländeabgleich, Pause bei Trennung, Wiederbeitritt und Neustart. Framezeit und LAN-Datenmenge werden getrennt gemessen.

## Umsetzung

Der native Server nutzt dieselbe Rust-Simulation wie die lokale WebAssembly-Fassung. Er verteilt bis zu 15 Zustände pro Sekunde und schickt Gelände nur bei Änderung. Die Geländepakete fassen Folgen gleicher Zellen zusammen. Bei stärkerer Fragmentierung kann der Host die Zellen direkt senden. In beiden Modi markiert das Spiel eine Sekunde vor dem Abwurf die Fallposition.

## Review

WebAssembly- und nativer Release-Build bestanden. Der WebSocket-Test prüfte beide Schüsse, synchronisierte Einschläge, den dritten Verbindungsversuch, Pause, Wiederbeitritt, den Host-Neustart sowie Kiste und Abwurfposition. Unter dem geskripteten beidseitigen Beschuss sank die gemessene Nutzdatenrate pro Gast von 236,4 auf 7,2 kB/s. Die Messung erfasst die Daten in den WebSocket-Nachrichten und schließt Transport-Overhead aus.

Zwei getrennte Chromium-Instanzen spielten lokal mit sieben gleichzeitig beobachteten Geschossen. Die p95-Framezeit betrug je 16,8 ms. Die Zeichenzeit lag bei p95 0,5 ms. Offline lagen die p95-Framezeit bei 16,8 ms, die JavaScript-seitig gemessene Zeichenzeit bei 0,6 ms und die Simulation bei 0,3 ms. Das sind kurze Headless-Messungen am Stand-PC. Browser-Rendering und GPU-Arbeit außerhalb der JavaScript-Messung sind in der Zeichenzeit nicht vollständig enthalten.

Ein Spieltest über zwei physische Rechner und ein Test in Safari stehen aus.
