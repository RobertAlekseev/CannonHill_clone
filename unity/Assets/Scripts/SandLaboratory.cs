using System;
using System.Net;
using System.Net.Sockets;
using System.Text;
using UnityEngine;

namespace CannonHill
{
    public sealed class SandLaboratory : MonoBehaviour
    {
        const int Port = 28741;
        readonly SandSimulation sim = new SandSimulation();
        RustGameClient rust;
        int rustSequence = -1;
        long rustRound = -1;
        bool rustSmoke, rustSawShots, rustSawDrop, rustSawWarning;
        TcpListener listener;
        TcpClient peer;
        readonly byte[] receive = new byte[65536];
        string incoming = "", mode = "offline", address = "127.0.0.1", status = "OFFLINE / Tab wechselt die Kanone";
        int player;
        float angle = 45, power = 55, clock, sendClock;
        bool fire, smoke, typingAddress;
        string capturePath;
        int smokeTicks;
        Texture2D terrain;
        Color32[] pixels;
        int paintedRevision = -1;
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Boot() { if (FindFirstObjectByType<SandLaboratory>() == null) new GameObject("Sand Laboratory").AddComponent<SandLaboratory>(); }
        void Start()
        {
            Application.runInBackground = true;
            terrain = new Texture2D(SandSimulation.W, SandSimulation.H, TextureFormat.RGBA32, false) { filterMode = FilterMode.Point };
            pixels = new Color32[SandSimulation.W * SandSimulation.H];
            foreach (var arg in Environment.GetCommandLineArgs())
            {
                if (arg == "--host") Host();
                else if (arg.StartsWith("--join=")) Join(arg.Substring(7));
                else if (arg.StartsWith("--rust-server=")) Join(arg.Substring(14));
                else if (arg == "--rust-smoke") rustSmoke = true;
                else if (arg == "--smoke") smoke = true;
                else if (arg.StartsWith("--capture=")) capturePath = arg.Substring(10);
            }
            Paint();
        }
        void Disconnect()
        {
            rust?.Dispose();
            rust = null;
            rustSequence = -1;
            rustRound = -1;
            fire = false;
            peer?.Close(); peer = null; listener?.Stop(); listener = null;
            incoming = ""; mode = "offline"; player = 0; status = "OFFLINE / Tab wechselt die Kanone";
            connecting = sending = null;
        }
        void Host()
        {
            Disconnect();
            try { listener = new TcpListener(IPAddress.Any, Port); listener.Start(1); mode = "host"; status = "HOST / TCP 28741 / warte auf Spieler 2"; Debug.Log("HOST_READY"); }
            catch (SocketException e) { Disconnect(); status = "Host fehlgeschlagen: " + e.SocketErrorCode; }
        }
        void Join(string host)
        {
            Disconnect();
            host = host.Trim();
            if (Uri.TryCreate(host, UriKind.Absolute, out var uri) && (uri.Scheme == "ws" || uri.Scheme == "wss"))
            {
                rust = new RustGameClient(uri);
                mode = "rust";
                return;
            }
            if (!IPAddress.TryParse(host, out var ip)) { status = "Bitte eine IPv4-Adresse eingeben"; return; }
            peer = new TcpClient { NoDelay = true }; mode = "client"; player = 1; status = "VERBINDE / " + host;
            // BeginConnect keeps the UI responsive; completion is polled on the main thread.
            connecting = peer.BeginConnect(ip, Port, null, null);
        }
        IAsyncResult connecting;
        void Send(Message m)
        {
            if (peer == null || !peer.Connected || connecting != null) return;
            var bytes = Encoding.UTF8.GetBytes(JsonUtility.ToJson(m) + "\n");
            // A bounded asynchronous write prevents the render loop blocking on a slow peer.
            if (sending != null && !sending.IsCompleted) return;
            if (sending != null) { peer.GetStream().EndWrite(sending); sending = null; }
            sending = peer.GetStream().BeginWrite(bytes, 0, bytes.Length, null, null);
        }
        IAsyncResult sending;
        void Network()
        {
            try
            {
                if (listener != null && listener.Pending())
                {
                    var next = listener.AcceptTcpClient();
                    if (peer != null) next.Close();
                    else { peer = next; peer.NoDelay = true; status = "HOST / Spieler 2 verbunden"; Debug.Log("PEER_CONNECTED"); }
                }
                if (peer == null) return;
                if (connecting != null)
                {
                    if (!connecting.IsCompleted) return;
                    peer.EndConnect(connecting); connecting = null;
                }
                if (!peer.Connected) return;
                if (peer.Client.Poll(0, SelectMode.SelectRead) && peer.Available == 0) throw new System.IO.IOException("Peer getrennt");
                var stream = peer.GetStream();
                while (stream.DataAvailable)
                {
                    int read = stream.Read(receive, 0, receive.Length);
                    if (read == 0) throw new System.IO.IOException("Peer getrennt");
                    incoming += Encoding.UTF8.GetString(receive, 0, read);
                    if (incoming.Length > 262144) throw new System.IO.IOException("Nachricht zu gross");
                }
                int newline;
                while ((newline = incoming.IndexOf('\n')) >= 0)
                {
                    string line = incoming.Substring(0, newline); incoming = incoming.Substring(newline + 1);
                    Message m;
                    try { m = JsonUtility.FromJson<Message>(line); } catch (ArgumentException) { continue; }
                    if (m == null) continue;
                    if (m.version != SandSimulation.ProtocolVersion) { status = "Andere Spielversion / beide brauchen Unity v5"; continue; }
                    if (mode == "host" && m.type == "input") sim.Input(1, m.angle, m.power, m.fire);
                    else if (mode == "client" && m.type == "state" && sim.Apply(m))
                    {
                        status = "LAN / Spieler 2 / Host-Tick " + sim.Tick;
                        if (sim.Tick % 30 < 3) Debug.Log("STATE_RECEIVED tick=" + sim.Tick + " impacts=" + sim.Impacts);
                    }
                }
            }
            catch (Exception e) when (e is SocketException || e is System.IO.IOException || e is ObjectDisposedException || e is InvalidOperationException)
            {
                peer?.Close(); peer = null; connecting = sending = null; incoming = "";
                status = mode == "host" ? "HOST / Spieler getrennt / warte auf Spieler 2" : "VERBINDUNG GETRENNT / erneut verbinden";
                Debug.LogWarning(status + " (" + e.GetType().Name + ")");
            }
        }
        void UpdateRust()
        {
            rust.Poll();
            status = rust.Status;
            var state = rust.Snapshot;
            if (state == null || state.players < 2) fire = false;
            if (state == null || rust.Sequence == rustSequence) return;

            if (sim.Cells != rust.Terrain)
            {
                sim.Cells = rust.Terrain;
                sim.TerrainRevision++;
            }
            for (int i = 0; i < 2; i++)
            {
                var c = sim.Cannons[i];
                var v = state.cannons[i];
                c.x = v[0]; c.y = v[1]; c.angle = v[2]; c.power = v[3];
                c.hp = (int)v[4]; c.shield = v[5]; c.rapid = v[6]; c.tilt = 0;
            }
            sim.Shots.Clear();
            foreach (var shot in state.shots) sim.Shots.Add(new Shot { x = shot[0], y = shot[1] });
            sim.Drop = state.drop == null ? null : new BuffDrop { kind = (int)state.drop[0], x = state.drop[1], y = state.drop[2] };
            sim.RoundOver = state.result != -2;
            sim.Winner = state.result;
            sim.Tick = state.tick;

            bool newSeat = player != rust.Player || rustRound != state.round;
            player = rust.Player;
            rustRound = state.round;
            rustSequence = rust.Sequence;
            if (newSeat)
            {
                angle = sim.Cannons[player].angle;
                power = sim.Cannons[player].power;
                fire = false;
            }
            if (rustSmoke && state.players == 2)
            {
                if (smokeTicks == 0) { angle = 47; fire = true; smokeTicks = 1; }
                rustSawShots |= sim.Shots.Count >= 2;
                rustSawDrop |= sim.Drop != null;
                rustSawWarning |= state.warning >= 0;
                if (rustSawShots && rustSawDrop && rustSawWarning)
                {
                    Debug.Log($"RUST_CLIENT_PASS player={player} tick={sim.Tick}");
                    Application.Quit(0);
                    rustSmoke = false;
                }
            }
        }

