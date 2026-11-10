#include "SandLaboratoryHUD.h"
#include "Dom/JsonObject.h"
#include "IWebSocket.h"
#include "Serialization/JsonSerializer.h"
#include "WebSocketsModule.h"

namespace
{
constexpr int32 TerrainSize = FSandSimulation::W * FSandSimulation::H;

bool DecodeTerrain(const TArray<uint8>& Packet, TArray<uint8>& Output)
{
    TArray<uint8> Cells;
    if (Packet.Num() == TerrainSize + 1 && Packet[0] == 0)
    {
        Cells.Append(Packet.GetData() + 1, TerrainSize);
        for (uint8 Cell : Cells) if (Cell > 2) return false;
    }
    else
    {
        if (Packet.Num() < 3 || Packet.Num() % 2 != 1 || Packet[0] != 1) return false;
        Cells.Reserve(TerrainSize);
        for (int32 I = 1; I < Packet.Num(); I += 2)
        {
            const int32 Count = Packet[I];
            const uint8 Cell = Packet[I + 1];
            if (!Count || Cell > 2 || Cells.Num() + Count > TerrainSize) return false;
            for (int32 J = 0; J < Count; ++J) Cells.Add(Cell);
        }
        if (Cells.Num() != TerrainSize) return false;
    }
    Output = MoveTemp(Cells);
    return true;
}

bool ReadValues(const TSharedPtr<FJsonValue>& Value, int32 Count, double* Output)
{
    const TArray<TSharedPtr<FJsonValue>>* Values = nullptr;
    if (!Value || !Value->TryGetArray(Values) || Values->Num() != Count) return false;
    for (int32 I = 0; I < Count; ++I)
        if (!(*Values)[I]->TryGetNumber(Output[I]) || !FMath::IsFinite(Output[I])) return false;
    return true;
}
}

void ASandLaboratoryHUD::JoinRust(const FString& Address)
{
    Disconnect();
    if (!Address.StartsWith(TEXT("ws://")) && !Address.StartsWith(TEXT("wss://")))
    {
        Status = TEXT("Rust-Serveradresse braucht ws:// oder wss://");
        return;
    }
    RustAddress = Address;
    Mode = 3;
    Weapon = 0;
    OpenRust();
}

void ASandLaboratoryHUD::OpenRust()
{
    CloseRust();
    Status = TEXT("VERBINDE / Rust-Server");
    const TMap<FString, FString> Headers = {{TEXT("X-Cannon-Hill-Native"), TEXT("1")}};
    RustSocket = FWebSocketsModule::Get().CreateWebSocket(RustAddress, FString(), Headers);
    RustSocket->OnMessage().AddUObject(this, &ASandLaboratoryHUD::RustText);
    RustSocket->OnBinaryMessage().AddUObject(this, &ASandLaboratoryHUD::RustBinary);
    RustSocket->OnConnectionError().AddWeakLambda(this, [this](const FString& Error)
    {
        UE_LOG(LogTemp, Verbose, TEXT("Cannon Hill Rust-WebSocket: %s"), *Error);
        RustDisconnected(true, TEXT("GETRENNT / neuer Versuch"));
    });
    RustSocket->OnClosed().AddWeakLambda(this, [this](int32 Code, const FString&, bool)
    {
        RustDisconnected(Code != 1008, Code == 1008 ? TEXT("PARTIE VOLL / erneut verbinden") : TEXT("GETRENNT / neuer Versuch"));
    });
    RustSocket->Connect();
}

void ASandLaboratoryHUD::CloseRust()
{
    if (RustSocket)
    {
        RustSocket->OnMessage().RemoveAll(this);
        RustSocket->OnBinaryMessage().RemoveAll(this);
        RustSocket->OnConnectionError().RemoveAll(this);
        RustSocket->OnClosed().RemoveAll(this);
        RustSocket->Close();
        RustSocket.Reset();
    }
    RustDisconnected(false, TEXT(""));
}

void ASandLaboratoryHUD::RustDisconnected(bool Retry, const TCHAR* Message)
{
    RustSeat = -1;
    RustPlayers = 0;
    RustRound = RustRevision = -1;
    RustWarning = -1.f;
    RustPacket.Reset();
    RustTerrain.Reset();
    Fire = false;
    RustRetryAt = Retry ? FPlatformTime::Seconds() + 1.0 : 0.0;
    Status = Message;
}

void ASandLaboratoryHUD::RustBinary(const void* Data, SIZE_T Size, bool Last)
{
    if (Size > SIZE_T(TerrainSize + 1 - RustPacket.Num()))
    {
        RustPacket.Reset();
        RustTerrain.Reset();
        return;
    }
    RustPacket.Append(static_cast<const uint8*>(Data), int32(Size));
    if (Last)
    {
        if (!DecodeTerrain(RustPacket, RustTerrain)) RustTerrain.Reset();
        RustPacket.Reset();
    }
}

