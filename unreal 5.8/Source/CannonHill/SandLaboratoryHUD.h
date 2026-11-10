#pragma once
#include "CoreMinimal.h"
#include "GameFramework/HUD.h"
#include "SandSimulation.h"
#include "SandLaboratoryHUD.generated.h"

class FSocket;
class IWebSocket;
class FJsonObject;
UCLASS()
class CANNONHILL_API ASandLaboratoryHUD : public AHUD
{
    GENERATED_BODY()
public:
    ASandLaboratoryHUD();
    virtual void BeginPlay() override;
    virtual void Tick(float DeltaSeconds) override;
    virtual void DrawHUD() override;
    virtual void EndPlay(const EEndPlayReason::Type Reason) override;
private:
    FSandSimulation Sim;
    FSocket* Listener = nullptr;
    FSocket* Peer = nullptr;
    FString Incoming, Status = TEXT("OFFLINE / Tab wechselt die Kanone");
    TArray<uint8> Outgoing;
    int32 Mode = 0, Player = 0, Weapon = 0;
    float Angle = 45, Power = 55, Clock = 0, SendClock = 0;
    bool Fire = false;
    bool Connecting = false;
    double ConnectDeadline = 0;
#if !UE_BUILD_SHIPPING
    bool LanSmoke = false, SmokeFired = false, SmokeReported = false;
    bool SmokeSawHostShot = false, SmokeSawGuestShot = false, SmokeSawDrop = false;
    bool SmokeReceivedSnapshot = false;
    float SmokeSeconds = 0.f;
    void UpdateLanSmoke(float Delta, float& Drive);
#endif
    TSharedPtr<IWebSocket> RustSocket;
    FString RustAddress;
    TArray<uint8> RustPacket, RustTerrain;
    double RustRetryAt = 0;
    int32 RustSeat = -1, RustPlayers = 0;
    int64 RustRound = -1, RustRevision = -1;
    float RustWarning = -1.f;
    bool RustSmoke = false, RustSawShots = false, RustSawDrop = false, RustSawWarning = false;
    void JoinRust(const FString& Address);
    void OpenRust();
    void CloseRust();
    void RustDisconnected(bool Retry, const TCHAR* Message);
    void RustBinary(const void* Data, SIZE_T Size, bool Last);
    void RustText(const FString& Message);
    bool SendRust(bool Restart);
    void Disconnect();
    void Host();
    void Join(const FString& Address);
    void Network();
    void ClosePeer(const TCHAR* Reason);
    void Send(const TSharedRef<FJsonObject>& Message);
    TSharedRef<FJsonObject> Snapshot() const;
    void ReadMessage(const TSharedPtr<FJsonObject>& Message);
};
