#include "SandLaboratoryHUD.h"
#include "Engine/Canvas.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Policies/CondensedJsonPrintPolicy.h"
#include "GameFramework/PlayerController.h"
#include "InputCoreTypes.h"
#include "Sockets.h"
#include "IWebSocket.h"
#include "WebSocketsModule.h"
#include "SocketSubsystem.h"
#include "Interfaces/IPv4/IPv4Address.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Misc/Base64.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"

namespace
{
constexpr int32 Port = 28741;
constexpr int32 MaxMessageChars = 262144;
constexpr int32 MaxReadsPerTick = 16;
const TCHAR* BuffNames[] = { TEXT("Reparatur"), TEXT("Schild"), TEXT("Schnellfeuer") };
TSharedRef<FJsonObject> Obj() { return MakeShared<FJsonObject>(); }
void Number(const TSharedRef<FJsonObject>& O, const TCHAR* K, double V) { O->SetNumberField(K, V); }
double Get(const TSharedPtr<FJsonObject>& O, const TCHAR* K, double Default = 0) { double V; return O->TryGetNumberField(K, V) && FMath::IsFinite(V) ? V : Default; }
}
ASandLaboratoryHUD::ASandLaboratoryHUD()
{
    PrimaryActorTick.bCanEverTick = true;
    PrimaryActorTick.bStartWithTickEnabled = true;
}
void ASandLaboratoryHUD::BeginPlay()
{
    Super::BeginPlay();
    if (auto* PC = GetOwningPlayerController())
    {
        PC->bShowMouseCursor = true;
        AddTickPrerequisiteActor(PC);
    }
#if !UE_BUILD_SHIPPING
    LanSmoke = FParse::Param(FCommandLine::Get(), TEXT("CannonHillLanSmoke"));
    RustSmoke = FParse::Param(FCommandLine::Get(), TEXT("CannonHillRustSmoke"));
#endif
    FString Address;
    if (FParse::Value(FCommandLine::Get(), TEXT("-RustServer="), Address)) JoinRust(Address);
    else if (FParse::Param(FCommandLine::Get(), TEXT("Host"))) Host();
    else if (FParse::Value(FCommandLine::Get(), TEXT("-Join="), Address)) Join(Address);
}
void ASandLaboratoryHUD::Disconnect()
{
    CloseRust();
    Fire = false;
    auto* SS = ISocketSubsystem::Get(PLATFORM_SOCKETSUBSYSTEM);
    for (FSocket* S : { Peer, Listener }) if (S) { S->Close(); SS->DestroySocket(S); }
    Peer = Listener = nullptr; Incoming.Empty(); Outgoing.Reset(); Mode = Player = 0;
    Connecting = false;
    Status = TEXT("OFFLINE / Tab wechselt die Kanone");
}
void ASandLaboratoryHUD::Host()
{
    Disconnect(); auto* SS = ISocketSubsystem::Get(PLATFORM_SOCKETSUBSYSTEM);
    Listener = SS->CreateSocket(NAME_Stream, TEXT("CannonHillListener"), FNetworkProtocolTypes::IPv4);
    if (!Listener) { Status = TEXT("Socket konnte nicht erstellt werden"); return; }
    auto Address = SS->CreateInternetAddr(FNetworkProtocolTypes::IPv4); Address->SetAnyAddress(); Address->SetPort(Port);
    Listener->SetNonBlocking(true);
    if (!Listener->Bind(*Address) || !Listener->Listen(1)) { Disconnect(); Status = TEXT("Host fehlgeschlagen / Port belegt?"); return; }
    Mode = 1; Status = TEXT("HOST / TCP 28741 / warte auf Spieler 2");
#if !UE_BUILD_SHIPPING
    if (LanSmoke) UE_LOG(LogTemp, Display, TEXT("CANNONHILL_LAN_READY"));
#endif
}
void ASandLaboratoryHUD::Join(const FString& IP)
{
    Disconnect(); auto* SS = ISocketSubsystem::Get(PLATFORM_SOCKETSUBSYSTEM);
    FIPv4Address IPv4;
    if (!FIPv4Address::Parse(IP, IPv4))
    {
        Status = TEXT("Ungueltige IPv4-Adresse");
        UE_LOG(LogTemp, Warning, TEXT("Cannon Hill LAN: invalid IPv4 address '%s'"), *IP);
        return;
    }
    auto Address = SS->CreateInternetAddr(FNetworkProtocolTypes::IPv4);
    Address->SetIp(IPv4.Value);
    Address->SetPort(Port);
    Peer = SS->CreateSocket(NAME_Stream, TEXT("CannonHillClient"), FNetworkProtocolTypes::IPv4);
    if (!Peer) { Status = TEXT("Socket konnte nicht erstellt werden"); return; }
    Peer->SetNonBlocking(true);
    Peer->SetNoDelay(true);
    if (!Peer->Connect(*Address))
    {
        const ESocketErrors Error = SS->GetLastErrorCode();
        UE_LOG(LogTemp, Warning, TEXT("Cannon Hill LAN: connect to %s failed (%d)"), *IP, int32(Error));
        Disconnect();
        Status = TEXT("Verbindung zum Host fehlgeschlagen");
        return;
    }
    Mode = 2;
    Player = 1;
    Connecting = true;
    ConnectDeadline = FPlatformTime::Seconds() + 8.0;
    Status = TEXT("VERBINDE / ") + IP;
#if !UE_BUILD_SHIPPING
    if (LanSmoke) UE_LOG(LogTemp, Display, TEXT("CANNONHILL_LAN_JOIN address=%s"), *Address->ToString(true));
#endif
}
void ASandLaboratoryHUD::Send(const TSharedRef<FJsonObject>& Message)
{
    if (!Peer || Connecting || Outgoing.Num() > 0) return;
    FString Text; auto Writer = TJsonWriterFactory<TCHAR, TCondensedJsonPrintPolicy<TCHAR>>::Create(&Text);
    FJsonSerializer::Serialize(Message, Writer); Text += TEXT("\n");
    FTCHARToUTF8 Bytes(*Text); Outgoing.Append(reinterpret_cast<const uint8*>(Bytes.Get()), Bytes.Length());
}
TSharedRef<FJsonObject> ASandLaboratoryHUD::Snapshot() const
{
    auto O = Obj(); O->SetStringField(TEXT("type"), TEXT("state")); Number(O, TEXT("version"), FSandSimulation::ProtocolVersion);
    O->SetBoolField(TEXT("roundOver"), Sim.RoundOver);
    Number(O, TEXT("winner"), Sim.Winner);
    Number(O, TEXT("dropKind"), Sim.Drop.Kind);
    Number(O, TEXT("dropX"), Sim.Drop.X);
    Number(O, TEXT("dropY"), Sim.Drop.Y);
    Number(O, TEXT("tick"), Sim.Tick); Number(O, TEXT("impacts"), Sim.Impacts);
    O->SetStringField(TEXT("cells"), FBase64::Encode(Sim.Cells));
    TArray<TSharedPtr<FJsonValue>> Cannons, Shots;
    for (const auto& C : Sim.Cannons)
    {
        auto V = Obj(); Number(V, TEXT("x"), C.X); Number(V, TEXT("y"), C.Y); Number(V, TEXT("vy"), C.VY);
        Number(V, TEXT("weapon"), C.Weapon); Number(V, TEXT("angle"), C.Angle); Number(V, TEXT("power"), C.Power); Number(V, TEXT("cooldown"), C.Cooldown); Number(V, TEXT("tilt"), C.Tilt);
        Number(V, TEXT("hp"), C.HP); Number(V, TEXT("shield"), C.Shield); Number(V, TEXT("rapid"), C.Rapid);
        Cannons.Add(MakeShared<FJsonValueObject>(V));
    }
    for (const auto& S : Sim.Shots)
    {
        auto V = Obj(); Number(V, TEXT("x"), S.X); Number(V, TEXT("y"), S.Y); Number(V, TEXT("vx"), S.VX); Number(V, TEXT("vy"), S.VY); Number(V, TEXT("age"), S.Age); Number(V, TEXT("weapon"), S.Weapon);
        Number(V, TEXT("owner"), S.Owner);
        Shots.Add(MakeShared<FJsonValueObject>(V));
    }
    O->SetArrayField(TEXT("cannons"), Cannons); O->SetArrayField(TEXT("shots"), Shots); return O;
}
void ASandLaboratoryHUD::ReadMessage(const TSharedPtr<FJsonObject>& O)
{
    if (!O) return;
    if (Get(O, TEXT("version")) != FSandSimulation::ProtocolVersion) { Status = TEXT("Protokoll unpassend / beide Spieler brauchen Unreal v6"); return; }
    FString Type; if (!O->TryGetStringField(TEXT("type"), Type)) return;
    if (Mode == 1 && Type == TEXT("input"))
    {
        bool Trigger = false; O->TryGetBoolField(TEXT("fire"), Trigger);
        Sim.Input(1, float(Get(O, TEXT("angle"), 45)), float(Get(O, TEXT("power"), 55)), Trigger, float(Get(O, TEXT("drive"))), int32(FMath::Clamp(Get(O, TEXT("weapon")), 0.0, 2.0)));
    }
    else if (Mode == 2 && Type == TEXT("state"))
    {
        FString Encoded; const TArray<TSharedPtr<FJsonValue>>* Cannons; const TArray<TSharedPtr<FJsonValue>>* Shots;
        if (!O->TryGetStringField(TEXT("cells"), Encoded) || !O->TryGetArrayField(TEXT("cannons"), Cannons) || !O->TryGetArrayField(TEXT("shots"), Shots)) return;
        TArray<uint8> Cells;
        if (!FBase64::Decode(Encoded, Cells) || Cells.Num() != FSandSimulation::W * FSandSimulation::H || Cannons->Num() != 2 || Shots->Num() > 32) return;
        for (const auto& V : *Cannons) if (V->Type != EJson::Object) return;
        for (const auto& V : *Shots) if (V->Type != EJson::Object) return;
        const double Kind = Get(O, TEXT("dropKind"), -2);
        const double X = Get(O, TEXT("dropX"), -1), Y = Get(O, TEXT("dropY"), -1);
        if ((Kind != -1 && Kind != 0 && Kind != 1 && Kind != 2) ||
            (Kind >= 0 && (X < 0 || X >= FSandSimulation::W || Y < 0 || Y >= FSandSimulation::H))) return;
        Sim.Drop = { int32(Kind), float(X), float(Y) };
        O->TryGetBoolField(TEXT("roundOver"), Sim.RoundOver);
        Sim.Winner = int32(FMath::Clamp(Get(O, TEXT("winner"), -1), -1.0, 1.0));
        Sim.Cells = MoveTemp(Cells); Sim.Tick = int32(Get(O, TEXT("tick"))); Sim.Impacts = int32(Get(O, TEXT("impacts")));
        for (int32 I = 0; I < 2; ++I)
        {
            auto V = (*Cannons)[I]->AsObject(); auto& C = Sim.Cannons[I];
            C.HP = int32(FMath::Clamp(Get(V, TEXT("hp"), FSandSimulation::MaxHP), 0.0, double(FSandSimulation::MaxHP)));
            C.Shield = FMath::Clamp(Get(V, TEXT("shield")), 0.0, 8.0);
            C.Rapid = FMath::Clamp(Get(V, TEXT("rapid")), 0.0, 8.0);
            C.X = Get(V, TEXT("x")); C.Y = Get(V, TEXT("y")); C.VY = Get(V, TEXT("vy"));
            C.Weapon = int32(FMath::Clamp(Get(V, TEXT("weapon")), 0.0, 2.0)); C.Angle = Get(V, TEXT("angle")); C.Power = Get(V, TEXT("power")); C.Cooldown = Get(V, TEXT("cooldown")); C.Tilt = Get(V, TEXT("tilt"));
        }
        Sim.Shots.Reset(); for (const auto& Value : *Shots)
        {
            auto V = Value->AsObject(); FShotState S; S.X = Get(V, TEXT("x")); S.Y = Get(V, TEXT("y")); S.VX = Get(V, TEXT("vx")); S.VY = Get(V, TEXT("vy")); S.Age = Get(V, TEXT("age")); S.Weapon = int32(FMath::Clamp(Get(V, TEXT("weapon")), 0.0, 2.0)); S.Owner = int32(FMath::Clamp(Get(V, TEXT("owner")), 0.0, 1.0)); Sim.Shots.Add(S);
        }
        Status = FString::Printf(TEXT("LAN / Spieler 2 / Host-Tick %d"), Sim.Tick);
#if !UE_BUILD_SHIPPING
        SmokeReceivedSnapshot = true;
#endif
    }
}
void ASandLaboratoryHUD::ClosePeer(const TCHAR* Reason)
{
    UE_LOG(LogTemp, Display, TEXT("Cannon Hill LAN: %s"), Reason);
    Peer->Close();
    ISocketSubsystem::Get(PLATFORM_SOCKETSUBSYSTEM)->DestroySocket(Peer);
    Peer = nullptr;
    Connecting = false;
    Incoming.Empty();
    Outgoing.Reset();
    Fire = false;
    Status = TEXT("VERBINDUNG GETRENNT / erneut verbinden");
}
void ASandLaboratoryHUD::Network()
{
    bool Pending = false;
    if (Listener && Listener->HasPendingConnection(Pending) && Pending)
    {
        auto* Next = Listener->Accept(TEXT("CannonHillPeer"));
        if (Next)
        {
            if (Peer) { Next->Close(); ISocketSubsystem::Get(PLATFORM_SOCKETSUBSYSTEM)->DestroySocket(Next); }
            else
            {
                Peer = Next;
                Peer->SetNonBlocking(true);
                Peer->SetNoDelay(true);
                Status = TEXT("HOST / Spieler 2 verbunden");
#if !UE_BUILD_SHIPPING
                if (LanSmoke) UE_LOG(LogTemp, Display, TEXT("CANNONHILL_LAN_ACCEPT"));
#endif
            }
        }
    }
    if (!Peer) return;
    if (Connecting)
    {
        if (Peer->Wait(ESocketWaitConditions::WaitForWrite, FTimespan::Zero()))
        {
            Connecting = false;
        }
        else
        {
            if (FPlatformTime::Seconds() >= ConnectDeadline) ClosePeer(TEXT("TCP connect timed out"));
            return;
        }
    }
    if (Outgoing.Num() > 0)
    {
        int32 Sent = 0;
        if (Peer->Send(Outgoing.GetData(), Outgoing.Num(), Sent))
        {
            if (Sent > 0) Outgoing.RemoveAt(0, Sent, EAllowShrinking::No);
        }
        else
        {
            const auto Error = ISocketSubsystem::Get(PLATFORM_SOCKETSUBSYSTEM)->GetLastErrorCode();
            if (Error != SE_EWOULDBLOCK && Error != SE_EINTR)
            {
                UE_LOG(LogTemp, Warning, TEXT("Cannon Hill LAN: TCP send error %d"), int32(Error));
                ClosePeer(TEXT("TCP send failed"));
                return;
            }
        }
    }
    // Readability also signals an orderly shutdown. HasPendingData alone
    // cannot distinguish a closed stream from an open stream with no payload.
    for (int32 Reads = 0; Reads < MaxReadsPerTick &&
        Peer->Wait(ESocketWaitConditions::WaitForRead, FTimespan::Zero()); ++Reads)
    {
        uint8 Bytes[65537];
        int32 Read = 0;
        if (!Peer->Recv(Bytes, 65536, Read))
        {
            ClosePeer(TEXT("TCP stream closed"));
            return;
        }
        if (Read <= 0) break;
        Bytes[Read] = 0;
        Incoming += UTF8_TO_TCHAR(reinterpret_cast<const char*>(Bytes));
        // TCP can batch several complete snapshots while the client is loading.
        // Apply the limit to a single line, not to the combined batch.
        int32 Index;
        while (Incoming.FindChar('\n', Index))
        {
            if (Index > MaxMessageChars) { ClosePeer(TEXT("TCP message too large")); return; }
            FString Line = Incoming.Left(Index);
            Incoming.RightChopInline(Index + 1, EAllowShrinking::No);
            TSharedPtr<FJsonObject> O;
            auto Reader = TJsonReaderFactory<>::Create(Line);
            if (FJsonSerializer::Deserialize(Reader, O)) ReadMessage(O);
        }
        if (Incoming.Len() > MaxMessageChars) { ClosePeer(TEXT("TCP message too large")); return; }
    }
}
void ASandLaboratoryHUD::Tick(float DeltaSeconds)
{
    Super::Tick(DeltaSeconds);
    auto* PC = GetOwningPlayerController();
    if (!PC) return;
    if (Mode == 3 && RustRetryAt > 0 && FPlatformTime::Seconds() >= RustRetryAt) OpenRust();
    else if (Mode != 3) Network();
    const float Delta = FMath::Min(DeltaSeconds, .15f);
    Angle = FMath::Clamp(Angle + (int32(PC->IsInputKeyDown(EKeys::Up)) - int32(PC->IsInputKeyDown(EKeys::Down))) * Delta * 40, 5.f, 85.f);
    Power = FMath::Clamp(Power + (int32(PC->IsInputKeyDown(EKeys::Right)) - int32(PC->IsInputKeyDown(EKeys::Left))) * Delta * 30, 15.f, 90.f);
    float Drive = float(int32(PC->IsInputKeyDown(EKeys::D)) - int32(PC->IsInputKeyDown(EKeys::A)));
    if (Mode != 3 && PC->WasInputKeyJustPressed(EKeys::One)) Weapon = 0;
    if (Mode != 3 && PC->WasInputKeyJustPressed(EKeys::Two)) Weapon = 1;
    if (Mode != 3 && PC->WasInputKeyJustPressed(EKeys::Three)) Weapon = 2;
    Fire |= PC->WasInputKeyJustPressed(EKeys::SpaceBar);
    if (Mode == 0 && PC->WasInputKeyJustPressed(EKeys::Tab)) { Sim.Cannons[Player].Drive = 0; Fire = false; Player = 1 - Player; Weapon = Sim.Cannons[Player].Weapon; Angle = Sim.Cannons[Player].Angle; Power = Sim.Cannons[Player].Power; }
    if (PC->WasInputKeyJustPressed(EKeys::H)) Host();
    if (PC->WasInputKeyJustPressed(EKeys::J)) { FString IP = TEXT("127.0.0.1"); if (FParse::Value(FCommandLine::Get(), TEXT("-RustServer="), IP)) JoinRust(IP); else { FParse::Value(FCommandLine::Get(), TEXT("-Join="), IP); Join(IP); } }
    if (PC->WasInputKeyJustPressed(EKeys::O)) { Disconnect(); Sim.Reset(); }
    if (PC->WasInputKeyJustPressed(EKeys::R))
    {
        if (Mode == 3) SendRust(true);
        else if (Mode != 2) Sim.Reset();
    }
    if (Mode != 2 && Mode != 3 && PC->WasInputKeyJustPressed(EKeys::B)) Sim.Crater(Sim.Cannons[Player].X, Sim.Cannons[Player].Y + 8, 12);
#if !UE_BUILD_SHIPPING
    if (LanSmoke) UpdateLanSmoke(Delta, Drive);
#endif
    Clock += Delta;
    while (Clock >= FSandSimulation::Dt) { Clock -= FSandSimulation::Dt; if (Mode != 2 && Mode != 3) { Sim.Input(Player, Angle, Power, Fire, Drive, Weapon); Sim.Step(); Fire = false; } }
    SendClock += Delta;
    if (SendClock >= .1f)
    {
        SendClock = 0;
        if (Mode == 3) { if (SendRust(false) || RustPlayers != 2) Fire = false; }
        else if (Mode == 1) Send(Snapshot());
        else if (Mode == 2 && Peer && !Connecting && Outgoing.Num() == 0)
        { auto O = Obj(); O->SetStringField(TEXT("type"), TEXT("input")); Number(O, TEXT("version"), FSandSimulation::ProtocolVersion); Number(O, TEXT("angle"), Angle); Number(O, TEXT("power"), Power); Number(O, TEXT("drive"), Drive); Number(O, TEXT("weapon"), Weapon); O->SetBoolField(TEXT("fire"), Fire); Send(O); Fire = false; }
    }
}
#if !UE_BUILD_SHIPPING
void ASandLaboratoryHUD::UpdateLanSmoke(float Delta, float& Drive)
{
    if (!Peer || (Mode == 2 && !SmokeReceivedSnapshot)) return;
    if (Mode == 1 && SmokeSeconds == 0.f) Sim.Reset();
    SmokeSeconds += Delta;
    if (!SmokeFired && SmokeSeconds >= .4f)
    {
        Fire = true;
        SmokeFired = true;
    }
    if (Mode != 2) return;
    Drive = SmokeSeconds < 1.2f ? -1.f : 0.f;
    Weapon = 1;
    for (const auto& Shot : Sim.Shots)
    {
        SmokeSawHostShot |= Shot.Owner == 0;
        SmokeSawGuestShot |= Shot.Owner == 1 && Shot.Weapon == 1;
    }
    SmokeSawDrop |= Sim.Drop.Kind >= 0;
    if (!SmokeReported && SmokeSawHostShot && SmokeSawGuestShot && SmokeSawDrop &&
        Sim.Cannons[1].X < 198.f && Sim.Cannons[1].Weapon == 1 && Sim.Impacts >= 2)
    {
        SmokeReported = true;
        UE_LOG(LogTemp, Display, TEXT("CANNONHILL_LAN_PASS tick=%d impacts=%d guestX=%.2f weapon=%d"),
            Sim.Tick, Sim.Impacts, Sim.Cannons[1].X, Sim.Cannons[1].Weapon);
    }
}
#endif
void ASandLaboratoryHUD::DrawHUD()
{
    Super::DrawHUD();
    if (!Canvas) return;
    const float SX = Canvas->SizeX / 1100.f, SY = Canvas->SizeY / 760.f;
    auto Rect = [&](float X, float Y, float W, float H, FLinearColor C) { DrawRect(C, X * SX, Y * SY, W * SX, H * SY); };
    auto Text = [&](const FString& T, float X, float Y, FLinearColor C, float Scale = 1.f) { DrawText(T, C, X * SX, Y * SY, GEngine->GetMediumFont(), Scale * SX); };
    auto Line = [&](FVector2D A, FVector2D B, FLinearColor C, float Thickness) { DrawLine(A.X * SX, A.Y * SY, B.X * SX, B.Y * SY, C, Thickness * SX); };
    Rect(0, 0, 1100, 760, FLinearColor(.035f, .06f, .09f));
    const FLinearColor Gold(.957f, .835f, .604f), Muted(.55f, .66f, .73f);
    Text(TEXT("CANNON HILL / SAND LABORATORY"), 38, 20, Gold, 1.4f);
    Text(TEXT("UNREAL / 01     Echtzeit-Artillerie / Sand / LAN fuer zwei"), 38, 60, Muted);
    Text(TEXT("H Host     J Verbinden (127.0.0.1 oder -Join=IP)     O Offline     R Neustart     B Boden loesen"), 38, 108, Gold, .8f);
    Text(Status + FString::Printf(TEXT(" | WAFFE: %s"), Weapon == 1 ? TEXT("SCHWER") : Weapon == 2 ? TEXT("SCHNELL") : TEXT("STANDARD")), 38, 144, FLinearColor(.55f, .86f, .69f), .8f);
    const auto& Current = Sim.Cannons[Player];
    FString BuffText = Sim.Drop.Kind >= 0 ? FString::Printf(TEXT("Kiste: %s"), BuffNames[Sim.Drop.Kind]) : TEXT("Kiste abschiessen");
    if (Mode == 3 && RustWarning >= 0) BuffText = TEXT("Abwurf in Kuerze");
    if (Sim.RoundOver) BuffText = Sim.Winner < 0 ? TEXT("Unentschieden") : FString::Printf(TEXT("Spieler %d gewinnt / R Neustart"), Sim.Winner + 1);
    Text(BuffText + FString::Printf(TEXT("  |  Schild %.0fs  Schnellfeuer %.0fs"), Current.Shield, Current.Rapid), 38, 162, Gold, .75f);
    for (int32 Y = 0; Y < FSandSimulation::H; ++Y)
    {
        // Sky is one run; sand uses a small palette to limit Canvas draw calls.
        for (int32 X = 0; X < FSandSimulation::W;)
        {
            uint8 Cell = Sim.Cells[Y * FSandSimulation::W + X]; int32 End = X + 1;
            while (End < FSandSimulation::W && Sim.Cells[Y * FSandSimulation::W + End] == Cell) ++End;
            FLinearColor C(.05f + Y * .0003f, .10f + Y * .0003f, .15f + Y * .0003f);
            if (Cell == 1) C = FLinearColor(.77f, .55f, .32f); else if (Cell == 2) C = FLinearColor(.204f, .282f, .329f);
            Rect(70 + X * 4, 180 + Y * 4, (End - X) * 4, 4, C); X = End;
        }
    }
    for (int32 I = 0; I < 2; ++I)
    {
        const auto& C = Sim.Cannons[I]; FVector2D P(70 + C.X * 4, 180 + C.Y * 4);
        FLinearColor Color = I == 0 ? FLinearColor(.47f, .85f, .77f) : FLinearColor(.94f, .61f, .53f);
        if (C.HP == 0) Color = FLinearColor::Gray;
        Text(FString::Printf(TEXT("%d LP"), C.HP), P.X - 22, P.Y - 31, Color, .75f);
        FVector2D Axis(FMath::Cos(C.Tilt) * 12, FMath::Sin(C.Tilt) * 12);
        Line(P - Axis, P + Axis, Color, 9);
        FVector2D D(FMath::Cos(FMath::DegreesToRadians(C.Angle)) * (I == 0 ? 1 : -1), -FMath::Sin(FMath::DegreesToRadians(C.Angle)));
        Line(P - FVector2D(0, 4), P - FVector2D(0, 4) + D * 28, Color, 6);
        for (int32 Wheel : { -1, 1 }) Rect(P.X + Axis.X * Wheel - 5, P.Y + Axis.Y * Wheel + 1, 10, 10, Color);
        if (Player == I) Rect(P.X - 3, P.Y - 38, 6, 6, Color);
    }
    if (Mode == 3 && RustWarning >= 0)
    {
        const float X = 70 + RustWarning * 4;
        Line(FVector2D(X - 9, 188), FVector2D(X, 198), Gold, 2);
        Line(FVector2D(X, 198), FVector2D(X + 9, 188), Gold, 2);
    }
    if (Sim.Drop.Kind >= 0)
    {
        const FVector2D P(70 + Sim.Drop.X * 4, 180 + Sim.Drop.Y * 4);
        const FLinearColor Tint = Sim.Drop.Kind == 0 ? FLinearColor::Green : Sim.Drop.Kind == 1 ? FLinearColor(.4f, .75f, 1.f) : Gold;
        Line(P + FVector2D(-12, -14), P + FVector2D(12, -14), Tint, 3);
        Line(P + FVector2D(-12, -14), P, Tint, 1);
        Line(P + FVector2D(12, -14), P, Tint, 1);
        Rect(P.X - 7, P.Y - 5, 14, 10, Tint);
    }
    for (const auto& S : Sim.Shots) Rect(70 + S.X * 4 - 3, 180 + S.Y * 4 - 3, 6, 6, Gold);
    Text(FString::Printf(TEXT("SPIELER %d    WINKEL %.0f    STAERKE %.0f    |    EINSCHLAEGE %d    SAND %d"), Player + 1, Angle, Power, Sim.Impacts, Sim.Moved), 38, 708, Gold, .8f);
    Text(Mode == 3 ? TEXT("Rust-Server | Pfeile: Winkel und Staerke | Leertaste Feuer | R Neustart (Spieler 1)") : TEXT("A/D Fahren | 1 Standard  2 Schwer  3 Schnell | Pfeile Zielen | Leertaste Feuer | Tab Spieler"), 38, 738, Muted, .8f);
}
void ASandLaboratoryHUD::EndPlay(const EEndPlayReason::Type Reason) { Disconnect(); Super::EndPlay(Reason); }
