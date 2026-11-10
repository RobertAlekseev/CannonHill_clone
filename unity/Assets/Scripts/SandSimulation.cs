using System;
using System.Collections.Generic;

namespace CannonHill
{
    [Serializable] public class Cannon
    {
        public int hp = SandSimulation.MaxHp;
        public float shield, rapid;
        public float x, y, vy, angle = 45, power = 55, cooldown, tilt;
    }
    [Serializable] public class Shot { public int owner; public float x, y, vx, vy, age; }
    [Serializable] public class BuffDrop { public int kind; public float x, y; }
    [Serializable] public class Message
    {
        public string type = "state";
        public int version = SandSimulation.ProtocolVersion, tick, impacts, winner = -1;
        public bool roundOver;
        public bool hasDrop;
        public BuffDrop drop;
        public string cells;
        public Cannon[] cannons;
        public Shot[] shots;
        public float angle, power;
        public bool fire;
    }

    // Same reference rules as Godot: grid coordinates, +Y down, 0.25m per cell.
    public sealed class SandSimulation
    {
        public const int W = 240, H = 128;
        public const int ProtocolVersion = 5, MaxHp = 1000;
        public static readonly string[] BuffNames = { "Reparatur", "Schild", "Schnellfeuer" };
        readonly Random random = new Random();
        public BuffDrop Drop;
        public bool RoundOver;
        public int Winner = -1;
        public int TerrainRevision;
        public const float Dt = 1f / 30f, Gravity = 39.24f;
        public byte[] Cells = new byte[W * H];
        public Cannon[] Cannons;
        public List<Shot> Shots = new List<Shot>();
        public int Tick, Impacts, Moved;
        public SandSimulation() { Reset(); }
        public void Reset()
        {
            Array.Clear(Cells, 0, Cells.Length);
            for (int x = 0; x < W; x++)
            {
                int surface = (int)(81 + 10 * Math.Sin(x * .035) + 5 * Math.Sin(x * .081));
                for (int y = surface; y < H; y++) Cells[y * W + x] = (byte)(y >= H - 4 ? 2 : 1);
            }
            Cannons = new[] { new Cannon { x = 40 }, new Cannon { x = 200 } };
            foreach (var c in Cannons) c.y = Surface((int)c.x) - 3;
            Shots.Clear(); Tick = Impacts = Moved = 0;
            Drop = null; RoundOver = false; Winner = -1; TerrainRevision++;
        }
        public bool Solid(int x, int y) => x >= 0 && x < W && y >= 0 && y < H && Cells[y * W + x] != 0;
        int Surface(int x) { for (int y = 0; y < H; y++) if (Solid(x, y)) return y; return H; }
        static float Clamp(float x, float min, float max) => Math.Max(min, Math.Min(max, x));
        public void Input(int player, float angle, float power, bool fire)
        {
            if (player < 0 || player > 1 || float.IsNaN(angle) || float.IsInfinity(angle) || float.IsNaN(power) || float.IsInfinity(power)) return;
            var c = Cannons[player];
            if (RoundOver || c.hp == 0) return;
            c.angle = Clamp(angle, 5, 85); c.power = Clamp(power, 15, 90);
            if (!fire || c.cooldown > 0 || Shots.Count >= 32) return;
            float dx = (float)Math.Cos(c.angle * Math.PI / 180) * (player == 0 ? 1 : -1);
            float dy = -(float)Math.Sin(c.angle * Math.PI / 180);
            Shots.Add(new Shot { owner = player, x = c.x + dx * 7, y = c.y - 1 + dy * 7, vx = dx * c.power, vy = dy * c.power });
            c.cooldown = c.rapid > 0 ? .35f : .7f;
        }
        public void Crater(float cx, float cy, float radius = 10)
        {
            bool changed = false;
            for (int y = Math.Max(0, (int)(cy - radius)); y < Math.Min(H, (int)(cy + radius) + 1); y++)
                for (int x = Math.Max(0, (int)(cx - radius)); x < Math.Min(W, (int)(cx + radius) + 1); x++)
                    if (Cells[y * W + x] == 1 && (x - cx) * (x - cx) + (y - cy) * (y - cy) < radius * radius) { Cells[y * W + x] = 0; changed = true; }
            if (changed) TerrainRevision++;
            Impacts++;
        }
        public void Step()
        {
            Tick++; Moved = 0;
            for (int y = H - 2; y >= 0; y--) for (int scan = 0; scan < W; scan++)
            {
                int x = Tick % 2 == 0 ? scan : W - 1 - scan, index = y * W + x;
                if (Cells[index] != 1) continue;
                int target = index + W;
                if (Cells[target] != 0)
                {
                    int side = (Tick + x + y) % 2 == 0 ? 1 : -1;
                    if (x + side >= 0 && x + side < W && Cells[target + side] == 0) target += side;
                    else if (x - side >= 0 && x - side < W && Cells[target - side] == 0) target -= side;
                    else continue;
                }
                Cells[index] = 0; Cells[target] = 1; Moved++;
            }
            if (Moved > 0) TerrainRevision++;
            foreach (var c in Cannons)
            {
                c.shield = Math.Max(0, c.shield - Dt);
                c.rapid = Math.Max(0, c.rapid - Dt);
                c.cooldown = Math.Max(0, c.cooldown - Dt); c.vy += Gravity * Dt;
                float next = Math.Min(H - 7, c.y + c.vy * Dt);
                int left = H, right = H;
                for (int y = Math.Max(0, (int)(c.y + 2)); y < H; y++)
                {
                    if (left == H && Solid((int)c.x - 3, y)) left = y;
                    if (right == H && Solid((int)c.x + 3, y)) right = y;
                }
                float floor = Math.Min(left, right) - 3;
                if (next >= floor) { next = floor; c.vy = 0; }
                c.y = next; c.tilt = Clamp((float)Math.Atan2(right - left, 6), -.5f, .5f);
            }
            if (RoundOver) return;
            if (Tick % 150 == 0) Drop = new BuffDrop { x = random.Next(96, 145), y = 4, kind = random.Next(3) };
            if (Drop != null)
            {
                Drop.y += 19 * Dt;
                if (Drop.y >= H || Solid((int)Drop.x, (int)Drop.y)) Drop = null;
            }
            for (int i = Shots.Count - 1; i >= 0; i--)
            {
                var s = Shots[i]; s.vy += Gravity * Dt; s.age += Dt;
                int count = Math.Max(1, (int)Math.Ceiling(Math.Sqrt(s.vx * s.vx + s.vy * s.vy) * Dt * 2));
                bool hit = false;
                for (int sub = 0; sub < count; sub++)
                {
                    s.x += s.vx * Dt / count; s.y += s.vy * Dt / count;
                    if (Drop != null && DistanceSquared(s.x - Drop.x, s.y - Drop.y) <= 25)
                    {
                        var owner = Cannons[s.owner];
                        if (owner.hp > 0)
                        {
                            switch (Drop.kind)
                            {
                                case 0: owner.hp = Math.Min(MaxHp, owner.hp + 150); break;
                                case 1: owner.shield = 8; break;
                                case 2: owner.rapid = 8; break;
                            }
                        }
                        Drop = null;
                        hit = true;
                        break;
                    }
                    int target = -1;
                    for (int j = 0; j < Cannons.Length; j++)
                    {
                        var c = Cannons[j];
                        if (c.hp > 0 && DistanceSquared(c.x - s.x, c.y - s.y) <= 16) { target = j; break; }
                    }
                    if (target >= 0 || Solid((int)Math.Floor(s.x), (int)Math.Floor(s.y)))
                    {
                        Crater(s.x, s.y);
                        for (int j = 0; j < Cannons.Length; j++)
                        {
                            var c = Cannons[j];
                            float distance = Math.Max(0, (float)Math.Sqrt(DistanceSquared(c.x - s.x, c.y - s.y)) - 4);
                            float damage = j == target ? 200 : 200 * Math.Max(0, 1 - distance / 14);
                            if (c.shield > 0) damage *= .5f;
                            c.hp = Math.Max(0, c.hp - (int)(damage + .5f));
                        }
                        hit = true;
                        break;
                    }
                }
                if (hit || s.age > 12 || s.x < 0 || s.x >= W || s.y >= H) Shots.RemoveAt(i);
            }
            if (Cannons[0].hp == 0 || Cannons[1].hp == 0)
            {
                RoundOver = true;
                Winner = Cannons[0].hp > 0 ? 0 : Cannons[1].hp > 0 ? 1 : -1;
                Shots.Clear();
                Drop = null;
            }
        }
        static float DistanceSquared(float x, float y) => x * x + y * y;
        public Message Snapshot() => new Message { tick = Tick, impacts = Impacts, cells = Convert.ToBase64String(Cells), cannons = Cannons, shots = Shots.ToArray(), hasDrop = Drop != null, drop = Drop, roundOver = RoundOver, winner = Winner };
        public bool Apply(Message state)
        {
            if (state == null || state.version != ProtocolVersion || state.cannons == null || state.cannons.Length != 2 || state.shots == null || state.shots.Length > 32) return false;
            foreach (var c in state.cannons)
                if (c == null || c.hp < 0 || c.hp > MaxHp || !(c.shield >= 0 && c.shield <= 8 && c.rapid >= 0 && c.rapid <= 8)) return false;
            if (state.hasDrop && (state.drop == null || state.drop.kind < 0 || state.drop.kind >= BuffNames.Length ||
                !(state.drop.x >= 0 && state.drop.x < W && state.drop.y >= 0 && state.drop.y < H))) return false;
            if (state.winner < -1 || state.winner > 1) return false;
            byte[] decoded;
            try { decoded = Convert.FromBase64String(state.cells ?? ""); } catch (FormatException) { return false; }
            if (decoded.Length != W * H) return false;
            for (int i = 0; i < decoded.Length; i++)
            {
                if (decoded[i] == Cells[i]) continue;
                TerrainRevision++;
                break;
            }
            Drop = state.hasDrop ? state.drop : null;
            RoundOver = state.roundOver;
            Winner = state.winner;
            Cells = decoded; Cannons = state.cannons; Shots = new List<Shot>(state.shots); Tick = state.tick; Impacts = state.impacts;
            return true;
        }
    }
}
