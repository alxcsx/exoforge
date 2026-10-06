using System;
using System.IO;
using System.Linq;
using Exoforge.Unity.Editor;
using System.Text.Json;
using SnakeGame;
using UnityEditor;
using UnityEngine;

/// <summary>
/// Headless self-check for the sample's fiddly bits: the board's pixel index maths and the
/// leaderboard JSON parsing. Everything else in the sample is either Unity or the SDK.
///
/// Driven from the Unity CLI (note: no <c>-quit</c>, the check sets its own exit code):
///
/// <code>
/// Unity -batchmode -nographics -projectPath sdk/unity/sample_unity \
///       -executeMethod ExoforgeSampleCheck.Run
/// </code>
///
/// Exit code 0 = pass, 1 = a check failed.
/// </summary>
public static class ExoforgeSampleCheck
{
    private static int _failures;

    public static void Run()
    {
        _failures = 0;

        CheckBoardPixels();
        CheckLeaderboardParsing();
        CheckPluginToolchain();

        if (_failures == 0)
        {
            Debug.Log("[ExoforgeSampleCheck] all checks passed.");
        }
        else
        {
            Debug.LogError($"[ExoforgeSampleCheck] {_failures} check(s) failed.");
        }

        EditorApplication.Exit(_failures == 0 ? 0 : 1);
    }

    /// <summary>
    /// A cell's colour has to land on that cell's pixel. This is what catches a transposed
    /// <c>x</c>/<c>y</c> or an off-by-one row stride — invisible until you look at the board.
    /// </summary>
    /// <summary>
    /// The Control Center builds plugins out of process, so the generator has to travel with the
    /// package. This resolved to null after M29 moved the generator into the dotnet project and
    /// nothing noticed, because nothing exercised the editor's resolution: the CLI finds it beside
    /// its own assembly and clean-build goes through the CLI, so both kept passing while Build &amp;
    /// Deploy failed with "the SDK's manifest generator is missing".
    /// </summary>
    private static void CheckPluginToolchain()
    {
        string? generator = ExoforgeEditorConfig.ManifestGenPath;

        Expect(generator != null,
            "the package does not carry the manifest generator - run 'just build-unity-sdk'");

        if (generator == null)
        {
            return;
        }

        Expect(File.Exists(Path.Combine(generator, "ManifestGen.csproj")),
            "the shipped manifest generator has no project file");
        Expect(File.Exists(Path.Combine(generator, "Program.cs")),
            "the shipped manifest generator has no source");
    }

    /// <summary>
    /// A cell's colour has to depend on what is in it, and the board has to sit centred on the
    /// origin. This is what catches a transposed x/y or an off-by-one row — invisible until you look
    /// at the board, and the reason the checkerboard is asserted to alternate.
    ///
    /// The sprites themselves need a frame to exist, so they are checked in the play-mode scene test.
    /// </summary>
    private static void CheckBoardPixels()
    {
        var gameGo = new GameObject("CheckGameplay");
        var viewGo = new GameObject("CheckBoard");

        try
        {
            var game = gameGo.AddComponent<SnakeGameController>();
            var view = viewGo.AddComponent<SnakeBoardView>();

            game.StartNewGame();
            Wire(view, "game", game);

            var palette = ReadPalette(view);

            var head = game.Head;
            Expect(view.CellColour(head).Equals(palette.Head), $"head cell {head} is not the head colour");

            var food = game.Food;
            Expect(view.CellColour(food).Equals(palette.Food), $"food cell {food} is not the food colour");

            foreach (var segment in game.Body)
            {
                Expect(view.CellColour(segment).Equals(palette.Body), $"body cell {segment} is not the body colour");
            }

            var empty = FirstEmptyCell(game, out _);
            var emptyColour = view.CellColour(empty);
            Expect(emptyColour.Equals(palette.SquareA) || emptyColour.Equals(palette.SquareB),
                $"empty cell {empty} is not a board colour");

            // The checkerboard has to alternate, or the grid is invisible when the board is empty.
            Expect(!view.CellColour(new Vector2Int(0, 0)).Equals(view.CellColour(new Vector2Int(1, 0))),
                "the checkerboard does not alternate along x");
            Expect(!view.CellColour(new Vector2Int(0, 0)).Equals(view.CellColour(new Vector2Int(0, 1))),
                "the checkerboard does not alternate along y");

            // Centred on the origin: the corners are equal and opposite.
            Expect(Vector3.Distance(view.CellToWorld(new Vector2Int(0, 0)),
                       -view.CellToWorld(new Vector2Int(game.GridWidth - 1, game.GridHeight - 1))) < 0.001f,
                "the board is not centred on the origin");
        }
        finally
        {
            UnityEngine.Object.DestroyImmediate(viewGo);
            UnityEngine.Object.DestroyImmediate(gameGo);
        }
    }