        void Update()
        {
            if (rust != null) UpdateRust();
            else Network();
            if (!typingAddress)
            {
                angle = Mathf.Clamp(angle + ((Input.GetKey(KeyCode.UpArrow) ? 1 : 0) - (Input.GetKey(KeyCode.DownArrow) ? 1 : 0)) * Time.deltaTime * 40, 5, 85);
                power = Mathf.Clamp(power + ((Input.GetKey(KeyCode.RightArrow) ? 1 : 0) - (Input.GetKey(KeyCode.LeftArrow) ? 1 : 0)) * Time.deltaTime * 30, 15, 90);
                fire |= Input.GetKeyDown(KeyCode.Space);
                if (mode == "offline" && Input.GetKeyDown(KeyCode.Tab)) { player = 1 - player; angle = sim.Cannons[player].angle; power = sim.Cannons[player].power; }
            }
            clock += Mathf.Min(Time.deltaTime, .15f);
            while (clock >= SandSimulation.Dt)
            {
                clock -= SandSimulation.Dt;
                if (mode != "client" && mode != "rust") { sim.Input(player, angle, power, fire); sim.Step(); fire = false; }
                if (smoke && ++smokeTicks == 30) fire = true;
                if (smoke && smokeTicks == 60 && capturePath != null) ScreenCapture.CaptureScreenshot(capturePath);
                if (smoke && smokeTicks == 200) { Debug.Log("SMOKE_FINISHED tick=" + sim.Tick + " impacts=" + sim.Impacts); Application.Quit(0); }
            }
            sendClock += Time.deltaTime;
            if (sendClock >= .1f)
            {
                sendClock = 0;
                try
                {
                    if (rust != null) { if (rust.Send(angle, power, fire)) fire = false; }
                    else if (mode == "host") Send(sim.Snapshot());
                    else if (mode == "client" && peer != null && peer.Connected && (sending == null || sending.IsCompleted))
                    { Send(new Message { type = "input", angle = angle, power = power, fire = fire }); fire = false; }
                }
                catch (Exception e) when (e is SocketException || e is System.IO.IOException) { Disconnect(); status = "Netzwerkfehler / erneut verbinden"; }
            }
            Paint();
        }
        void Paint()
        {
            if (paintedRevision == sim.TerrainRevision) return;
            paintedRevision = sim.TerrainRevision;
            for (int y = 0; y < SandSimulation.H; y++) for (int x = 0; x < SandSimulation.W; x++)
            {
                int i = y * SandSimulation.W + x; float g = (x * 17 + y * 31) % 11 / 110f;
                Color c = new Color(.05f + y * .0003f, .10f + y * .0003f, .15f + y * .0003f);
                if (sim.Cells[i] == 1) c = y > 0 && sim.Cells[i - SandSimulation.W] == 0 ? new Color(.957f, .835f, .604f) : new Color(.72f + g, .50f + g, .27f + g);
                else if (sim.Cells[i] == 2) c = new Color(.204f, .282f, .329f);
                pixels[(SandSimulation.H - 1 - y) * SandSimulation.W + x] = c;
            }
            terrain.SetPixels32(pixels); terrain.Apply(false);
        }
        static void Box(Rect r, Color c) { GUI.color = c; GUI.DrawTexture(r, Texture2D.whiteTexture); GUI.color = Color.white; }
        static void Line(Vector2 a, Vector2 b, float width, Color c)
        {
            var matrix = GUI.matrix; Vector2 d = b - a;
            GUIUtility.RotateAroundPivot(Mathf.Atan2(d.y, d.x) * Mathf.Rad2Deg, a);
            Box(new Rect(a.x, a.y - width / 2, d.magnitude, width), c); GUI.matrix = matrix;
        }
        void OnGUI()
        {
            GUI.matrix = Matrix4x4.Scale(new Vector3(Screen.width / 1100f, Screen.height / 760f, 1));
            Box(new Rect(0, 0, 1100, 760), new Color(.035f, .06f, .09f));
            var title = new GUIStyle(GUI.skin.label) { fontSize = 27, normal = { textColor = new Color(.957f, .835f, .604f) } };
            GUI.Label(new Rect(38, 20, 1000, 40), "CANNON HILL   /   SAND LABORATORY", title);
            GUI.Label(new Rect(38, 60, 1000, 30), "UNITY / 01     Echtzeit-Artillerie · Sand · LAN fuer zwei");
            if (GUI.Button(new Rect(38, 99, 100, 34), "Offline")) { Disconnect(); sim.Reset(); }
            if (GUI.Button(new Rect(150, 99, 125, 34), "LAN hosten")) Host();
            GUI.SetNextControlName("address"); address = GUI.TextField(new Rect(288, 99, 185, 34), address);
            if (GUI.Button(new Rect(486, 99, 125, 34), "Verbinden")) { GUI.FocusControl(null); Join(address); }
            if (GUI.Button(new Rect(624, 99, 125, 34), "Neustart"))
            {
                if (rust != null) rust.Restart();
                else if (mode != "client") sim.Reset();
            }
            if (GUI.Button(new Rect(762, 99, 125, 34), "Boden loesen") && mode != "client" && mode != "rust") sim.Crater(sim.Cannons[player].x, sim.Cannons[player].y + 8, 12);
            var current = sim.Cannons[player];
            string info = sim.RoundOver ? (sim.Winner < 0 ? "Unentschieden" : $"Spieler {sim.Winner + 1} gewinnt") : "Kiste abschiessen";
            if (rust?.Snapshot?.warning >= 0) info = "Abwurf in Kuerze";
            else if (sim.Drop != null) info = "Kiste: " + SandSimulation.BuffNames[sim.Drop.kind];
            GUI.Label(new Rect(38, 144, 1000, 30), $"{status} | {info} | Schild {current.shield:0}s | Schnellfeuer {current.rapid:0}s");
            GUI.DrawTexture(new Rect(70, 180, 960, 512), terrain);
            for (int i = 0; i < 2; i++)
            {
                var c = sim.Cannons[i]; Vector2 p = new Vector2(70 + c.x * 4, 180 + c.y * 4);
                Color color = i == 0 ? new Color(.47f, .85f, .77f) : new Color(.94f, .61f, .53f);
                if (c.hp == 0) color = Color.gray;
                GUI.Label(new Rect(p.x - 32, p.y - 31, 84, 22), $"{c.hp} LP");
                Vector2 axis = new Vector2(Mathf.Cos(c.tilt), Mathf.Sin(c.tilt)) * 12;
                Line(p - axis, p + axis, 9, color);
                Vector2 dir = new Vector2(Mathf.Cos(c.angle * Mathf.Deg2Rad) * (i == 0 ? 1 : -1), -Mathf.Sin(c.angle * Mathf.Deg2Rad));
                Line(p - Vector2.down * 4, p - Vector2.down * 4 + dir * 28, 6, color);
                foreach (int wheel in new[] { -1, 1 }) Box(new Rect(p.x + axis.x * wheel - 5, p.y + axis.y * wheel + 1, 10, 10), color);
                if (player == i) Box(new Rect(p.x - 3, p.y - 38, 6, 6), color);
            }
            if (rust?.Snapshot?.warning >= 0)
            {
                float x = 70 + rust.Snapshot.warning * 4;
                Line(new Vector2(x - 9, 188), new Vector2(x, 198), 2, Color.yellow);
                Line(new Vector2(x, 198), new Vector2(x + 9, 188), 2, Color.yellow);
            }
            if (sim.Drop != null)
            {
                var p = new Vector2(70 + sim.Drop.x * 4, 180 + sim.Drop.y * 4);
                Color tint = sim.Drop.kind == 0 ? Color.green : sim.Drop.kind == 1 ? Color.cyan : new Color(1, .75f, .25f);
                Line(p + new Vector2(-12, -14), p + new Vector2(12, -14), 3, tint);
                Line(p + new Vector2(-12, -14), p, 1, tint);
                Line(p + new Vector2(12, -14), p, 1, tint);
                Box(new Rect(p.x - 7, p.y - 5, 14, 10), tint);
            }
            foreach (var s in sim.Shots) Box(new Rect(70 + s.x * 4 - 3, 180 + s.y * 4 - 3, 6, 6), new Color(1, .95f, .8f));
            GUI.Label(new Rect(38, 708, 1050, 25), $"SPIELER {player + 1}     WINKEL {angle:00}°     STAERKE {power:00}     |     EINSCHLAEGE {sim.Impacts}     SAND IN BEWEGUNG {sim.Moved}");
            GUI.Label(new Rect(38, 738, 1050, 22), "Pfeile: Winkel / Staerke     LEERTASTE Feuer     TAB Spieler (offline)     |     Fels traegt · Sand rieselt");
            typingAddress = GUI.GetNameOfFocusedControl() == "address";
        }
        void OnDestroy() { Disconnect(); if (terrain != null) Destroy(terrain); }
    }
}
