# LAN protocol v1

**Scope:** This documents the initial Unity/Unreal protocol and the historical Godot baseline. Current Godot uses the v2 extension below; v1 and v2 instances are not compatible. Unity and Unreal are intentionally unchanged while Godot is the focus.

TCP 28741, one host / one client, newline-delimited UTF-8 JSON. Only ASCII field values in v1. Maximum buffered input: 262144 bytes. Second clients are rejected. Host owns simulation; clients never submit terrain or player IDs. No authentication; trusted LAN only. No changes to firewall or router settings.

Messages are bounded by `\n`, not socket read boundaries. Senders retain incomplete writes; at most one pending message, dropping stale snapshots rather than building an unbounded queue. 10 Hz state/input target; simulation 30 Hz. Clients do not predict or interpolate yet.

Client → host:

```json
{"type":"input","version":1,"angle":45,"power":55,"fire":true}
```

Host applies this only to player index 1, clamps angle/power and enforces cooldown. Host controls index 0. Fire is an event retained until it can be queued.

Host → client:

```json
{"type":"state","version":1,"tick":90,"impacts":0,"cells":"BASE64","cannons":[{"x":40,"y":80,"vy":0,"angle":45,"power":55,"cooldown":0,"tilt":0},{"x":200,"y":80,"vy":0,"angle":45,"power":55,"cooldown":0,"tilt":0}],"shots":[{"x":70,"y":50,"vx":38.89,"vy":-10,"age":0.73}]}
```

`cells`: exactly 30720 bytes, row-major top-to-bottom; 0 air / 1 sand / 2 rock. `cannons`: exactly two. `shots`: maximum 32. Coordinates and velocities follow gameplay-spec.md. Array order assigns cannon ownership. State snapshots contain the complete world, supporting mid-game join and reconnect. Engine differences do not accumulate on clients because only the host integrates physics.

One full state is about 42 kB, approximately 0.42 MB/s at 10 Hz. This deliberately simple prototype protocol prioritizes correctness over bandwidth; compression/deltas and interpolation are later tasks. Interoperability must be tested in both directions before a pairing is declared supported.

## Godot v2: health and round state

The framing and host authority remain the same. Both input and state messages carry `version: 2`. Godot disconnects peers sending other versions and displays a version mismatch message. It does not silently substitute full health for missing fields.

Each cannon adds `hp` (0..1000), `max_hp` (1000), and `hit_flash` (seconds). State also adds `round_over` (boolean), `winner` (-1 for no winner or draw, otherwise zero-based winner), and `moved` (moving sand count). `round_over` distinguishes an ongoing game from a draw.

Only host snapshots set HP or the result. Client input still contains only angle, power and fire. Restart snapshots are complete and may move `tick` back to zero. Receivers validate the new fields before replacing state. JSON numeric decoding must accept integer-valued floats, as Godot JSON uses floats for parsed numbers.

Current supported pairing: Godot v3 ↔ Godot v3 (v2 is superseded). All other health pairings need a later implementation and new tests.

## Godot v3: rigid-body cannons

Same as v2 with `version: 3`. Each cannon additionally carries `vx` and `spin` (rad/s) and `tipped_time` (seconds lying tipped). `tilt` is now the full chassis rotation in rad, wrapped to -π..π (positive = clockwise on screen), no longer a visual value clamped to ±0.5. `angle` stays the barrel angle relative to the chassis. Clients apply the host values unchanged; only the host runs the solver from shared/physics-proposal-p1.md. Snapshots missing any of these fields are rejected.
