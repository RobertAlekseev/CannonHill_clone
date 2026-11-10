#include "CannonHillGameMode.h"
#include "SandLaboratoryHUD.h"
#include "GameFramework/PlayerController.h"
ACannonHillGameMode::ACannonHillGameMode()
{
    HUDClass = ASandLaboratoryHUD::StaticClass();
    DefaultPawnClass = nullptr;
    PlayerControllerClass = APlayerController::StaticClass();
}
