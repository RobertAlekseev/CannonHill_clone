using UnrealBuildTool;
using System.Collections.Generic;
public class CannonHillTarget : TargetRules
{
    public CannonHillTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Game;
        DefaultBuildSettings = BuildSettingsVersion.V5;
        ExtraModuleNames.Add("CannonHill");
    }
}
