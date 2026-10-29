#pragma once
#include "CoreMinimal.h"

struct FCannonState
{
    float X = 0, Y = 0, VY = 0, Angle = 45, Power = 55, Cooldown = 0, Tilt = 0;
};
struct FShotState { float X = 0, Y = 0, VX = 0, VY = 0, Age = 0; };

// Reference model: +Y down, cell = 0.25m, fixed 30Hz. No Chaos dependency.
struct FSandSimulation
{
    static constexpr int32 W = 240, H = 128;
    static constexpr float Dt = 1.f / 30.f, Gravity = 39.24f;
    TArray<uint8> Cells;
    FCannonState Cannons[2];
    TArray<FShotState> Shots;
    int32 Tick = 0, Impacts = 0, Moved = 0;
    FSandSimulation() { Reset(); }
    bool Solid(int32 X, int32 Y) const { return X >= 0 && X < W && Y >= 0 && Y < H && Cells[Y * W + X] != 0; }
    int32 Surface(int32 X) const { for (int32 Y = 0; Y < H; ++Y) if (Solid(X, Y)) return Y; return H; }
    void Reset()
    {
        Cells.Init(0, W * H);
        for (int32 X = 0; X < W; ++X)
        {
            int32 Top = int32(81.0 + 10.0 * FMath::Sin(double(X) * .035) + 5.0 * FMath::Sin(double(X) * .081));
            for (int32 Y = Top; Y < H; ++Y) Cells[Y * W + X] = Y >= H - 4 ? 2 : 1;
        }
        for (int32 I = 0; I < 2; ++I) { Cannons[I] = FCannonState(); Cannons[I].X = I == 0 ? 40.f : 200.f; Cannons[I].Y = Surface(int32(Cannons[I].X)) - 3.f; }
        Shots.Reset(); Tick = Impacts = Moved = 0;
    }
    void Input(int32 Player, float Angle, float Power, bool Fire)
    {
        if (Player < 0 || Player > 1 || !FMath::IsFinite(Angle) || !FMath::IsFinite(Power)) return;
        auto& C = Cannons[Player]; C.Angle = FMath::Clamp(Angle, 5.f, 85.f); C.Power = FMath::Clamp(Power, 15.f, 90.f);
        if (!Fire || C.Cooldown > 0 || Shots.Num() >= 32) return;
        const float DX = FMath::Cos(FMath::DegreesToRadians(C.Angle)) * (Player == 0 ? 1.f : -1.f);
        const float DY = -FMath::Sin(FMath::DegreesToRadians(C.Angle));
        FShotState S; S.X = C.X + DX * 7; S.Y = C.Y - 1 + DY * 7; S.VX = DX * C.Power; S.VY = DY * C.Power;
        Shots.Add(S); C.Cooldown = .7f;
    }
    void Crater(float CX, float CY, float Radius = 10.f)
    {
        for (int32 Y = FMath::Max(0, int32(CY - Radius)); Y < FMath::Min(H, int32(CY + Radius) + 1); ++Y)
            for (int32 X = FMath::Max(0, int32(CX - Radius)); X < FMath::Min(W, int32(CX + Radius) + 1); ++X)
                if (Cells[Y * W + X] == 1 && FMath::Square(X - CX) + FMath::Square(Y - CY) < Radius * Radius) Cells[Y * W + X] = 0;
        ++Impacts;
    }
    void Step()
    {
        ++Tick; Moved = 0;
        for (int32 Y = H - 2; Y >= 0; --Y) for (int32 Scan = 0; Scan < W; ++Scan)
        {
            const int32 X = Tick % 2 == 0 ? Scan : W - 1 - Scan, Index = Y * W + X;
            if (Cells[Index] != 1) continue;
            int32 Target = Index + W;
            if (Cells[Target] != 0)
            {
                int32 Side = (Tick + X + Y) % 2 == 0 ? 1 : -1;
                if (X + Side >= 0 && X + Side < W && Cells[Target + Side] == 0) Target += Side;
                else if (X - Side >= 0 && X - Side < W && Cells[Target - Side] == 0) Target -= Side;
                else continue;
            }
            Cells[Index] = 0; Cells[Target] = 1; ++Moved;
        }
        for (auto& C : Cannons)
        {
            C.Cooldown = FMath::Max(0.f, C.Cooldown - Dt); C.VY += Gravity * Dt;
            float Next = FMath::Min(H - 7.f, C.Y + C.VY * Dt);
            int32 Left = H, Right = H;
            for (int32 Y = FMath::Max(0, int32(C.Y + 2)); Y < H; ++Y)
            {
                if (Left == H && Solid(int32(C.X) - 3, Y)) Left = Y;
                if (Right == H && Solid(int32(C.X) + 3, Y)) Right = Y;
            }
            const float Floor = FMath::Min(Left, Right) - 3.f;
            if (Next >= Floor) { Next = Floor; C.VY = 0; }
            C.Y = Next; C.Tilt = FMath::Clamp(FMath::Atan2(float(Right - Left), 6.f), -.5f, .5f);
        }
        for (int32 I = Shots.Num() - 1; I >= 0; --I)
        {
            auto& S = Shots[I]; S.VY += Gravity * Dt; S.Age += Dt;
            const int32 Count = FMath::Max(1, FMath::CeilToInt(FMath::Sqrt(S.VX * S.VX + S.VY * S.VY) * Dt * 2));
            bool Hit = false;
            for (int32 Sub = 0; Sub < Count; ++Sub)
            {
                S.X += S.VX * Dt / Count; S.Y += S.VY * Dt / Count;
                if (Solid(FMath::FloorToInt(S.X), FMath::FloorToInt(S.Y))) { Crater(S.X, S.Y); Hit = true; break; }
            }
            if (Hit || S.Age > 12 || S.X < 0 || S.X >= W || S.Y >= H) Shots.RemoveAt(I);
        }
    }
};
