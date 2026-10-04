using System;
using System.Linq;
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
    private static void CheckBoardPixels()
    {
        var gameGo = new GameObject("CheckGameplay");
        var viewGo = new GameObject("CheckHud");

        try
        {
            var game = gameGo.AddComponent<SnakeGameController>();
            var view = viewGo.AddComponent<SnakeGameView>();

            game.StartNewGame();
            Wire(view, "game", game);

            var palette = ReadPalette(view);
            var pixels = view.BuildPixels();

            int w = game.GridWidth;
            int h = game.GridHeight;

            Expect(pixels.Length == w * h, $"pixel buffer is {pixels.Length}, expected {w * h}");

            var head = game.Head;
            Expect(pixels[head.y * w + head.x].Equals(palette.Head), $"head cell {head} is not the head colour");

            var food = game.Food;
            Expect(pixels[food.y * w + food.x].Equals(palette.Food), $"food cell {food} is not the food colour");

            foreach (var segment in game.Body)
            {
                Expect(pixels[segment.y * w + segment.x].Equals(palette.Body), $"body cell {segment} is not the body colour");
            }

            // An untouched cell keeps the checkerboard, and the checkerboard actually alternates.
            var empty = FirstEmptyCell(game, out _);
            var emptyColor = pixels[empty.y * w + empty.x];
            Expect(emptyColor.Equals(palette.SquareA) || emptyColor.Equals(palette.SquareB),
                $"empty cell {empty} is not a board colour");

            Expect(!pixels[0].Equals(pixels[1]), "the checkerboard does not alternate along x");
            Expect(!pixels[0].Equals(pixels[w]), "the checkerboard does not alternate along y");
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

    private static Palette ReadPalette(SnakeGameView view)
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
