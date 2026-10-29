using UnrealBuildTool;
public class CannonHill : ModuleRules
{
    public CannonHill(ReadOnlyTargetRules Target) : base(Target)
    {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
        PublicDependencyModuleNames.AddRange(new[] { "Core", "CoreUObject", "Engine", "InputCore", "Sockets", "Networking", "Json" });
    }
}
