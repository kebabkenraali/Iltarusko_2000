// PackGame: pakkaa pelin — alkuperäinen aineisto (res://original/..., "original art")
// ja pelin exe ("exe") -> ZIP-tiedosto.
//
// Käyttö: pack_game.exe [--engine <exe>] [--out <zip-pol​ut>]
// Oletukset: projekti löytyy kuten find_game_data.exe (data/ + original/ olemassa);
// pelin exe etsitään käyttöympäristöstä (haku C:\AI_Projektit\coyote-flats\dist\engine\...)
// tai ympäristömuuttujasta TWILIGHT_GAME_EXE.
//
// ZIP:n sisältö: original/ (koko puu, *.import mukaan lukien) + pelin exe (juurimerkki
// pois laskettu, kaksoismerkinnän välttämiseksi vähintään yksi aliohjaiminen tiedosto).
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;

static class Program
{
    static int Main(string[] args)
    {
        string engineOverride = null;
        string outOverride = null;
        for (var i = 0; i < args.Length; i++)
        {
            if (args[i] == "--engine" && i + 1 < args.Length) engineOverride = args[++i];
            else if (args[i] == "--out" && i + 1 < args.Length) outOverride = args[++i];
        }
        var game = FindGame();
        if (game == null)
        {
            Console.WriteLine("PROJEKTI PAIKKA: ei löydy (etsitty kuin find_game_data.exe).");
            return 1;
        }
        Console.WriteLine("Projekti: " + game);
        var engine = engineOverride ?? FindEngine(game);
        if (engine == null)
        {
            Console.WriteLine("PELIN EXE: ei löydy (etsitään C:\\AI_Projektit\\coyote-flats\\dist\\engine\\Godot_v4.7.2-stable_win64.exe tai aseta TWILIGHT_GAME_EXE).");
            return 1;
        }
        Console.WriteLine("Pelin exe: " + engine);
        var outPath = Path.GetFullPath(outOverride ?? Path.Combine(Environment.CurrentDirectory, "Twilight-2000-Remake.zip"));

        long n = 0, bytes = 0;
        using (var archive = ZipFile.Open(outPath, ZipArchiveMode.Create))
        {
            var orig = Path.Combine(game, "original");
            foreach (var f in new DirectoryInfo(orig).EnumerateFiles("*", SearchOption.AllDirectories))
            {
                var rel = "original/" + f.FullName.Substring(orig.Length + 1).Replace("\\", "/");
                archive.CreateEntryFromFile(f.FullName, rel);
                n++; bytes += f.Length;
            }
            archive.CreateEntryFromFile(engine, Path.GetFileName(engine));
            n++; bytes += new FileInfo(engine).Length;
        }
        Console.WriteLine("Pakkaamsella: " + outPath);
        Console.WriteLine("Sisältö: original/ (" + n + " tiedostoa, " + bytes + " tavua) + pelin exe (" + Path.GetFileName(engine) + ").");
        return 0;
    }

    /// Hakemisto, jossa data/ ja original/ ovat (kuten find_game_data.exe etsii).
    static string FindGame()
    {
        var cand = new List<string>();
        var dir = AppContext.BaseDirectory;
        for (var i = 0; i < 4; i++)
        {
            cand.Add(Path.GetFullPath(Path.Combine(dir, "..", "godot")));
            dir = Path.GetFullPath(Path.Combine(dir, ".."));
        }
        cand.Add(Path.Combine(Environment.CurrentDirectory, "remake", "godot"));
        cand.Add(Path.Combine(Environment.CurrentDirectory, "godot"));
        foreach (var c in cand)
        {
            if (Directory.Exists(Path.Combine(c, "data")) && Directory.Exists(Path.Combine(c, "original")))
            {
                return Path.GetFullPath(c);
            }
        }
        return null;
    }

    /// Pelin exe: TWILIGHT_GAME_EXE ympäristömuuttuja tai hakupolku coyote-flats-poikuksella.
    static string FindEngine(string game)
    {
        var v = Environment.GetEnvironmentVariable("TWILIGHT_GAME_EXE");
        if (!string.IsNullOrWhiteSpace(v) && File.Exists(v)) return Path.GetFullPath(v);
        var dir = game;
        for (var i = 0; i < 6; i++)
        {
            var c = Path.Combine(dir, "AI_Projektit", "coyote-flats", "dist", "engine", "Godot_v4.7.2-stable_win64.exe");
            if (File.Exists(c)) return Path.GetFullPath(c);
            dir = Path.GetDirectoryName(dir);
            if (dir == null) break;
        }
        return null;
    }
}
