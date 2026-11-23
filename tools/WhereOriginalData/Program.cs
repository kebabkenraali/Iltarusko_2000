// WhereOriginalData: kertoo, mistä alkuperäisen pelin datat (remake/godot/original/)
// sijaitsevat. Etsii projektijuurin (data/ + original/ olemassa) kuin find_game_data.exe.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

static class Program
{
    static int Main()
    {
        var game = FindGame();
        if (game == null)
        {
            Console.WriteLine("Pelistä ei löydetty (haku: data/ + original/ olemassa olevia kansioita).");
            return 1;
        }
        var orig = Path.Combine(game, "original");
        var ok = Directory.Exists(orig);
        Console.WriteLine("Alkuperäinen pelidata sijaitsee kohteessa:");
        Console.WriteLine("  " + orig + (ok ? "  [OK]" : "  [PUUTTUVA]"));
        if (ok)
        {
            long n = 0, bytes = 0;
            foreach (var f in new DirectoryInfo(orig).EnumerateFiles("*", SearchOption.AllDirectories))
            {
                n++; bytes += f.Length;
            }
            var dirs = Directory.GetDirectories(orig).Select(Path.GetFileName).OrderBy(x => x).ToArray();
            Console.WriteLine("  Sisältö: " + string.Join(", ", dirs) + "  (" + n + " tiedostoa, " + bytes + " tavua)");
        }
        return ok ? 0 : 1;
    }

    /// Hakemisto, jossa data/ ja original/ ovat (like find_game_data.exe), etsitään
    /// soveltaen remake-juurta (exe:n kansio mennään "godot"-hakemistoon ylös) sekä nykyhakemistoon.
    static string FindGame()
    {
        var cand = new List<string>();
        cand.Add(Path.Combine(AppContext.BaseDirectory, "godot"));
        var dir = AppContext.BaseDirectory;
        for (var i = 0; i < 5; i++)
        {
            dir = Path.GetDirectoryName(dir);
            if (dir == null) break;
            cand.Add(Path.Combine(dir, "godot"));
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
}
