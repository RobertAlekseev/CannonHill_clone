#!/usr/bin/env bash
# macOS/Linux counterpart of Test-Lan.ps1 and Test-GodotHealthLan.ps1: pairs of
# headless Godot processes over 127.0.0.1.
#  1. Scene smoke: each player fires once, both impacts and effects reach the client.
#  2. Health: five direct hits over TCP, damage, winner and host restart replicate.
#  3. Weapons: both choose Mega (client choice travels as input), splits replay.
# Usage: tools/test-lan.sh [path-to-godot]
set -euo pipefail
GODOT="${1:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPORT="$ROOT/reports"
mkdir -p "$REPORT"
HOST_PID=""
CLIENT_PID=""
cleanup() { kill $HOST_PID $CLIENT_PID 2>/dev/null || true; }
trap cleanup EXIT
fail() { echo "FAIL: $1"; exit 1; }

# run_pair <name> <extra godot args...>; host gets --host, client --join.
run_pair() {
  local name="$1"; shift
  HOST_LOG="$REPORT/$name-host.log"
  CLIENT_LOG="$REPORT/$name-client.log"
  "$GODOT" --headless --path "$ROOT/godot" "$@" --host > "$HOST_LOG" 2>&1 &
  HOST_PID=$!
  for _ in $(seq 100); do
    grep -q HOST_READY "$HOST_LOG" && break
    kill -0 "$HOST_PID" 2>/dev/null || fail "$name: host exited before listening"
    sleep 0.2
  done
  grep -q HOST_READY "$HOST_LOG" || fail "$name: host did not listen within 20 seconds"
  "$GODOT" --headless --path "$ROOT/godot" "$@" --join=127.0.0.1 > "$CLIENT_LOG" 2>&1 &
  CLIENT_PID=$!
  wait "$CLIENT_PID" || fail "$name: client process failed"
  wait "$HOST_PID" || fail "$name: host process failed"
  HOST_PID=""
  CLIENT_PID=""
  grep -q "SCRIPT ERROR" "$HOST_LOG" "$CLIENT_LOG" && fail "$name: GDScript runtime error"
  return 0
}

run_pair lan -- --smoke
grep -q PEER_CONNECTED "$HOST_LOG" || fail "host did not accept client"
grep -q STATE_RECEIVED "$CLIENT_LOG" || fail "client did not receive a world snapshot"
grep -q "SMOKE_FINISHED tick=200 impacts=2" "$HOST_LOG" || fail "expected one shot from each player to impact"
grep -Eq "STATE_RECEIVED tick=[0-9]+ impacts=2" "$CLIENT_LOG" || fail "client did not receive both impacts"
grep -q "EFFECTS fire=2 impact=2" "$CLIENT_LOG" || fail "client did not reconstruct both shots and impacts as effects"
echo "PASS: scene smoke, both players fire, both impacts and their effects reach the client."

run_pair health-lan --script res://tests/health_lan_peer.gd --
grep -q HOST_HEALTH_PASS "$HOST_LOG" || fail "host did not verify damage and winner"
grep -q "CLIENT_HEALTH_PASS damage=true victory=true restart=true" "$CLIENT_LOG" || fail "client did not verify damage, winner and restart"
echo "PASS: health over TCP, 1000->800->0 HP, winner and host restart replicate to the client."

run_pair weapons-lan -- --smoke --weapon=3
grep -q "SMOKE_FINISHED tick=200 impacts=12" "$HOST_LOG" || fail "expected both Mega shots to split into six splinters each"
grep -q "EFFECTS fire=2 impact=12 snow=0 heal=0 shield=0 split=2" "$CLIENT_LOG" || fail "client did not replay both Mega splits and all twelve splinter impacts"
echo "PASS: weapon choice over TCP, both players fire Mega, all splits and impacts replay on the client."
