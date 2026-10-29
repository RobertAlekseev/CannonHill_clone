using System;
using System.Collections.Generic;

namespace CannonHill
{
    [Serializable] public class Cannon
    {
        public float x, y, vy, angle = 45, power = 55, cooldown, tilt;
    }
    [Serializable] public class Shot { public float x, y, vx, vy, age; }
    [Serializable] public class Message
    {
        public string type = "state";
        public int version = 1, tick, impacts;
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
        }
        public bool Solid(int x, int y) => x >= 0 && x < W && y >= 0 && y < H && Cells[y * W + x] != 0;
        int Surface(int x) { for (int y = 0; y < H; y++) if (Solid(x, y)) return y; return H; }
        static float Clamp(float x, float min, float max) => Math.Max(min, Math.Min(max, x));
        public void Input(int player, float angle, float power, bool fire)
        {
            if (player < 0 || player > 1 || float.IsNaN(angle) || float.IsInfinity(angle) || float.IsNaN(power) || float.IsInfinity(power)) return;
            var c = Cannons[player]; c.angle = Clamp(angle, 5, 85); c.power = Clamp(power, 15, 90);
            if (!fire || c.cooldown > 0 || Shots.Count >= 32) return;
            float dx = (float)Math.Cos(c.angle * Math.PI / 180) * (player == 0 ? 1 : -1);
            float dy = -(float)Math.Sin(c.angle * Math.PI / 180);
            Shots.Add(new Shot { x = c.x + dx * 7, y = c.y - 1 + dy * 7, vx = dx * c.power, vy = dy * c.power });
            c.cooldown = .7f;
        }
        public void Crater(float cx, float cy, float radius = 10)
        {
            for (int y = Math.Max(0, (int)(cy - radius)); y < Math.Min(H, (int)(cy + radius) + 1); y++)
                for (int x = Math.Max(0, (int)(cx - radius)); x < Math.Min(W, (int)(cx + radius) + 1); x++)
                    if (Cells[y * W + x] == 1 && (x - cx) * (x - cx) + (y - cy) * (y - cy) < radius * radius) Cells[y * W + x] = 0;
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
            foreach (var c in Cannons)
            {
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
            for (int i = Shots.Count - 1; i >= 0; i--)
            {
                var s = Shots[i]; s.vy += Gravity * Dt; s.age += Dt;
                int count = Math.Max(1, (int)Math.Ceiling(Math.Sqrt(s.vx * s.vx + s.vy * s.vy) * Dt * 2));
                bool hit = false;
                for (int sub = 0; sub < count; sub++)
                {
                    s.x += s.vx * Dt / count; s.y += s.vy * Dt / count;
                    if (Solid((int)Math.Floor(s.x), (int)Math.Floor(s.y))) { Crater(s.x, s.y); hit = true; break; }
                }
                if (hit || s.age > 12 || s.x < 0 || s.x >= W || s.y >= H) Shots.RemoveAt(i);
            }
        }
        public Message Snapshot() => new Message { tick = Tick, impacts = Impacts, cells = Convert.ToBase64String(Cells), cannons = Cannons, shots = Shots.ToArray() };
        public bool Apply(Message state)
        {
            if (state == null || state.version != 1 || state.cannons == null || state.cannons.Length != 2 || state.shots == null || state.shots.Length > 32) return false;
            byte[] decoded;
            try { decoded = Convert.FromBase64String(state.cells ?? ""); } catch (FormatException) { return false; }
            if (decoded.Length != W * H) return false;
            Cells = decoded; Cannons = state.cannons; Shots = new List<Shot>(state.shots); Tick = state.tick; Impacts = state.impacts;
            return true;
        }
    }
}
