using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using CannonHill;

public static class ProjectSetup
{
    [MenuItem("Cannon Hill/Create or open sandbox")]
    public static void CreateScene()
    {
        const string path = "Assets/Scenes/Sandbox.unity";
        Directory.CreateDirectory("Assets/Scenes");
        if (!File.Exists(path))
        {
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            EditorSceneManager.SaveScene(scene, path);
        }
        else EditorSceneManager.OpenScene(path);
        EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(path, true) };
        EditorSettings.serializationMode = SerializationMode.ForceText;
        PlayerSettings.productName = "Cannon Hill Sand Laboratory";
        PlayerSettings.companyName = "CannonHill";
        PlayerSettings.defaultScreenWidth = 1100; PlayerSettings.defaultScreenHeight = 760;
        PlayerSettings.fullScreenMode = FullScreenMode.Windowed;
        AssetDatabase.SaveAssets();
    }
    static void Check(bool condition, string name) { if (!condition) throw new Exception("FAIL " + name); Debug.Log("PASS " + name); }
    [MenuItem("Cannon Hill/Verify simulation")]
    public static void Verify()
    {
        CreateScene();
        var s = new SandSimulation(); int count = s.Cells.Count(x => x == 1);
        for (int i = 0; i < 120; i++) s.Step();
        Check(s.Cells.Count(x => x == 1) == count, "sand conservation");
        Check(s.Cells.Count(x => x == 2) == 960, "bedrock conservation");
        float y = s.Cannons[0].y;
        for (int i = 0; i < 120; i++) s.Step();
        Check(Math.Abs(s.Cannons[0].y - y) < .1, "supported cannon");
        s.Crater(40, y + 8, 14);
        for (int i = 0; i < 90; i++) s.Step();
        Check(s.Cannons[0].y > y + 2, "falling cannon");
        s.Reset(); for (int i = 0; i < 120; i++) s.Step();
        s.Input(0, 45, 55, true); s.Input(0, 45, 55, true);
        Check(s.Shots.Count == 1, "fire and cooldown");
        var shot = s.Shots[0]; float initialY = shot.y; s.Step();
        Check(shot.x > 40 && shot.y < initialY, "ballistic launch");
        for (int i = 0; i < 400; i++) s.Step();
        Check(s.Impacts > 0 && s.Shots.Count == 0, "terrain impact");
        var clone = new SandSimulation();
        Check(clone.Apply(JsonUtility.FromJson<Message>(JsonUtility.ToJson(s.Snapshot()))) && clone.Cells.SequenceEqual(s.Cells), "wire snapshot roundtrip");
        s.Reset();
        s.Tick = 149;
        s.Step();
        Check(s.Drop != null && s.Drop.y > 4, "falling crate spawns");
        Check(clone.Apply(JsonUtility.FromJson<Message>(JsonUtility.ToJson(s.Snapshot()))) &&
            clone.Drop != null && clone.Drop.kind == s.Drop.kind, "falling crate replicates");
        for (int kind = 0; kind < 3; kind++)
        {
            s.Cannons[1].hp = 800;
            s.Drop = new BuffDrop { x = 120, y = 40, kind = kind };
            s.Shots.Add(new Shot { x = 124, y = 40, vx = -55, owner = 1 });
            s.Step();
            Check(s.Drop == null && s.Shots.Count == 0, "projectile collects crate");
            if (kind == 0) Check(s.Cannons[1].hp == 950, "repair restores 150 HP");
            if (kind == 1)
            {
                var defender = s.Cannons[1];
                s.Shots.Add(new Shot { x = defender.x + 4, y = defender.y, vx = -55 });
                s.Step();
                Check(defender.hp == 700, "shield halves damage");
            }
            if (kind == 2)
            {
                s.Input(1, 45, 55, true);
                Check(Math.Abs(s.Cannons[1].cooldown - .35f) < .001f, "rapid fire halves reload");
            }
        }
        s.Reset();
        Check(s.Cannons[1].hp == 1000 && s.Cannons[1].rapid == 0 && s.Drop == null, "restart clears buffs");
        Debug.Log("UNITY_SIMULATION_PASS");
    }
    public static void Build()
    {
        Verify();
        string output = Path.GetFullPath("../builds/unity/CannonHill.exe");
        Directory.CreateDirectory(Path.GetDirectoryName(output));
        var report = BuildPipeline.BuildPlayer(EditorBuildSettings.scenes, output, BuildTarget.StandaloneWindows64, BuildOptions.Development);
        if (report.summary.result != UnityEditor.Build.Reporting.BuildResult.Succeeded) throw new Exception("Build failed: " + report.summary.result);
        Debug.Log("UNITY_BUILD_PASS " + output);
    }
}
