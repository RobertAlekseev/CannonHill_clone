# Große Assets ohne GitHub

Der Prototyp braucht keine externen Assets; die beiden Sounds in `shared/assets/audio/` sind prozedural erzeugt (`tools/generate_shared_audio.py`) und optional. Es werden keine Downloads oder Installationen angestoßen.

## Gemeinsame Ordnerstruktur

| Ort | Inhalt | In Git |
|---|---|---|
| `shared/assets/<art>/` | Kleine, selbst erstellte oder frei lizenzierte Dateien (Audio, kleine Texturen) | Ja |
| `external-assets/<paket>-vNNN/` | Große USB-Pakete, unveränderlich pro Version | Nein |
| `asset-manifests/assets.json` | ID, Pfad, Größe, SHA-256, Quelle, Lizenz für beides | Ja |

Engines verweisen per **ID** auf das Manifest, nicht auf eigene Kopien. Godot (`godot/shared_assets.gd`) lädt zur Laufzeit aus diesen Ordnern. Unity und Unreal können dieselben Pfade später z. B. über einen Import-/Sync-Schritt oder Laufzeitladen nutzen; Engine-Importdaten (`.meta`, `.uasset`, `.import`) entstehen dann nur im jeweiligen Engineordner und gelten nicht als Quelle.

Manifest-Format für Pakete:

```json
{"name": "terrain-cc0-v001", "source": "...", "license": "CC0",
 "files": [{"id": "texture.sand", "path": "textures/sand.png", "sizeBytes": 1234, "sha256": "..."}]}
```

Datei liegt dann unter `external-assets/terrain-cc0-v001/textures/sand.png`.

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
