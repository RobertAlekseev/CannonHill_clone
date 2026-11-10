import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { setTimeout as delay } from "node:timers/promises";
import { createHash } from "node:crypto";

if (!process.argv[2]) throw new Error("Godot-Konsolen-EXE als Argument angeben.");
const root = new URL("../", import.meta.url);
const executable = new URL(process.platform === "win32"
    ? "./target/release/cannon-hill-lan.exe" : "./target/release/cannon-hill-lan", import.meta.url);

async function waitFor(check, description, milliseconds = 15000) {
    const deadline = performance.now() + milliseconds;
    while (performance.now() < deadline) {
        if (check()) return;
        await delay(10);
    }
    throw new Error(description);
}

function decode(buffer) {
    const bytes = new Uint8Array(buffer);
    if (bytes[0] === 0) return bytes.subarray(1);
    assert.equal(bytes[0], 1);
    const result = new Uint8Array(240 * 128);
    let offset = 0;
    for (let i = 1; i < bytes.length; i += 2) {
        result.fill(bytes[i + 1], offset, offset + bytes[i]);
        offset += bytes[i];
    }
    assert.equal(offset, result.length);
    return result;
}

async function run(godotPlayer) {
    const server = spawn(fileURLToPath(executable), ["127.0.0.1:0"], { windowsHide: true });
    let serverLog = "", output = "", exit, socket, godot, peerPlayer = -1, fired = false;
    const hashes = new Map();
    let pendingTerrain, terrain;
    server.stdout.on("data", data => { serverLog += data; });
    server.stderr.pipe(process.stderr);
    function launchGodot(address) {
        godot = spawn(process.argv[2], ["--headless", "--path", fileURLToPath(new URL("godot", root)),
            "--script", "res://tests/rust_scene.gd", "--", "--rust-server=" + address], { windowsHide: true });
        godot.stdout.on("data", data => {
            output += data;
            if (godotPlayer === 1 && output.includes("MIXED_PLAY_PASS") && frame?.players === 2 && !restarted) {
                restarted = true;
                socket.send(JSON.stringify({ type: "restart", round: frame.round }));
            }
        });
        godot.stderr.on("data", data => { output += data; process.stderr.write(data); });
        godot.on("error", error => { output += error; exit = 1; });
        godot.on("exit", code => { exit = code; });
    }
    let frame, restarted = false;
    try {
        await waitFor(() => serverLog.match(/http:\/\/127\.0\.0\.1:\d+/), "Rust-Server fehlt.");
        const address = serverLog.match(/http:\/\/127\.0\.0\.1:\d+/)[0].replace("http:", "ws:") + "/ws";
        if (godotPlayer === 0) {
            launchGodot(address);
            await waitFor(() => output.includes("MIXED_READY player=0"), "Godot-Platz fehlt.");
        }
        socket = new WebSocket(address);
        socket.binaryType = "arraybuffer";
        socket.onmessage = ({ data }) => {
            if (typeof data !== "string") { pendingTerrain = decode(data); return; }
            const message = JSON.parse(data);
            assert.equal(message.protocol, 1);
            if (message.player !== undefined) { peerPlayer = message.player; return; }
            frame = message;
            if (pendingTerrain) { terrain = pendingTerrain; pendingTerrain = undefined; }
            if (terrain) {
                const hash = createHash("sha256").update(Buffer.from(terrain).toString("hex")).digest("hex");
                hashes.set(frame.revision, hash);
            }
            if (frame.players === 2 && !fired) {
                fired = true;
                socket.send(JSON.stringify({ type: "input", round: frame.round, angle: 43, power: 55, fire: true }));
            }
        };
        await waitFor(() => peerPlayer >= 0, "WebSocket-Platz fehlt.");
        assert.equal(peerPlayer, 1 - godotPlayer);
        if (godotPlayer === 1) launchGodot(address);
        await waitFor(() => exit !== undefined, "Godot-Szene beendet Test nicht.", 28000);
        assert.equal(exit, 0, output);
        assert.ok(!output.includes("SCRIPT ERROR"), output);
        const match = output.match(/MIXED_PLAY_PASS player=(\d) revision=(\d+) hash=([a-f0-9]+)/);
        assert.ok(match, output);
        assert.equal(Number(match[1]), godotPlayer);
        assert.equal(hashes.get(Number(match[2])), match[3]);
        assert.match(output, /MIXED_SCENE_PASS.*restart=true reconnect=true/);
        console.log(`PASS: Godot-Spielszene als Spieler ${godotPlayer + 1}, beide Schüsse, identisches Terrain, Vorwarnung, Kiste, Neustart und Wiederverbindung`);
    } finally {
        socket?.close();
        godot?.kill();
        server.kill();
    }
}

await run(0);
await run(1);
