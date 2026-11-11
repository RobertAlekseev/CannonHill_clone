const W = 240;
const H = 128;
const SCALE = 4;
const DT = 1 / 30;
const COLORS = ["#82e0c3", "#f89c88"];
const BUFFS = ["Reparatur", "Schild", "Schnellfeuer"];
const BUFF_COLORS = ["#98ed91", "#85c8ff", "#ffc975"];
const arena = document.querySelector("#arena");
const notice = document.querySelector("#notice");
const switchButton = document.querySelector("#switch");
const resetButton = document.querySelector("#reset");
const cards = [document.querySelector("#player-0"), document.querySelector("#player-1")];

async function loadLocalGame() {
    const response = await fetch("./cannon_hill_web.wasm");
    if (!response.ok) throw new Error("WebAssembly-Datei fehlt. Start.ps1 ausführen.");
    const { instance } = await WebAssembly.instantiate(await response.arrayBuffer());
    const exports = instance.exports;
    return {
        ...exports,
        terrain: () => new Uint8Array(exports.memory.buffer, exports.terrain_ptr(), W * H),
    };
}

function decodeTerrain(buffer) {
    const bytes = new Uint8Array(buffer);
    if (bytes[0] === 0) return bytes.length === W * H + 1 ? bytes.subarray(1) : undefined;
    if (bytes[0] !== 1 || bytes.length % 2 !== 1) return undefined;
    const cells = new Uint8Array(W * H);
    let offset = 0;
    for (let i = 1; i < bytes.length; i += 2) {
        const end = offset + bytes[i];
        if (end > cells.length || bytes[i] === 0 || bytes[i + 1] > 2) return undefined;
        cells.fill(bytes[i + 1], offset, end);
        offset = end;
    }
    return offset === cells.length ? cells : undefined;
}

function connectLan() {
    const url = new URL("./ws", window.location.href);
    url.protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
    let socket;
    let player = -1;
    let state;
    let terrain = new Uint8Array(W * H);
    let pendingTerrain;
    let revision = 0;
    let message = "Verbinde mit dem LAN-Host …";
    let retry = 1000;

    function connect() {
        socket = new WebSocket(url);
        socket.binaryType = "arraybuffer";
        socket.onmessage = event => {
            if (event.data instanceof ArrayBuffer) {
                pendingTerrain = decodeTerrain(event.data);
                return;
            }
            const data = JSON.parse(event.data);
            if (Number.isInteger(data.player)) {
                player = data.player;
                retry = 1000;
                return;
            }
            if (pendingTerrain) {
                terrain = pendingTerrain;
                pendingTerrain = undefined;
                revision++;
            }
            state = data;
        };
        socket.onclose = event => {
            state = undefined;
            player = -1;
            pendingTerrain = undefined;
            if (event.code === 1008) {
                message = "Partie voll. Lade die Seite neu, sobald ein Platz frei ist.";
                return;
            }
            message = "Verbindung unterbrochen · neuer Versuch …";
            window.setTimeout(connect, retry);
            retry = Math.min(retry * 2, 8000);
        };
    }

    function send(command) {
        if (state && socket.readyState === WebSocket.OPEN && socket.bufferedAmount < 4096) {
            socket.send(JSON.stringify({ ...command, round: state.round }));
            return true;
        }
        return false;
    }

    connect();
    return {
        terrain: () => terrain,
        terrain_revision: () => revision,
        cannon: (index, field) => state?.cannons[index][field] ?? [index ? 200 : 40, 80, 45, 55, 1000, 0, 0][field],
        shot_count: () => state?.shots.length ?? 0,
        shot: (index, axis) => state.shots[index][axis],
        drop_state: field => state?.drop?.[field] ?? -1,
        drop_warning_x: () => state?.warning ?? -1,
        result: () => state?.result ?? -2,
        input: (_player, angle, power, fire, drive = 0) => {
            return state?.players === 2 && send({ type: "input", angle, power, fire: Boolean(fire), drive });
        },
        reset: () => send({ type: "restart" }),
        step: () => {},
        session: () => ({ player, round: state?.round, ready: state?.players === 2,
            notice: state ? (state.players === 2 ? "" : "Warte auf den zweiten Spieler …") : message }),
    };
}

