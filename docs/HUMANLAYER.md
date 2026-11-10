# Lokale Projektbetreuung für Cannon Hill

Wir nutzen Research → Plan → Implement → Review direkt im Checkout. Die Aufgabenübersicht und die einzelnen Aufgabennotizen sind der gemeinsame Stand für Robert und Coding-Agenten. Sie lassen sich in Codex oder in einem Texteditor öffnen. Für diesen Ablauf ist kein HumanLayer-Konto nötig.

## Einstieg

Die [Aufgabenübersicht](aufgaben/README.md) zeigt, was läuft, was zur Prüfung bereitliegt und was als Nächstes ansteht. Öffne die dort verlinkte Aufgabe und lies ihren letzten Stand. Ein neuer Chat kann mit der Aufgabennummer oder dem Dateipfad übernehmen.

Für eine neue Aufgabe kopiere [die Vorlage](aufgaben/VORLAGE.md), vergib die nächste Nummer und trage die Datei in die Übersicht ein. Aktualisiere den Eintrag, sobald sich die Phase oder der nächste Schritt ändert. Bei mehreren Beteiligten stimmen wir Zuständigkeiten im bestehenden GitHub-Prozess ab.

| Phase | Was in der Aufgabennotiz steht |
| --- | --- |
| Research | Ausgangslage, Reproduktion, Codepfade und Messwerte |
| Plan | Ziel, betroffene Dateien, Abnahmekriterien und Testschritte |
| Implement | Änderungen, ausgeführte Prüfungen und offene Punkte |
| Review | Ergebnis, Vorher-Nachher-Vergleich und gegebenenfalls anstehender Spieltest |
| Erledigt | Abnahme oder Abschluss samt verbleibenden Grenzen |

Bei einer Frage für die Abnahme hält der Agent den konkreten Prüfpunkt und den bis dahin erreichten Stand fest. Nach einer Entscheidung trägt er Ergebnis und nächsten Schritt nach. Bei kleinen Änderungen reichen je Phase ein oder zwei Sätze.

## Performance bei Spielen

Simulation, Rendering und Netzwerk getrennt messen. Vergleiche denselben Lastfall im selben Build-Modus auf derselben Maschine. Für Simulation sind Tickzeiten relevant, für die Darstellung Framezeiten und für LAN Latenz und Datenrate. Die aktuelle Referenzmessung und die nächsten Schritte stehen in [CH-001](aufgaben/CH-001-rust-web-sand.md).

## Einordnung der früheren Installation

Die früher geprüfte HumanLayer-CLI liegt im ignorierten Ordner `reports/humanlayer-cli/`. Sie ist für die lokale Projektbetreuung nicht erforderlich. Die lokale Aufgabenübersicht hat keine Anbindung an HumanLayer. Wenn du einen Coding-Agenten nutzt, gelten dessen eigene Einstellungen zur Datenverarbeitung.