void ASandLaboratoryHUD::RustText(const FString& Message)
{
    auto Reader = TJsonReaderFactory<>::Create(Message);
    TSharedPtr<FJsonObject> Object;
    if (!FJsonSerializer::Deserialize(Reader, Object) || !Object) return;
    double Protocol;
    if (!Object->TryGetNumberField(TEXT("protocol"), Protocol) || Protocol != 1)
    {
        RustDisconnected(false, TEXT("ANDERE SPIELVERSION / Rust-WebSocket v1"));
        return;
    }

    double Seat;
    if (Object->TryGetNumberField(TEXT("player"), Seat))
    {
        if (Seat == 0 || Seat == 1) RustSeat = int32(Seat);
        return;
    }
    if (RustSeat < 0) return;

    double Round, Revision, Tick, Players, Result, Warning;
    if (!Object->TryGetNumberField(TEXT("round"), Round) || Round < 0 || Round > MAX_uint32 ||
        !Object->TryGetNumberField(TEXT("revision"), Revision) || Revision < 0 || Revision > MAX_uint32 ||
        !Object->TryGetNumberField(TEXT("tick"), Tick) || Tick < 0 || Tick > MAX_int32 ||
        !Object->TryGetNumberField(TEXT("players"), Players) || Players < 0 || Players > 2 ||
        !Object->TryGetNumberField(TEXT("result"), Result) || Result < -2 || Result > 1 ||
        !Object->TryGetNumberField(TEXT("warning"), Warning) || !FMath::IsFinite(Warning)) return;
    if (int64(Revision) != RustRevision && RustTerrain.Num() != TerrainSize) return;

    const TArray<TSharedPtr<FJsonValue>>* Cannons = nullptr;
    const TArray<TSharedPtr<FJsonValue>>* Shots = nullptr;
    if (!Object->TryGetArrayField(TEXT("cannons"), Cannons) || Cannons->Num() != 2 ||
        !Object->TryGetArrayField(TEXT("shots"), Shots) || Shots->Num() > 32) return;
    double CannonValues[2][7];
    for (int32 I = 0; I < 2; ++I)
        if (!ReadValues((*Cannons)[I], 7, CannonValues[I]) || CannonValues[I][4] < 0 || CannonValues[I][4] > 1000) return;
    TArray<FShotState> NewShots;
    for (const auto& Shot : *Shots)
    {
        double Values[2];
        if (!ReadValues(Shot, 2, Values)) return;
        auto& State = NewShots.AddDefaulted_GetRef();
        State.X = Values[0];
        State.Y = Values[1];
    }
    FBuffDrop Drop;
    const auto DropValue = Object->TryGetField(TEXT("drop"));
    if (DropValue && !DropValue->IsNull())
    {
        double Values[3];
        if (!ReadValues(DropValue, 3, Values) || Values[0] < 0 || Values[0] > 2) return;
        Drop = { int32(Values[0]), float(Values[1]), float(Values[2]) };
    }
    const bool NewRound = int64(Round) != RustRound || Player != RustSeat;
    if (int64(Revision) != RustRevision) Sim.Cells = MoveTemp(RustTerrain);
    RustRevision = int64(Revision);
    RustRound = int64(Round);
    RustPlayers = int32(Players);
    RustWarning = float(Warning);
    Player = RustSeat;
    Sim.Tick = int32(Tick);
    Sim.RoundOver = Result != -2;
    Sim.Winner = Result >= 0 ? int32(Result) : -1;
    Sim.Drop = Drop;
    Sim.Shots = MoveTemp(NewShots);
    for (int32 I = 0; I < 2; ++I)
    {
        const auto& V = CannonValues[I];
        auto& C = Sim.Cannons[I];
        C.X = V[0]; C.Y = V[1]; C.Angle = V[2]; C.Power = V[3];
        C.HP = int32(V[4]); C.Shield = V[5]; C.Rapid = V[6]; C.Tilt = 0;
    }
    if (NewRound) { Angle = Sim.Cannons[Player].Angle; Power = Sim.Cannons[Player].Power; Fire = false; }
    Status = FString::Printf(TEXT("RUST-SERVER / Spieler %d%s"), Player + 1,
        RustPlayers == 2 ? TEXT("") : TEXT(" / warte auf zweiten Spieler"));

    if (RustSmoke && RustPlayers == 2)
    {
#if !UE_BUILD_SHIPPING
        if (!SmokeFired) { Angle = 47.f; Fire = true; SmokeFired = true; }
#endif
        RustSawShots |= Sim.Shots.Num() >= 2;
        RustSawDrop |= Sim.Drop.Kind >= 0;
        RustSawWarning |= RustWarning >= 0;
        if (RustSawShots && RustSawDrop && RustSawWarning)
        {
            UE_LOG(LogTemp, Display, TEXT("RUST_CLIENT_PASS player=%d tick=%d"), Player, Sim.Tick);
            RustSmoke = false;
        }
    }
}

bool ASandLaboratoryHUD::SendRust(bool Restart)
{
    if (!RustSocket || !RustSocket->IsConnected() || RustSeat < 0 || RustRound < 0) return false;
    if (Restart ? RustSeat != 0 : RustPlayers != 2) return false;
    auto Object = MakeShared<FJsonObject>();
    Object->SetStringField(TEXT("type"), Restart ? TEXT("restart") : TEXT("input"));
    Object->SetNumberField(TEXT("round"), double(RustRound));
    if (!Restart)
    {
        Object->SetNumberField(TEXT("angle"), Angle);
        Object->SetNumberField(TEXT("power"), Power);
        Object->SetBoolField(TEXT("fire"), Fire);
    }
    FString Json;
    auto Writer = TJsonWriterFactory<>::Create(&Json);
    if (!FJsonSerializer::Serialize(Object, Writer)) return false;
    RustSocket->Send(Json);
    return true;
}
