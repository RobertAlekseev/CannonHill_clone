using System;
using System.IO;
using System.Net.WebSockets;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using UnityEngine;

namespace CannonHill
{
    internal sealed class RustGameClient : IDisposable
    {
        [Serializable] public sealed class Welcome { public int protocol, player = -1; }
        [Serializable] public sealed class Command
        {
            public string type;
            public long round;
            public float angle, power;
            public bool fire;
        }
        [DataContract]
        public sealed class State
        {
            [DataMember] public int protocol, tick, players, result;
            [DataMember] public long round, revision;
            [DataMember] public float[][] cannons, shots;
            [DataMember] public float[] drop;
            [DataMember] public float warning;
        }

        readonly Uri address;
        readonly byte[] buffer = new byte[65536];
        readonly MemoryStream message = new MemoryStream();
        readonly DataContractJsonSerializer serializer = new DataContractJsonSerializer(typeof(State));
        ClientWebSocket socket;
        CancellationTokenSource cancellation;
        Task connection, sending;
        Task<WebSocketReceiveResult> receiving;
        byte[] pendingTerrain;
        long revision = -1;
        float retryAt;
        public int Player { get; private set; } = -1;
        public State Snapshot { get; private set; }
        public int Sequence { get; private set; }
        public byte[] Terrain { get; private set; }
        public string Status { get; private set; }

        public RustGameClient(Uri address)
        {
            this.address = address;
            Open();
        }

        void Open()
        {
            socket = new ClientWebSocket();
            cancellation = new CancellationTokenSource();
            connection = socket.ConnectAsync(address, cancellation.Token);
            Status = "VERBINDE / Rust-Server";
        }

        void ResetConnection(string status, bool retry)
        {
            Dispose();
            retryAt = retry ? Time.realtimeSinceStartup + 1 : float.PositiveInfinity;
            Status = status;
        }

        public void Poll()
        {
            try
            {
                if (socket == null)
                {
                    if (Time.realtimeSinceStartup >= retryAt) Open();
                    return;
                }
                if (!connection.IsCompleted) return;
                connection.GetAwaiter().GetResult();
                if (sending != null && sending.IsCompleted)
                {
                    sending.GetAwaiter().GetResult();
                    sending = null;
                }
                for (int i = 0; i < 24; i++)
                {
                    receiving ??= socket.ReceiveAsync(new ArraySegment<byte>(buffer), cancellation.Token);
                    if (!receiving.IsCompleted) break;
                    var result = receiving.GetAwaiter().GetResult();
                    receiving = null;
                    if (result.MessageType == WebSocketMessageType.Close)
                    {
                        bool full = (int?)result.CloseStatus == 1008;
                        ResetConnection(full ? "PARTIE VOLL / erneut verbinden" : "GETRENNT / neuer Versuch", !full);
                        return;
                    }
                    message.Write(buffer, 0, result.Count);
                    if (message.Length > 65536)
                    {
                        ResetConnection("Ungueltige Servernachricht", false);
                        return;
                    }
                    if (!result.EndOfMessage) continue;
                    if (result.MessageType == WebSocketMessageType.Binary)
                        pendingTerrain = DecodeTerrain(message.GetBuffer(), (int)message.Length);
                    else
                        ReadText();
                    message.SetLength(0);
                    if (socket == null) return;
                }
            }
            catch (Exception e) when (e is WebSocketException || e is IOException ||
                e is InvalidOperationException || e is OperationCanceledException)
            {
                ResetConnection("GETRENNT / neuer Versuch", true);
            }
        }

        void ReadText()
        {
            if (Player < 0)
            {
                var welcome = JsonUtility.FromJson<Welcome>(Encoding.UTF8.GetString(message.GetBuffer(), 0, (int)message.Length));
                if (welcome == null || welcome.protocol != 1 || welcome.player < 0 || welcome.player > 1)
                {
                    ResetConnection("ANDERE SPIELVERSION / Rust-WebSocket v1", false);
                    return;
                }
                Player = welcome.player;
                return;
            }
            message.Position = 0;
            State state;
            try { state = serializer.ReadObject(message) as State; }
            catch (System.Runtime.Serialization.SerializationException) { return; }
            if (state == null || state.protocol != 1 || state.cannons?.Length != 2 ||
                state.shots == null || state.shots.Length > 32 || state.players < 0 || state.players > 2 ||
                state.result < -2 || state.result > 1 || state.tick < 0 || state.round < 0 || state.revision < 0) return;
            foreach (var cannon in state.cannons)
                if (!ValidValues(cannon, 7) || cannon[4] < 0 || cannon[4] > SandSimulation.MaxHp) return;
            foreach (var shot in state.shots)
                if (!ValidValues(shot, 2)) return;
            if (state.drop != null && (!ValidValues(state.drop, 3) || state.drop[0] < 0 || state.drop[0] > 2 ||
                state.drop[0] != (int)state.drop[0])) return;
            if (state.revision != revision)
            {
                if (pendingTerrain == null) return;
                Terrain = pendingTerrain;
                pendingTerrain = null;
                revision = state.revision;
            }
            Snapshot = state;
            Sequence++;
            Status = $"RUST-SERVER / Spieler {Player + 1}" + (state.players == 2 ? "" : " / warte auf zweiten Spieler");
        }

        static bool ValidValues(float[] values, int length)
        {
            if (values == null || values.Length != length) return false;
            foreach (var value in values)
                if (float.IsNaN(value) || float.IsInfinity(value)) return false;
            return true;
        }

        static byte[] DecodeTerrain(byte[] bytes, int length)
        {
            var cells = new byte[SandSimulation.W * SandSimulation.H];
            if (length == cells.Length + 1 && bytes[0] == 0)
            {
                Buffer.BlockCopy(bytes, 1, cells, 0, cells.Length);
                foreach (byte cell in cells) if (cell > 2) return null;
                return cells;
            }
            if (length < 3 || bytes[0] != 1 || length % 2 != 1) return null;
            int offset = 0;
            for (int i = 1; i < length; i += 2)
            {
                int count = bytes[i];
                byte cell = bytes[i + 1];
                if (count == 0 || cell > 2 || offset + count > cells.Length) return null;
                for (int j = 0; j < count; j++) cells[offset++] = cell;
            }
            return offset == cells.Length ? cells : null;
        }

        public bool Send(float angle, float power, bool fire)
        {
            return Snapshot?.players == 2 && Send(new Command { type = "input", round = Snapshot.round, angle = angle, power = power, fire = fire });
        }

        public bool Restart()
        {
            return Player == 0 && Snapshot != null && Send(new Command { type = "restart", round = Snapshot.round });
        }

        bool Send(Command command)
        {
            if (socket?.State != WebSocketState.Open || sending != null) return false;
            var bytes = Encoding.UTF8.GetBytes(JsonUtility.ToJson(command));
            sending = socket.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, cancellation.Token);
            return true;
        }

        public void Dispose()
        {
            cancellation?.Cancel();
            socket?.Dispose();
            cancellation?.Dispose();
            socket = null;
            cancellation = null;
            connection = sending = null;
            receiving = null;
            Snapshot = null;
            Terrain = pendingTerrain = null;
            Player = -1;
            revision = -1;
            message.SetLength(0);
        }
    }
}
