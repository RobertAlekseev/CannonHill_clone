import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { readFile, mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { setTimeout as delay } from "node:timers/promises";

const [engine, executable] = process.argv.slice(2);
if (!executable || !["unity", "unreal"].includes(engine)) throw new Error("native-smoke.mjs unity|unreal <executable>");
const root = fileURLToPath(new URL("../", import.meta.url));
const logs = await mkdtemp(join(tmpdir(), "cannon-hill-native-"));
const logFile = join(logs, "client.log");
const server = spawn(resolve(root, "rust-web/target/release/cannon-hill-lan.exe"), ["127.0.0.1:0"], { windowsHide: true });
let output = "", peer, client, snapshot, launchError;
server.stdout.on("data", bytes => { output += bytes; });
server.stderr.pipe(process.stderr);
server.on("error", error => { launchError = error; });

async function waitFor(check, milliseconds, description) {
    const deadline = performance.now() + milliseconds;
    while (performance.now() < deadline) {
        if (launchError) throw launchError;
        const value = await check();
        if (value) return value;
        await delay(50);
    }
    throw new Error(`${description}. Log: ${logFile}`);
}

try {
    const address = await waitFor(() => output.match(/http:\/\/127\.0\.0\.1:\d+/)?.[0], 10000, "Rust-Server fehlt");
    const url = address.replace("http:", "ws:") + "/ws";
    let seat = -1, fired = false;
    peer = new WebSocket(url);
    peer.onmessage = ({data}) => {
        if (typeof data !== "string") return;
        const message = JSON.parse(data);
        if ("player" in message) { seat = message.player; return; }
        snapshot = message;
        if (!fired && message.players === 2) {
            fired = true;
            peer.send(JSON.stringify({ type:"input", round:message.round, angle:43, power:55, fire:true }));
        }
    };
    await waitFor(() => seat === 0, 10000, "Erster Platz fehlt");
    const args = engine === "unity"
        ? ["-batchmode", "-nographics", "-logFile", logFile, "--rust-server=" + url, "--rust-smoke"]
        : [resolve(root, "unreal 5.8/CannonHill.uproject"), "-game", "-nullrhi", "-nosound", "-unattended", "-nop4", "-nosplash",
            "-RustServer=" + url, "-CannonHillRustSmoke", "-ExecCmds=t.MaxFPS 60", "-abslog=" + logFile];
    client = spawn(executable, args, { windowsHide: true, stdio:"ignore" });
    client.on("error", error => { launchError = error; });
    const marker = await waitFor(async () => {
        const text = await readFile(logFile, "utf8").catch(() => "");
        const match = text.match(/RUST_CLIENT_PASS player=1 tick=\d+/);
        if (!match && client.exitCode !== null) throw new Error(`Spiel beendet. Log: ${logFile}`);
        return match?.[0];
    }, 100000, "Spieltest fehlt");
    assert.ok(fired && snapshot?.cannons[1][2] === 47, "Eingabe des nativen Clients fehlt");
    console.log(`PASS ${engine}: ${marker}, beide Schuesse, Vorwarnung und Kiste. Log: ${logFile}`);
} finally {
    peer?.close();
    client?.kill();
    server.kill();
}
