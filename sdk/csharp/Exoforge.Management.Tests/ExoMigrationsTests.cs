using System;
using System.IO;
using System.Linq;
using Exoforge.Management;
using Xunit;

namespace Exoforge.Management.Tests;

public class ExoMigrationsTests
{
    [Fact]
    public void Statements_Split_At_The_Semicolons_That_End_One()
    {
        var statements = ExoMigrations.Split("""
            ALTER TABLE a ADD COLUMN x text;
            -- a comment; with a semicolon
            UPDATE a SET x = 'one; two' WHERE y = "we;ird";
            /* block; comment */ DELETE FROM a;
            """);

        Assert.Equal(3, statements.Length);
        Assert.StartsWith("ALTER TABLE a", statements[0]);
        Assert.Contains("'one; two'", statements[1]);
        Assert.Contains("\"we;ird\"", statements[1]);
        Assert.EndsWith("DELETE FROM a", statements[2]);
    }

    [Fact]
    public void A_Dollar_Quoted_Body_Is_One_Statement_And_A_Parameter_Is_Not_A_Quote()
    {
        var statements = ExoMigrations.Split("""
            CREATE FUNCTION f() RETURNS int AS $body$ BEGIN RETURN 1; END; $body$ LANGUAGE plpgsql;
            SELECT $1;
            """);

        Assert.Equal(2, statements.Length);
        Assert.Contains("RETURN 1; END;", statements[0]);
        Assert.Equal("SELECT $1", statements[1]);
    }

    [Fact]
    public void A_Doubled_Quote_Stays_Inside_The_String()
    {
        var statements = ExoMigrations.Split("UPDATE a SET n = 'it''s; fine'; SELECT 1;");
        Assert.Equal(2, statements.Length);
        Assert.Contains("it''s; fine", statements[0]);
    }

    [Fact]
    public void A_File_With_Only_Comments_Has_No_Statements()
    {
        Assert.Empty(ExoMigrations.Split("-- nothing here\n/* or here */\n"));
    }

    private static string Folder(params (string Name, string Sql)[] files)
    {
        string dir = Path.Combine(Path.GetTempPath(), $"exo_migrations_{Guid.NewGuid():N}");
        Directory.CreateDirectory(dir);
        foreach (var (name, sql) in files) File.WriteAllText(Path.Combine(dir, name), sql);
        return dir;
    }

    [Fact]
    public void Migrations_Load_In_Version_Order_Whatever_The_Names_Sort_As()
    {
        string dir = Folder(("0010_later.sql", "SELECT 10;"), ("0002_early.sql", "SELECT 2;"), ("0007_middle.sql", "SELECT 7;"));
        try
        {
            var loaded = ExoMigrations.Load(dir);
            Assert.Equal(new[] { 2, 7, 10 }, loaded.Select(m => m.Version));
            Assert.Equal("early", loaded[0].Name);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public void A_File_That_Is_Not_Named_As_A_Migration_Is_Refused()
    {
        string dir = Folder(("add_owner.sql", "SELECT 1;"));
        try { Assert.Contains("0007_what_it_does.sql", Assert.Throws<ArgumentException>(() => ExoMigrations.Load(dir)).Message); }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public void Two_Files_Of_One_Version_Are_Refused()
    {
        string dir = Folder(("0001_a.sql", "SELECT 1;"), ("0001_b.sql", "SELECT 2;"));
        try { Assert.Contains("version 1", Assert.Throws<ArgumentException>(() => ExoMigrations.Load(dir)).Message); }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public void The_Payload_Is_What_The_Server_Action_Takes()
    {
        string dir = Folder(("0001_first.sql", "CREATE TABLE t (id text); CREATE INDEX i ON t (id);"));
        try
        {
            var payload = ExoMigrations.ToPayload("snake_game", ExoMigrations.Load(dir));

            Assert.Equal("snake_game", payload["namespace"]!.GetValue<string>());
            var migration = payload["migrations"]!.AsArray().Single()!;
            Assert.Equal(1, migration["version"]!.GetValue<int>());
            Assert.Equal("first", migration["name"]!.GetValue<string>());
            Assert.Equal(2, migration["sql"]!.AsArray().Count);
        }
        finally { Directory.Delete(dir, true); }
    }
}
