# Cannonhill: belegte Waffen und Hilfsmittel

Die [Entwicklerseite von Dirk Plate](https://dplate.de/games/cannonhill) beschreibt das Echtzeitspiel mit bis zu vier Bunkern und verlinkt den [SDL-Port von Alexander](https://github.com/univrsal/cannonhill-sdl). Recherche: 29.10.2026. Die Bezeichnungen unten sind aus dessen Quellcode sinngemäß ausgeschrieben; exakte historische Shop-Beschriftungen sind nicht für jeden Eintrag bestätigt.

| Typ | Quellcode-Kennung | Einordnung |
|---|---|---|
| Stein | `MUNSTEIN` | Kostenloses Grundgeschoss |
| Rakete | `MUNRAKETE` | Explosivgeschoss |
| Granate | `MUNGRANATE` | Granatenmunition |
| Laser | `MUNLASER` | Strahlenwaffe |
| Gewehr | `MUNGEWEHR` | Gewehrmunition |
| Säurefass | `MUNFASS` | Setzt Säure frei |
| Magnetrakete | `MUNMAGRAKETE` | Besondere Raketenvariante |
| Mega-Geschoss | `MUNMEGA` | Verteilt acht gemischte Untergeschosse |
| Schneeball | `MUNSCHNEEBALL` | Erzeugt Schneematerial |
| Schild | `MUNSCHILD` | Schutzmittel |
| Medipack | `MUNMEDI` | Heilung |
| Magnetfeld | `MUNMAGNET` | Magnet-Hilfsmittel |

Zusätzlich gibt es intern `MUNSPLITTER`: Splittergeschosse, die im normalen Shop nicht separat angeboten werden.

Belege: [Munitionskennungen und 1.000 maximale Lebenspunkte](https://github.com/univrsal/cannonhill-sdl/blob/master/panzer.h#L199-L214), [Parameter und Effekte](https://github.com/univrsal/cannonhill-sdl/blob/master/panzer.cpp#L1196-L1269), [Säure, Mega und Schnee](https://github.com/univrsal/cannonhill-sdl/blob/master/panzer.cpp#L4815-L4926), [Shop-Schleife](https://github.com/univrsal/cannonhill-sdl/blob/master/panzer.cpp#L5055-L5059). Die Lebenspunkte-Konstante steht separat in `panzer.h`, Zeile 50.

## Aktuelle Umsetzung

Godot erhält zunächst **ein** Standardgeschoss und 1.000 Lebenspunkte pro Kanone. Höchstens 200 Schaden, Distanzabfall, Selbstschaden und runde Hitboxen sind eigene Prototypregeln. Die Waffenliste ist eine Referenz für spätere Arbeit, keine bereits implementierte Waffenauswahl. Fremder Quellcode oder Originalassets wurden nicht übernommen.
