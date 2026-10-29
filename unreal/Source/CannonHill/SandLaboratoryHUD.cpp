#include "SandLaboratoryHUD.h"
#include "Engine/Canvas.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Policies/CondensedJsonPrintPolicy.h"
#include "GameFramework/PlayerController.h"
#include "InputCoreTypes.h"
#include "Sockets.h"
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
TSharedRef<FJsonObject> Obj() { return MakeShared<FJsonObject>(); }
void Number(const TSharedRef<FJsonObject>& O, const TCHAR* K, double V) { O->SetNumberField(K, V); }
double Get(const TSharedPtr<FJsonObject>& O, const TCHAR* K, double Default = 0) { double V; return O->TryGetNumberField(K, V) && FMath::IsFinite(V) ? V : Default; }
}
void ASandLaboratoryHUD::BeginPlay()
{
    Super::BeginPlay();
    GetOwningPlayerController()->bShowMouseCursor = true;
    FString Address;
    if (FParse::Param(FCommandLine::Get(), TEXT("Host"))) Host();
    else if (FParse::Value(FCommandLine::Get(), TEXT("Join="), Address)) Join(Address);
}
void ASandLaboratoryHUD::Disconnect()
{
    auto* SS = ISocketSubsystem::Get(PLATFORM_SOCKETSUBSYSTEM);
    for (FSocket* S : { Peer, Listener }) if (S) { S->Close(); SS->DestroySocket(S); }
    Peer = Listener = nullptr; Incoming.Empty(); Outgoing.Reset(); Mode = Player = 0;
    Status = TEXT("OFFLINE / Tab wechselt die Kanone");
}
void ASandLaboratoryHUD::Host()
{
    Disconnect(); auto* SS = ISocketSubsystem::Get(PLATFORM_SOCKETSUBSYSTEM);
    Listener = SS->CreateSocket(NAME_Stream, TEXT("CannonHillListener"), false);
    if (!Listener) { Status = TEXT("Socket konnte nicht erstellt werden"); return; }
    auto Address = SS->CreateInternetAddr(); Address->SetAnyAddress(); Address->SetPort(Port);
    Listener->SetNonBlocking(true);
    if (!Listener->Bind(*Address) || !Listener->Listen(1)) { Disconnect(); Status = TEXT("Host fehlgeschlagen / Port belegt?"); return; }
    Mode = 1; Status = TEXT("HOST / TCP 28741 / warte auf Spieler 2");
}
void ASandLaboratoryHUD::Join(const FString& IP)
{
    Disconnect(); auto* SS = ISocketSubsystem::Get(PLATFORM_SOCKETSUBSYSTEM);
    bool Valid = false; auto Address = SS->CreateInternetAddr(); Address->SetIp(*IP, Valid); Address->SetPort(Port);
    if (!Valid) { Status = TEXT("Ungueltige IP-Adresse"); return; }
    Peer = SS->CreateSocket(NAME_Stream, TEXT("CannonHillClient"), false);
    if (!Peer) { Status = TEXT("Socket konnte nicht erstellt werden"); return; }
    Peer->SetNonBlocking(true); Peer->SetNoDelay(true);
    Peer->Connect(*Address); Mode = 2; Player = 1; Status = TEXT("VERBINDE / ") + IP;
}
void ASandLaboratoryHUD::Send(const TSharedRef<FJsonObject>& Message)
{
    if (!Peer || Outgoing.Num() > 0 || Peer->GetConnectionState() != SCS_Connected) return;
    FString Text; auto Writer = TJsonWriterFactory<TCHAR, TCondensedJsonPrintPolicy<TCHAR>>::Create(&Text);
    FJsonSerializer::Serialize(Message, Writer); Text += TEXT("\n");
    FTCHARToUTF8 Bytes(*Text); Outgoing.Append(reinterpret_cast<const uint8*>(Bytes.Get()), Bytes.Length());
}
TSharedRef<FJsonObject> ASandLaboratoryHUD::Snapshot() const
{
    auto O = Obj(); O->SetStringField(TEXT("type"), TEXT("state")); Number(O, TEXT("version"), 1);
    Number(O, TEXT("tick"), Sim.Tick); Number(O, TEXT("impacts"), Sim.Impacts);
    O->SetStringField(TEXT("cells"), FBase64::Encode(Sim.Cells));
    TArray<TSharedPtr<FJsonValue>> Cannons, Shots;
    for (const auto& C : Sim.Cannons)
    {
        auto V = Obj(); Number(V, TEXT("x"), C.X); Number(V, TEXT("y"), C.Y); Number(V, TEXT("vy"), C.VY);
        Number(V, TEXT("angle"), C.Angle); Number(V, TEXT("power"), C.Power); Number(V, TEXT("cooldown"), C.Cooldown); Number(V, TEXT("tilt"), C.Tilt);
        Cannons.Add(MakeShared<FJsonValueObject>(V));
    }
    for (const auto& S : Sim.Shots)
    {
        auto V = Obj(); Number(V, TEXT("x"), S.X); Number(V, TEXT("y"), S.Y); Number(V, TEXT("vx"), S.VX); Number(V, TEXT("vy"), S.VY); Number(V, TEXT("age"), S.Age);
        Shots.Add(MakeShared<FJsonValueObject>(V));
    }
    O->SetArrayField(TEXT("cannons"), Cannons); O->SetArrayField(TEXT("shots"), Shots); return O;
}
void ASandLaboratoryHUD::ReadMessage(const TSharedPtr<FJsonObject>& O)
{
    if (!O || Get(O, TEXT("version")) != 1) return;
    FString Type; if (!O->TryGetStringField(TEXT("type"), Type)) return;
    if (Mode == 1 && Type == TEXT("input"))
    {
        bool Trigger = false; O->TryGetBoolField(TEXT("fire"), Trigger);
        Sim.Input(1, float(Get(O, TEXT("angle"), 45)), float(Get(O, TEXT("power"), 55)), Trigger);
    }
    else if (Mode == 2 && Type == TEXT("state"))
    {
        FString Encoded; const TArray<TSharedPtr<FJsonValue>>* Cannons; const TArray<TSharedPtr<FJsonValue>>* Shots;
        if (!O->TryGetStringField(TEXT("cells"), Encoded) || !O->TryGetArrayField(TEXT("cannons"), Cannons) || !O->TryGetArrayField(TEXT("shots"), Shots)) return;
        TArray<uint8> Cells;
        if (!FBase64::Decode(Encoded, Cells) || Cells.Num() != FSandSimulation::W * FSandSimulation::H || Cannons->Num() != 2 || Shots->Num() > 32) return;
        for (const auto& V : *Cannons) if (V->Type != EJson::Object) return;
        for (const auto& V : *Shots) if (V->Type != EJson::Object) return;
        Sim.Cells = MoveTemp(Cells); Sim.Tick = int32(Get(O, TEXT("tick"))); Sim.Impacts = int32(Get(O, TEXT("impacts")));
        for (int32 I = 0; I < 2; ++I)
        {
            auto V = (*Cannons)[I]->AsObject(); auto& C = Sim.Cannons[I];
            C.X = Get(V, TEXT("x")); C.Y = Get(V, TEXT("y")); C.VY = Get(V, TEXT("vy"));
            C.Angle = Get(V, TEXT("angle")); C.Power = Get(V, TEXT("power")); C.Cooldown = Get(V, TEXT("cooldown")); C.Tilt = Get(V, TEXT("tilt"));
        }
        Sim.Shots.Reset(); for (const auto& Value : *Shots)
        {
            auto V = Value->AsObject(); FShotState S; S.X = Get(V, TEXT("x")); S.Y = Get(V, TEXT("y")); S.VX = Get(V, TEXT("vx")); S.VY = Get(V, TEXT("vy")); S.Age = Get(V, TEXT("age")); Sim.Shots.Add(S);
        }
        Status = FString::Printf(TEXT("LAN / Spieler 2 / Host-Tick %d"), Sim.Tick);
    }
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
            else { Peer = Next; Peer->SetNonBlocking(true); Peer->SetNoDelay(true); Status = TEXT("HOST / Spieler 2 verbunden"); }
        }
    }
    if (!Peer) return;
    if (Peer->GetConnectionState() == SCS_ConnectionError)
    {
        Peer->Close(); ISocketSubsystem::Get(PLATFORM_SOCKETSUBSYSTEM)->DestroySocket(Peer); Peer = nullptr;
        Incoming.Empty(); Outgoing.Reset(); Status = TEXT("VERBINDUNG GETRENNT / erneut verbinden"); return;
    }
    if (Outgoing.Num() > 0)
    {
        int32 Sent = 0; if (Peer->Send(Outgoing.GetData(), Outgoing.Num(), Sent) && Sent > 0) Outgoing.RemoveAt(0, Sent, EAllowShrinking::No);
    }
    uint32 Available = 0;
    while (Peer->HasPendingData(Available) && Available > 0)
    {
        uint8 Bytes[65537]; int32 Read = 0;
        if (!Peer->Recv(Bytes, FMath::Min<int32>(65536, Available), Read) || Read <= 0) break;
        Bytes[Read] = 0; Incoming += UTF8_TO_TCHAR(reinterpret_cast<const char*>(Bytes));
        if (Incoming.Len() > 262144) { Disconnect(); Status = TEXT("Nachricht zu gross"); return; }
    }
    int32 Index;
    while (Incoming.FindChar('\n', Index))
    {
        FString Line = Incoming.Left(Index); Incoming = Incoming.Mid(Index + 1);
        TSharedPtr<FJsonObject> O; auto Reader = TJsonReaderFactory<>::Create(Line);
        if (FJsonSerializer::Deserialize(Reader, O)) ReadMessage(O);
    }
}
void ASandLaboratoryHUD::DrawHUD()
{
    Super::DrawHUD(); if (!Canvas) return;
    auto* PC = GetOwningPlayerController(); Network();
    const float Delta = FMath::Min(GetWorld()->GetDeltaSeconds(), .15f);
    Angle = FMath::Clamp(Angle + (int32(PC->IsInputKeyDown(EKeys::Up)) - int32(PC->IsInputKeyDown(EKeys::Down))) * Delta * 40, 5.f, 85.f);
    Power = FMath::Clamp(Power + (int32(PC->IsInputKeyDown(EKeys::Right)) - int32(PC->IsInputKeyDown(EKeys::Left))) * Delta * 30, 15.f, 90.f);
    Fire |= PC->WasInputKeyJustPressed(EKeys::SpaceBar);
    if (Mode == 0 && PC->WasInputKeyJustPressed(EKeys::Tab)) { Player = 1 - Player; Angle = Sim.Cannons[Player].Angle; Power = Sim.Cannons[Player].Power; }
    if (PC->WasInputKeyJustPressed(EKeys::H)) Host();
    if (PC->WasInputKeyJustPressed(EKeys::J)) { FString IP = TEXT("127.0.0.1"); FParse::Value(FCommandLine::Get(), TEXT("Join="), IP); Join(IP); }
    if (PC->WasInputKeyJustPressed(EKeys::O)) { Disconnect(); Sim.Reset(); }
    if (Mode != 2 && PC->WasInputKeyJustPressed(EKeys::R)) Sim.Reset();
    if (Mode != 2 && PC->WasInputKeyJustPressed(EKeys::B)) Sim.Crater(Sim.Cannons[Player].X, Sim.Cannons[Player].Y + 8, 12);
    Clock += Delta;
    while (Clock >= FSandSimulation::Dt) { Clock -= FSandSimulation::Dt; if (Mode != 2) { Sim.Input(Player, Angle, Power, Fire); Sim.Step(); Fire = false; } }
    SendClock += Delta;
    if (SendClock >= .1f)
    {
        SendClock = 0;
        if (Mode == 1) Send(Snapshot());
        else if (Mode == 2 && Peer && Outgoing.Num() == 0 && Peer->GetConnectionState() == SCS_Connected)
        { auto O = Obj(); O->SetStringField(TEXT("type"), TEXT("input")); Number(O, TEXT("version"), 1); Number(O, TEXT("angle"), Angle); Number(O, TEXT("power"), Power); O->SetBoolField(TEXT("fire"), Fire); Send(O); Fire = false; }
    }
    const float SX = Canvas->SizeX / 1100.f, SY = Canvas->SizeY / 760.f;
    auto Rect = [&](float X, float Y, float W, float H, FLinearColor C) { DrawRect(C, X * SX, Y * SY, W * SX, H * SY); };
    auto Text = [&](const FString& T, float X, float Y, FLinearColor C, float Scale = 1.f) { DrawText(T, C, X * SX, Y * SY, GEngine->GetMediumFont(), Scale * SX); };
    auto Line = [&](FVector2D A, FVector2D B, FLinearColor C, float Thickness) { DrawLine(A.X * SX, A.Y * SY, B.X * SX, B.Y * SY, C, Thickness * SX); };
    Rect(0, 0, 1100, 760, FLinearColor(.035f, .06f, .09f));
    const FLinearColor Gold(.957f, .835f, .604f), Muted(.55f, .66f, .73f);
    Text(TEXT("CANNON HILL / SAND LABORATORY"), 38, 20, Gold, 1.4f);
    Text(TEXT("UNREAL / 01     Echtzeit-Artillerie / Sand / LAN fuer zwei"), 38, 60, Muted);
    Text(TEXT("H Host     J Verbinden (127.0.0.1 oder -Join=IP)     O Offline     R Neustart     B Boden loesen"), 38, 108, Gold, .8f);
    Text(Status, 38, 144, FLinearColor(.55f, .86f, .69f), .8f);
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
        FVector2D Axis(FMath::Cos(C.Tilt) * 12, FMath::Sin(C.Tilt) * 12);
        Line(P - Axis, P + Axis, Color, 9);
        FVector2D D(FMath::Cos(FMath::DegreesToRadians(C.Angle)) * (I == 0 ? 1 : -1), -FMath::Sin(FMath::DegreesToRadians(C.Angle)));
        Line(P - FVector2D(0, 4), P - FVector2D(0, 4) + D * 28, Color, 6);
        for (int32 Wheel : { -1, 1 }) Rect(P.X + Axis.X * Wheel - 5, P.Y + Axis.Y * Wheel + 1, 10, 10, Color);
        if (Player == I) Rect(P.X - 3, P.Y - 38, 6, 6, Color);
    }
    for (const auto& S : Sim.Shots) Rect(70 + S.X * 4 - 3, 180 + S.Y * 4 - 3, 6, 6, Gold);
    Text(FString::Printf(TEXT("SPIELER %d    WINKEL %.0f    STAERKE %.0f    |    EINSCHLAEGE %d    SAND %d"), Player + 1, Angle, Power, Sim.Impacts, Sim.Moved), 38, 708, Gold, .8f);
    Text(TEXT("Pfeile: Winkel / Staerke     LEERTASTE Feuer     TAB Spieler (offline)"), 38, 738, Muted, .8f);
}
void ASandLaboratoryHUD::EndPlay(const EEndPlayReason::Type Reason) { Disconnect(); Super::EndPlay(Reason); }