async function start() {
    const options = new URLSearchParams(window.location.search);
    const lan = options.get("lan") === "1";
    const measure = options.get("perf") === "1";
    const game = lan ? connectLan() : await loadLocalGame();
    const samples = [];
    if (measure) {
        window.cannonHillPerformance = () => {
            const percentile = key => {
                const values = samples.map(sample => sample[key]).sort((a, b) => a - b);
                return values.length ? values[Math.ceil(values.length * 0.95) - 1] : 0;
            };
            return { frames: samples.length, frameP95: percentile("frame"),
                simulationP95: percentile("simulation"), drawingP95: percentile("drawing"),
                terrainUpdates: samples.filter(sample => sample.terrain).length,
                maxShots: Math.max(0, ...samples.map(sample => sample.shots)) };
        };
    }
    const ctx = arena.getContext("2d");
    const terrain = document.createElement("canvas");
    terrain.width = W;
    terrain.height = H;
    const terrainCtx = terrain.getContext("2d");
    const image = terrainCtx.createImageData(W, H);
    const keys = new Set();
    let player = 0;
    let revision = -1;
    let fire = false;
    let elapsed = 0;
    let previous = performance.now();
    let angle = 45;
    let power = 55;
    let round;

    arena.tabIndex = 0;
    arena.addEventListener("click", () => arena.focus());
    arena.addEventListener("blur", () => { keys.clear(); fire = false; });

    function selectPlayer() {
        game.drive?.(player, 0);
        player = 1 - player;
        angle = game.cannon(player, 2);
        power = game.cannon(player, 3);
        fire = false;
        cards.forEach((card, i) => card.setAttribute("aria-current", String(i === player)));
    }

    arena.addEventListener("keydown", event => {
        if (!["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "KeyA", "KeyD", "Space", "Tab"].includes(event.code)) return;
        if (event.shiftKey || event.ctrlKey || event.altKey || event.metaKey) return;
        if (lan && event.code === "Tab") return;
        event.preventDefault();
        keys.add(event.code);
        if (event.repeat) return;
        if (event.code === "Tab") selectPlayer();
        if (event.code === "Space") fire = true;
    });
    arena.addEventListener("keyup", event => keys.delete(event.code));
    switchButton.addEventListener("click", () => { selectPlayer(); arena.focus(); });
    function restart() {
        if (lan) {
            game.reset();
            arena.focus();
            return;
        }
        game.reset(crypto.getRandomValues(new Uint32Array(1))[0]);
        keys.clear();
        fire = false;
        elapsed = 0;
        angle = 45;
        power = 55;
        arena.focus();
    }
    resetButton.addEventListener("click", restart);
    if (lan) {
        switchButton.hidden = true;
        document.querySelector("#mode").textContent = "LAN · Zwei Browser im Heimnetz";
        document.querySelector("#local").hidden = false;
        document.querySelector("#switch-help").hidden = true;
    } else {
        switchButton.disabled = false;
        resetButton.disabled = false;
        restart();
    }

    function paintTerrain() {
        const current = game.terrain_revision();
        if (revision === current) return;
        revision = current;
        const cells = game.terrain();
        const pixels = image.data;
        for (let y = 0; y < H; y++) {
            for (let x = 0; x < W; x++) {
                const i = y * W + x;
                const p = i * 4;
                const grain = (x * 17 + y * 31) % 11;
                const exposed = y > 0 && cells[i - W] === 0;
                let r = 13, g = 24 + (y >> 3), b = 38 + (y >> 3);
                if (cells[i] === 2) { r = 52; g = 72; b = 84; }
                if (cells[i] === 1) {
                    r = exposed ? 243 : 181 + grain * 2;
                    g = exposed ? 209 : 128 + grain * 2;
                    b = exposed ? 141 : 69 + grain * 2;
                }
                pixels[p] = r;
                pixels[p + 1] = g;
                pixels[p + 2] = b;
                pixels[p + 3] = 255;
            }
        }
        terrainCtx.putImageData(image, 0, 0);
    }

    function draw(session) {
        paintTerrain();
        ctx.imageSmoothingEnabled = false;
        ctx.drawImage(terrain, 0, 0, arena.width, arena.height);
        for (let i = 0; i < 2; i++) {
            const x = game.cannon(i, 0) * SCALE;
            const y = game.cannon(i, 1) * SCALE;
            const aim = game.cannon(i, 2);
            const strength = game.cannon(i, 3);
            const hp = game.cannon(i, 4);
            const shield = Math.ceil(game.cannon(i, 5));
            const rapid = Math.ceil(game.cannon(i, 6));
            const text = `Spieler ${i + 1} · ${hp} LP · ${Math.round(aim)}° · Stärke ${Math.round(strength)}`
                + (shield ? ` · Schild ${shield}s` : "") + (rapid ? ` · Schnellfeuer ${rapid}s` : "");
            if (cards[i].textContent !== text) cards[i].textContent = text;
            ctx.fillStyle = hp ? COLORS[i] : "#646e73";
            ctx.strokeStyle = ctx.fillStyle;
            ctx.fillRect(x - 14, y - 5, 28, 10);
            ctx.fillRect(x - 13, y + 4, 7, 6);
            ctx.fillRect(x + 6, y + 4, 7, 6);
            ctx.lineWidth = 5;
            const radians = aim * Math.PI / 180;
            ctx.beginPath();
            ctx.moveTo(x, y - 4);
            ctx.lineTo(x + Math.cos(radians) * 28 * (i ? -1 : 1), y - 4 - Math.sin(radians) * 28);
            ctx.stroke();
            if (i === player && hp) ctx.fillRect(x - 2, y - 34, 4, 4);
        }
        ctx.fillStyle = "#fff0b9";
        const shotCount = game.shot_count();
        for (let i = 0; i < shotCount; i++) {
            ctx.fillRect(game.shot(i, 0) * SCALE - 2, game.shot(i, 1) * SCALE - 2, 4, 4);
        }

        const warning = game.drop_warning_x();
        if (warning >= 0) {
            const x = warning * SCALE;
            ctx.strokeStyle = "#ffd991";
            ctx.fillStyle = "#ffd991";
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.moveTo(x - 9, 13);
            ctx.lineTo(x, 24);
            ctx.lineTo(x + 9, 13);
            ctx.stroke();
            ctx.font = "14px system-ui";
            ctx.fillText("Abwurf", x - 22, 12);
        }
        const kind = game.drop_state(0);
        if (kind >= 0) {
            const x = game.drop_state(1) * SCALE;
            const y = game.drop_state(2) * SCALE;
            ctx.fillStyle = ctx.strokeStyle = BUFF_COLORS[kind];
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.arc(x, y - 11, 11, Math.PI, 2 * Math.PI);
            ctx.moveTo(x - 11, y - 11);
            ctx.lineTo(x, y);
            ctx.lineTo(x + 11, y - 11);
            ctx.stroke();
            ctx.fillRect(x - 7, y - 4, 14, 8);
        }
        const result = game.result();
        const status = session?.notice || (result === -2
            ? (warning >= 0 ? "Abwurf in Kürze" : kind >= 0 ? `Kiste im Anflug · ${BUFFS[kind]}` : "Im Spiel · Nächste Kiste alle fünf Sekunden")
            : (result === -1 ? "Unentschieden" : `Spieler ${result + 1} gewinnt`));
        if (notice.textContent !== status) notice.textContent = status;
    }

    function frame(now) {
        const frameTime = now - previous;
        elapsed += Math.max(0, Math.min(frameTime / 1000, 0.15));
        previous = now;
        const session = game.session?.();
        if (session) {
            if (session.player !== player || session.round !== round) {
                player = session.player;
                round = session.round;
                if (player >= 0) {
                    angle = game.cannon(player, 2);
                    power = game.cannon(player, 3);
                }
                fire = false;
                cards.forEach((card, i) => card.setAttribute("aria-current", String(i === player)));
            }
            resetButton.disabled = player !== 0 || round === undefined;
        }
        const simulationStart = measure ? performance.now() : 0;
        while (elapsed >= DT) {
            elapsed -= DT;
            if (session && !session.ready) { fire = false; continue; }
            angle = Math.max(5, Math.min(85, angle + (Number(keys.has("ArrowUp")) - Number(keys.has("ArrowDown"))) * 40 * DT));
            power = Math.max(15, Math.min(90, power + (Number(keys.has("ArrowRight")) - Number(keys.has("ArrowLeft"))) * 30 * DT));
            const drive = Number(keys.has("KeyD")) - Number(keys.has("KeyA"));
            game.drive?.(player, drive);
            if (game.input(player, angle, power, Number(fire), drive) !== false) fire = false;
            game.step();
        }
        const drawStart = measure ? performance.now() : 0;
        const oldRevision = revision;
        draw(session);
        if (measure && frameTime > 0) {
            if (samples.length === 600) samples.shift();
            samples.push({ frame: frameTime, simulation: drawStart - simulationStart,
                drawing: performance.now() - drawStart, terrain: revision !== oldRevision,
                shots: game.shot_count() });
        }
        requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);
}

start().catch(error => {
    notice.textContent = "Start fehlgeschlagen · " + error.message;
    console.error(error);
});
