#pragma once
#include "CoreMinimal.h"
#include "GameFramework/HUD.h"
#include "SandSimulation.h"
#include "SandLaboratoryHUD.generated.h"

class FSocket;
class FJsonObject;
UCLASS()
class CANNONHILL_API ASandLaboratoryHUD : public AHUD
{
    GENERATED_BODY()
public:
    virtual void BeginPlay() override;
    virtual void DrawHUD() override;
    virtual void EndPlay(const EEndPlayReason::Type Reason) override;
private:
    FSandSimulation Sim;
    FSocket* Listener = nullptr;
    FSocket* Peer = nullptr;
    FString Incoming, Status = TEXT("OFFLINE / Tab wechselt die Kanone");
    TArray<uint8> Outgoing;
    int32 Mode = 0, Player = 0;
    float Angle = 45, Power = 55, Clock = 0, SendClock = 0;
    bool Fire = false;
    void Disconnect();
    void Host();
    void Join(const FString& Address);
    void Network();
    void Send(const TSharedRef<FJsonObject>& Message);
    TSharedRef<FJsonObject> Snapshot() const;
    void ReadMessage(const TSharedPtr<FJsonObject>& Message);
};
