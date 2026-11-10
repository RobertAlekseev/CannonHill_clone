import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { performance } from 'node:perf_hooks';

const [wasm = new URL('./dist/cannon_hill_web.wasm', import.meta.url), comparePath] = process.argv.slice(2);
const { instance } = await WebAssembly.instantiate(await readFile(wasm));
const game = instance.exports;
const mapScale = game.bench_map_scale?.() ?? 1;
const width = 240 * mapScale;
const height = 128 * mapScale;
const scenarios = [
    { name: 'Ruhe', fire: false },
    { name: 'Beschuss', fire: true },
];
if (game.bench_fill_shots) scenarios.push({ name: '32 Geschosse', stress: true });
const runs = 5;
const ticks = 300;

function run(g, scenario, samples, hash) {
    g.reset(42);
    for (let tick = 0; tick < ticks; tick++) {
        const fire = Number(scenario.fire && tick % 23 === 0);
        if (scenario.stress) g.bench_fill_shots();
        const start = performance.now();
        g.input(0, 45, 55, fire);
        g.input(1, 45, 55, fire);
        g.step();
        samples?.push(performance.now() - start);
        if (hash) {
            const values = [g.result(), g.terrain_revision(), g.shot_count()];
            for (let player = 0; player < 2; player++) {
                for (let field = 0; field < 7; field++) values.push(g.cannon(player, field));
            }
            for (let i = 0; i < g.shot_count(); i++) values.push(g.shot(i, 0), g.shot(i, 1));
            for (let field = 0; field < 3; field++) values.push(g.drop_state(field));
            hash.update(JSON.stringify(values) + '\n');
            hash.update(new Uint8Array(g.memory.buffer, g.terrain_ptr(), width * height));
        }
        if (g.result() !== -2) throw new Error('Runde im Messszenario vorzeitig beendet.');
    }
}

const referenceBytes = comparePath ? await readFile(comparePath) : undefined;
const reference = referenceBytes
    ? (await WebAssembly.instantiate(referenceBytes)).instance.exports
    : undefined;
if (reference && ((reference.bench_map_scale?.() ?? 1) !== mapScale ||
    Boolean(reference.bench_fill_shots) !== Boolean(game.bench_fill_shots))) {
    throw new Error('Referenz und Testbuild brauchen dieselbe Kartengroesse und dieselben Benchmark-Features.');
}

function stats(samples) {
    samples.sort((a, b) => a - b);
    const percentile = p => samples[Math.ceil(p * samples.length) - 1].toFixed(3);
    return `p50 ${percentile(0.5)} ms, p95 ${percentile(0.95)} ms pro Tick`;
}

console.log(`${width} x ${height} Zellen`);
for (const scenario of scenarios) {
    run(game, scenario);
    const samples = [];
    const oldSamples = [];
    if (reference) run(reference, scenario);
    for (let i = 0; i < runs; i++) {
        if (reference && i % 2 === 0) run(reference, scenario, oldSamples);
        run(game, scenario, samples);
        if (reference && i % 2 !== 0) run(reference, scenario, oldSamples);
    }
    console.log(`${scenario.name}: ${stats(samples)} (${samples.length} Ticks)`);
    if (reference) console.log(`  Referenz: ${stats(oldSamples)}`);
}

if (reference) {
    for (const scenario of scenarios) {
        const actual = createHash('sha256');
        const expected = createHash('sha256');
        // Compare fresh instances so their monotonic terrain revisions start equal.
        const candidate = (await WebAssembly.instantiate(await readFile(wasm))).instance.exports;
        const baseline = (await WebAssembly.instantiate(referenceBytes)).instance.exports;
        run(candidate, scenario, undefined, actual);
        run(baseline, scenario, undefined, expected);
        if (actual.digest('hex') !== expected.digest('hex')) {
            throw new Error(`Spielzustand weicht ab: ${scenario.name}`);
        }
        console.log(`Identischer sichtbarer Spielzustand in allen ${ticks} Ticks: ${scenario.name}`);
    }
}
