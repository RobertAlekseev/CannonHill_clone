#!/usr/bin/env bash
# macOS/Linux counterpart of Test-Lan.ps1: two headless Godot processes over
# 127.0.0.1, each fires once, both impacts must reach the client.
# Usage: tools/test-lan.sh [path-to-godot]
set -euo pipefail
GODOT="${1:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPORT="$ROOT/reports"
mkdir -p "$REPORT"
HOST_LOG="$REPORT/lan-host.log"
CLIENT_LOG="$REPORT/lan-client.log"
: > "$HOST_LOG"
: > "$CLIENT_LOG"
cleanup() { kill "${HOST_PID:-}" "${CLIENT_PID:-}" 2>/dev/null || true; }
trap cleanup EXIT

"$GODOT" --headless --path "$ROOT/godot" -- --host --smoke > "$HOST_LOG" 2>&1 &
HOST_PID=$!
for _ in $(seq 100); do
  grep -q HOST_READY "$HOST_LOG" && break
  kill -0 "$HOST_PID" 2>/dev/null || { echo "FAIL: host exited before listening"; exit 1; }
  sleep 0.2
done
grep -q HOST_READY "$HOST_LOG" || { echo "FAIL: host did not listen within 20 seconds"; exit 1; }

"$GODOT" --headless --path "$ROOT/godot" -- --join=127.0.0.1 --smoke > "$CLIENT_LOG" 2>&1 &
CLIENT_PID=$!
wait "$CLIENT_PID" || { echo "FAIL: client process failed"; exit 1; }
wait "$HOST_PID" || { echo "FAIL: host process failed"; exit 1; }

fail() { echo "FAIL: $1"; exit 1; }
grep -q "SCRIPT ERROR" "$HOST_LOG" "$CLIENT_LOG" && fail "GDScript runtime error"
grep -q PEER_CONNECTED "$HOST_LOG" || fail "host did not accept client"
grep -q STATE_RECEIVED "$CLIENT_LOG" || fail "client did not receive a world snapshot"
grep -q "SMOKE_FINISHED tick=200 impacts=2" "$HOST_LOG" || fail "expected one shot from each player to impact"
grep -Eq "STATE_RECEIVED tick=[0-9]+ impacts=2" "$CLIENT_LOG" || fail "client did not receive both impacts"
grep -q "EFFECTS fire=2 impact=2" "$CLIENT_LOG" || fail "client did not reconstruct both shots and impacts as effects"
echo "PASS: two Godot processes, authoritative state sync, both players fire, both impacts and their effects reach the client."
