using UnrealBuildTool;
using System.Collections.Generic;
public class CannonHillTarget : TargetRules
{
    public CannonHillTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Game;
        DefaultBuildSettings = BuildSettingsVersion.V7;
        ExtraModuleNames.Add("CannonHill");
    }
}
