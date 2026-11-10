import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { get } from "node:http";
import { isIPv4 } from "node:net";
import { fileURLToPath } from "node:url";
import { setTimeout as delay } from "node:timers/promises";

const executable = new URL(process.platform === "win32"
    ? "./target/release/cannon-hill-lan.exe" : "./target/release/cannon-hill-lan", import.meta.url);
const address = process.argv[2] ?? "127.0.0.1";
assert.ok(isIPv4(address), "Eine lokale IPv4-Adresse angeben.");
const server = spawn(fileURLToPath(executable), [`${address}:0`], { windowsHide: true });
const sockets = [];
server.stderr.pipe(process.stderr);

async function until(predicate, description, timeout = 8000) {
    const deadline = performance.now() + timeout;
    while (performance.now() < deadline) {
        const result = predicate();
        if (result) return result;
        await delay(10);
    }
    throw new Error(description);
}

function connect(address) {
    const socket = new WebSocket(address);
    sockets.push(socket);
    socket.binaryType = "arraybuffer";
    const peer = { socket, player: -1, terrain: 0, bytes: 0 };
    socket.onmessage = ({ data }) => {
        if (typeof data !== "string") {
            peer.terrain++;
            peer.bytes += data.byteLength;
            const bytes = new Uint8Array(data);
            if (bytes[0] === 0) assert.equal(bytes.length, 240 * 128 + 1);
            else {
                assert.equal(bytes[0], 1);
                assert.equal(bytes.length % 2, 1);
                let cells = 0;
                for (let i = 1; i < bytes.length; i += 2) {
                    assert.ok(bytes[i] > 0 && bytes[i + 1] <= 2);
                    cells += bytes[i];
                }
                assert.equal(cells, 240 * 128);
            }
            return;
        }
        peer.bytes += Buffer.byteLength(data);
        const message = JSON.parse(data);
        if (message.player !== undefined) peer.player = message.player;
        else peer.frame = message;
    };
    return peer;
}

try {
    let output = "";
    server.stdout.on("data", data => { output += data; });
    let failed;
    server.on("error", error => { failed = error; });
    const url = await until(() => {
        if (failed) throw failed;
        if (server.exitCode !== null) throw new Error("LAN-Server beendet.");
        return output.match(/http:\/\/[\d.]+:\d+/)?.[0];
    }, "LAN-Server startet nicht.");
    assert.equal(new URL(url).hostname, address);
    const response = await fetch(url);
    assert.equal(response.status, 200);
    assert.match(response.url, /lan=1$/);
    assert.match(await response.text(), /Cannon Hill/);
    const wrongOrigin = await new Promise((resolve, reject) => {
        const request = get(url + "/ws", { headers: {
            Connection: "Upgrade", Upgrade: "websocket",
            "Sec-WebSocket-Version": "13", "Sec-WebSocket-Key": "dGhlIHNhbXBsZSBub25jZQ==",
            Origin: `http://${address}`,
        } }, response => { response.resume(); resolve(response.statusCode); });
        request.on("upgrade", (_response, upgraded) => { upgraded.destroy(); resolve(101); });
        request.on("error", reject);
    });
    assert.equal(wrongOrigin, 403, "Browser-Origin ohne Host-Port wurde akzeptiert.");
    const ws = url.replace("http:", "ws:") + "/ws";
    const host = connect(ws);
    await until(() => host.player === 0 && host.frame?.players === 1 && host.terrain === 1, "Host fehlt.");
    const guest = connect(ws);
    await until(() => guest.player === 1 && guest.frame?.players === 2 && host.frame?.players === 2, "Gast fehlt.");
    const full = connect(ws);
    full.socket.addEventListener("close", event => { full.closeCode = event.code; });
    await until(() => full.closeCode, "Dritter Client blieb verbunden.", 4000);
    assert.equal(full.closeCode, 1008);

    function input(peer, angle, fire = true) {
        peer.socket.send(JSON.stringify({ type: "input", round: peer.frame.round, angle, power: 55, fire }));
    }
    input(host, 43);
    input(guest, 47);
    await until(() => [host, guest].every(peer => peer.frame?.shots.length === 2 &&
        peer.frame.cannons[0][2] === 43 && peer.frame.cannons[1][2] === 47), "Beide Schüsse wurden nicht repliziert.");
    await until(() => host.terrain > 1 && guest.terrain > 1, "Einschlag erzeugte keine Terrain-Updates.");

    await until(() => host.frame?.warning >= 0 && guest.frame?.warning === host.frame.warning, "Abwurfvorwarnung fehlt.");
    const dropX = host.frame.warning;
    await until(() => host.frame?.drop?.[1] === dropX && guest.frame?.drop?.[1] === dropX, "Kiste fällt nicht in der markierten Zone.");

    const initialBytes = guest.bytes;
    const start = performance.now();
    for (let i = 0; i < 5; i++) {
        input(host, 43);
        input(guest, 47);
        await delay(760);
    }
    const rate = (guest.bytes - initialBytes) * 1000 / (performance.now() - start);
    console.log(`Nutzdaten je Gast bei beidseitigem Beschuss: ${(rate / 1000).toFixed(1)} kB/s`);

    guest.socket.close();
    await until(() => host.frame?.players === 1, "Host erkennt die Trennung nicht.");
    const paused = host.frame;
    await delay(250);
    assert.deepEqual(host.frame, paused);
    const rejoined = connect(ws);
    await until(() => rejoined.player === 1 && rejoined.frame?.players === 2 && rejoined.terrain >= 1, "Wiederbeitritt fehlgeschlagen.");
    assert.equal(rejoined.frame.round, paused.round);
    rejoined.socket.send(JSON.stringify({ type: "restart", round: paused.round }));
    await delay(200);
    assert.equal(host.frame.round, paused.round);
    host.socket.send(JSON.stringify({ type: "restart", round: paused.round }));
    await until(() => [host, rejoined].every(peer => peer.frame?.round === paused.round + 1 &&
        peer.frame.cannons.every(cannon => cannon[4] === 1000) && !peer.frame.drop), "Host-Neustart fehlt.");
    console.log("PASS: 2 Spieler, 2 Schüsse, Terrain, Vorwarnung, Kiste, voller Raum, Pause, Wiederbeitritt, Host-Neustart");
} finally {
    for (const socket of sockets) socket.close();
    server.kill();
}
