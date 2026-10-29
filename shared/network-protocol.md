# LAN protocol v1

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
