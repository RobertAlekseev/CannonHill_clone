using UnrealBuildTool;
using System.Collections.Generic;
public class CannonHillEditorTarget : TargetRules
{
    public CannonHillEditorTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Editor;
        DefaultBuildSettings = BuildSettingsVersion.V5;
        ExtraModuleNames.Add("CannonHill");
    }
}