    private static void CheckLeaderboardParsing()
    {
        var rows = SnakeLeaderboard.ParseRows(JsonDocument.Parse(
            """[{"name":"Viper","score":120,"snake_length":7},{"name":"Ada","score":90,"snake_length":5},{"score":10}]""")
            .RootElement);

        Expect(rows.Count == 3, $"parsed {rows.Count} rows, expected 3");
        Expect(rows[0].Name == "Viper" && rows[0].Score == 120 && rows[0].Length == 7, "row 0 parsed wrong");
        Expect(rows[1].Name == "Ada" && rows[1].Score == 90 && rows[1].Length == 5, "row 1 parsed wrong");

        // A row missing fields still shows up, with placeholders instead of an exception.
        Expect(rows[2].Name == "?" && rows[2].Score == 10 && rows[2].Length == 0, "row 2 (partial) parsed wrong");

        // Anything that is not an array is simply empty.
        Expect(SnakeLeaderboard.ParseRows(JsonDocument.Parse("{}").RootElement).Count == 0,
            "a non-array leaderboard should parse to no rows");
    }

    private static Vector2Int FirstEmptyCell(SnakeGameController game, out bool found)
    {
        for (int x = 0; x < game.GridWidth; x++)
        {
            for (int y = 0; y < game.GridHeight; y++)
            {
                var cell = new Vector2Int(x, y);

                if (cell != game.Head && cell != game.Food && !game.Body.Contains(cell))
                {
                    found = true;
                    return cell;
                }
            }
        }

        found = false;
        return Vector2Int.zero;
    }

    private readonly struct Palette
    {
        public Palette(Color32 squareA, Color32 squareB, Color32 body, Color32 head, Color32 food)
        {
            SquareA = squareA;
            SquareB = squareB;
            Body = body;
            Head = head;
            Food = food;
        }

        public Color32 SquareA { get; }
        public Color32 SquareB { get; }
        public Color32 Body { get; }
        public Color32 Head { get; }
        public Color32 Food { get; }
    }

    private static Palette ReadPalette(SnakeBoardView view)
    {
        var so = new SerializedObject(view);

        return new Palette(
            (Color32)ReadColor(so, "squareA"),
            (Color32)ReadColor(so, "squareB"),
            (Color32)ReadColor(so, "bodyColor"),
            (Color32)ReadColor(so, "headColor"),
            (Color32)ReadColor(so, "foodColor"));
    }

    private static Color ReadColor(SerializedObject so, string field) =>
        so.FindProperty(field)?.colorValue ?? Color.magenta;

    private static void Wire(Component target, string field, UnityEngine.Object value)
    {
        var so = new SerializedObject(target);
        var property = so.FindProperty(field);

        if (property == null)
        {
            Expect(false, $"{target.GetType().Name} has no field '{field}'");
            return;
        }

        property.objectReferenceValue = value;
        so.ApplyModifiedPropertiesWithoutUndo();
    }

    private static void Expect(bool condition, string message)
    {
        if (condition)
        {
            return;
        }

        _failures++;
        Debug.LogError($"[ExoforgeSampleCheck] FAIL: {message}");
    }
}
