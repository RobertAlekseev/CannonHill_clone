#include "SandSimulation.h"
#include "Misc/AutomationTest.h"
#if WITH_DEV_AUTOMATION_TESTS
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FDrivingWeaponsTest, "CannonHill.DrivingAndWeapons", EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)
bool FDrivingWeaponsTest::RunTest(const FString& Parameters)
{
    FSandSimulation S;
    // Flat ground isolates driving from the generated hillside.
    S.Cells.Init(0, S.W * S.H);
    for (int32 Y = 90; Y < S.H; ++Y) for (int32 X = 0; X < S.W; ++X) S.Cells[Y*S.W+X] = 2;
    S.Cannons[0].Y = S.Cannons[1].Y = 87;
    const float Start = S.Cannons[0].X;
    for (int32 I=0; I<30; ++I) { S.Input(0,45,55,false,1,0); S.Step(); }
    TestTrue(TEXT("Drives right"), S.Cannons[0].X > Start + 10);
    for (int32 I=0; I<30; ++I) { S.Input(0,45,55,false,-1,0); S.Step(); }
    TestTrue(TEXT("Drives left"), FMath::Abs(S.Cannons[0].X-Start)<.1f);
    S.Input(0,45,55,false,1,0);
    for (int32 I=0; I<20; ++I) S.Step();
    float Stopped = S.Cannons[0].X;
    for (int32 I=0; I<20; ++I) S.Step();
    TestEqual(TEXT("Stale input stops"), S.Cannons[0].X, Stopped);
    for(int32 W=0; W<3; ++W) {
        S.Cannons[0].Cooldown=0; S.Shots.Reset();
        S.Input(0,45,55,true,0,W);
        TestEqual(TEXT("Shot weapon retained"), S.Shots[0].Weapon,W);
        TestEqual(TEXT("Weapon cooldown"), S.Cannons[0].Cooldown,W==1?1.4f:W==2?.3f:.7f);
        S.Input(0,45,55,true,0,W); TestEqual(TEXT("Cooldown prevents repeated fire"),S.Shots.Num(),1);
    }
    S.Reset();
    S.Tick = 149;
    S.Step();
    TestTrue(TEXT("Crate spawns and falls"), S.Drop.Kind >= 0 && S.Drop.Y > 4.f);
    for (int32 Kind = 0; Kind < 3; ++Kind)
    {
        S.Cannons[1].HP = 800;
        S.Drop = {Kind, 120.f, 40.f};
        FShotState Shot;
        Shot.X = 124.f; Shot.Y = 40.f; Shot.VX = -55.f; Shot.Owner = 1;
        S.Shots.Add(Shot);
        S.Step();
        TestTrue(TEXT("Projectile collects crate"), S.Drop.Kind == -1 && S.Shots.IsEmpty());
        if (Kind == 0) TestEqual(TEXT("Repair restores HP"), S.Cannons[1].HP, 950);
        if (Kind == 1)
        {
            Shot.X = S.Cannons[1].X + 4.f;
            Shot.Y = S.Cannons[1].Y;
            Shot.Owner = 0;
            S.Shots.Add(Shot);
            S.Step();
            TestEqual(TEXT("Shield halves damage"), S.Cannons[1].HP, 700);
        }
        if (Kind == 2)
        {
            S.Input(1, 45, 55, true, 0, 1);
            TestEqual(TEXT("Rapid fire halves the heavy weapon reload"), S.Cannons[1].Cooldown, .7f);
        }
    }
    S.Reset();
    TestTrue(TEXT("Restart clears buffs"), S.Drop.Kind == -1 && S.Cannons[1].Rapid == 0.f && S.Cannons[1].HP == 1000);
    return true;
}
#endif
