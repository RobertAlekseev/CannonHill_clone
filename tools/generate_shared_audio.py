#!/usr/bin/env python3
"""Synthesise the small, engine-neutral sound effects in shared/assets/audio.

The output is deterministic (fixed seed), so every machine regenerates the
same bytes and the SHA-256 values in asset-manifests/assets.json stay valid.
Usage: python3 tools/generate_shared_audio.py [--manifest]
"""
import hashlib
import json
import math
import random
import struct
import sys
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
AUDIO = ROOT / "shared" / "assets" / "audio"
MANIFEST = ROOT / "asset-manifests" / "assets.json"
RATE = 22050


def envelope(t, attack, decay):
    return min(1.0, t / attack) * math.exp(-t / decay) if attack > 0 else math.exp(-t / decay)


def fire(rng):
    # Short thump: falling sine plus a burst of filtered noise.
    samples, low = [], 0.0
    for i in range(int(RATE * 0.45)):
        t = i / RATE
        low += 0.18 * (rng.uniform(-1, 1) - low)
        tone = math.sin(2 * math.pi * (140 - 160 * t) * t)
        samples.append((0.65 * tone + 0.6 * low) * envelope(t, 0.004, 0.09))
    return samples


def impact(rng):
    # Longer, darker rumble with a trickle of sand on the tail.
    samples, low, lower = [], 0.0, 0.0
    for i in range(int(RATE * 0.9)):
        t = i / RATE
        noise = rng.uniform(-1, 1)
        low += 0.08 * (noise - low)
        lower += 0.02 * (noise - lower)
        boom = (math.sin(2 * math.pi * (70 - 30 * t) * t) + 2.5 * lower) * envelope(t, 0.006, 0.22)
        trickle = 0.25 * low * envelope(t, 0.15, 0.25) * (1 if rng.random() < 0.35 else 0.2)
        samples.append(0.8 * boom + trickle)
    return samples


def write(path, samples):
    peak = max(abs(s) for s in samples) or 1.0
    frames = b"".join(struct.pack("<h", int(32000 * s / peak)) for s in samples)
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(frames)


def main():
    generated = {}
    for name, synth in (("fire", fire), ("impact", impact)):
        path = AUDIO / f"{name}.wav"
        write(path, synth(random.Random(name)))
        generated[name] = path
        print(f"{path.relative_to(ROOT)}  {path.stat().st_size} bytes")
    if "--manifest" in sys.argv:
        data = json.loads(MANIFEST.read_text(encoding="utf-8"))
        for entry in data.get("shared", []):
            path = ROOT / entry["path"]
            if path.is_file():
                entry["sizeBytes"] = path.stat().st_size
                entry["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        MANIFEST.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"updated {MANIFEST.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
