# LAN protocol v1

**Scope:** This documents the initial Unity/Unreal protocol and the historical Godot baseline. Current builds use Unity v5, Unreal v6 and Godot v4. Godot v2 below describes the historical health baseline.

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

Historical supported pairing: Godot v2 ↔ Godot v2. All other health pairings need a later implementation and new tests.


## Unreal v3: driving and weapons

The historical Unreal v3 builds sent version 3 exclusively. They do not interoperate with v1 or Godot v2. Input adds `drive` (-1..1, A/D) and `weapon` (0 standard, 1 heavy, 2 quick). The host clamps both and stores driving input for at most 0.35 seconds without refresh. Driving advances in fixed simulation steps; airborne cannons and steep upward steps block propulsion. Cannon and shot snapshots add `weapon`; shots retain their firing weapon when the player changes selection. Explosion radii are 10/16/5 cells; cooldowns 0.7/1.4/0.3 seconds. Unreal v3 does not include Godot health fields.


## Godot v4: falling buffs

Both peers must run v4. The host advances drops at 30 Hz and awards them on projectile contact. State adds `drop` (empty object or `x`, `y`, `kind`), `last_buff_player`, `last_buff_kind` and `buff_notice` (seconds). Cannon objects add `shield` and `rapid` in seconds. Shot objects include their firing player as `owner`. Kind 0 repairs, 1 shields and 2 speeds up reloading. Inputs retain the v2 shape with the version set to 4.


## Unity v5 and Unreal v6: health and falling buffs

Both versions use the same pickup rules as Godot v4. Their state adds `roundOver`, `winner`, cannon `hp`, `shield`, `rapid` and shot `owner`. Unity sends `hasDrop` and a `drop` object. Unreal sends `dropKind` (-1 when absent), `dropX` and `dropY`. The host owns pickup and damage. Each engine requires a matching peer build.


Unreal v6 applies the receive size limit to each newline-delimited message. Multiple valid snapshots can arrive together while a guest is loading. The current Unreal client parses complete lines before checking the remaining fragment.

## Shared Rust-WebSocket v1

The Rust server sends `protocol: 1` in its welcome message and snapshots. The browser and the Godot, Unity and Unreal Rust clients use this connection. Welcome assigns `player`. Snapshots carry `tick`, `round`, `players`, `result`, `revision`, `cannons`, `shots`, `drop` and `warning`. Cannon arrays contain x, y, angle, power, HP, shield seconds and rapid-fire seconds. Shot arrays contain x and y. Drop is null or [kind, x, y]. Warning is the next crate's x coordinate, or -1.

Terrain precedes the snapshot whenever its revision changes. Binary type 0 is one byte followed by 30,720 raw cells. Type 1 is followed by repeated [count, cell] byte pairs. Runs must decode to exactly 30,720 cells, with cell values 0..2 and positive counts.

Clients send input with type, integer round, angle, power and fire. Host restart sends type restart and integer round. The server assigns ownership by socket and gates input on the current round. Godot converts JSON-parsed round values to integers before sending.

Unreal's native handshake identifies itself with `X-Cannon-Hill-Native: 1`. For that client only, the server also accepts the same hostname without a port in the Origin header. Browser origins still have to match the full host and port.
