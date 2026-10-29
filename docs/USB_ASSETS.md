# Große Assets ohne GitHub

Der erste Prototyp braucht keine externen Assets. Es werden keine Downloads oder Installationen angestoßen.

Für spätere Pakete:

1. Nur rechtmäßig teilbare Dateien verwenden und Quelle/Lizenz dokumentieren.
2. Paket unveränderlich benennen, z. B. `terrain-cc0-v001`. Inhalt und stabile relative Zielpfade im Manifest festhalten.
3. Für jede Datei Größe und SHA-256 aufnehmen. Paket per USB auf beiden Rechnern unter denselben relativen Pfaden bereitstellen und Prüfsummen vergleichen.
4. Große Dateien vor dem ersten Commit gezielt ignorieren. Kleine eigene Szenen und Referenzen weiter versionieren. `git status` vor jedem Commit prüfen.
5. Ein Paketupdate ist eine neue Version. Ein Rücksprung auf einen alten Git-Commit braucht gegebenenfalls das damalige USB-Paket; Git allein enthält diese Daten nicht.

**Unity:** `.meta`-Dateien gehören zu ihren Assets, ihre GUID darf beim Kopieren nicht neu entstehen. Import-Einstellungen und Referenzen hängen daran. Keine pauschale Ignore-Regel für `.meta` verwenden.

**Godot:** Quelldateien und benötigte `.uid`-Referenzen erhalten, `.godot/`-Cache nicht austauschen.

**Unreal:** `.uasset` und `.umap` sind Projektquellen, nicht einfach regenerierbare Caches. Geometrie, Materialeinstellungen und Referenzen können in derselben Binärdatei liegen. Große Pakete müssen daher samt benötigten importierten Assets konsistent ausgetauscht werden. Kleine eigene Blueprints/Maps gehören weiterhin in die Versionsverwaltung. Nicht den gesamten Content-Ordner ignorieren.

Caches und Builds bleiben lokal. Ein USB-Stick allein ist keine belastbare Sicherung: freigegebene Paketversionen zusätzlich an einem zweiten Ort aufbewahren.
