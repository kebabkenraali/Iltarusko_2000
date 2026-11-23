// FindGameData: kertoo missä vastaavan pelin vaatimat datat ovat:
//   - projekti (remake/godot)
//   - aikuenhinnoitu aineisto (res://original/...: grafiikka, äänet, palaverit)
//   - pelidata (res://data/...: items.json, missions.json, careers.json, charger.json, ...)
//   - tallennushakemisto (user:// = %APPDATA%\Godot\app_userdata\Twilight- 2000 Remake)
//
// Käyttö: find_game_data.exe [--path <projekti-juuripolku>]
using System;
using System.Collections.Generic;
using System.IO;

static class Program
{
    static int Main(string[] args)
    {
        var cand = new List<string>();
        for (var i = 0; i < args.Length; i++)
        {
            if (args[i] == "--path" && i + 1 < args.Length)
            {
                cand.Add(args[i + 1]);
            }
        }
        var dir = AppContext.BaseDirectory;
        for (var i = 0; i < 4; i++)
        {
            cand.Add(Path.GetFullPath(Path.Combine(dir, "..", "godot")));
            dir = Path.GetFullPath(Path.Combine(dir, ".."));
        }
        cand.Add(Path.Combine(Environment.CurrentDirectory, "remake", "godot"));
        cand.Add(Path.Combine(Environment.CurrentDirectory, "godot"));

        string root = null;
        foreach (var c in cand)
        {
            if (Directory.Exists(Path.Combine(c, "data")) && Directory.Exists(Path.Combine(c, "original")))
            {
                root = Path.GetFullPath(c);
                break;
            }
        }
        if (root == null)
        {
            Console.WriteLine("PROJEKTI PAIKKA: ei löydy (" + string.Join(" / ", cand) + ")");
            return 1;
        }
        var godot = root;   // hakemisto, jossa data/ ja original/ ovat (remake/godot)
        Console.WriteLine("Projekti: " + godot);

        var ok = true;
        ok &= CheckDir(Path.Combine(godot, "data"), "pelidata (JSON)");
        foreach (var f in new[] { "items.json", "missions.json", "careers.json", "chargen.json", "cities.json", "EQUIP.json", "worldmap.json" })
        {
            ok &= CheckFile(Path.Combine(godot, "data", f), f);
        }
        ok &= CheckDir(Path.Combine(godot, "original"), "original (alunperin aineisto)");
        foreach (var d in new[] { "graphics", "graphics/ANIMS", "graphics/CMBT", "graphics/FACES", "graphics/FACES/talk", "graphics/WORLD", "graphics/BUILDING", "graphics/ART", "graphics/ICON", "audio", "audio/music", "audio/sfx" })
        {
            ok &= CheckDir(Path.Combine(godot, "original", d), d);
        }
        var userDir = Path.Combine(Environment.GetEnvironmentVariable("APPDATA") ?? "", "Godot", "app_userdata", "Twilight- 2000 Remake");
        CheckDir(userDir, "tallennus (user://)");

        Console.WriteLine();
        Console.WriteLine(ok ? "DATA PAAT LÖYTYVÄT." : "OSA DATA PUUTTUVA - peliä ei voi ajaa sellaisenaan.");
        return ok ? 0 : 1;
    }

    static bool CheckDir(string path, string name)
    {
        var ok = Directory.Exists(path);
        Console.WriteLine("  " + name + ": " + path + " [" + (ok ? "OK" : "PUUTTUVA") + "]");
        if (ok)
        {
            var n = 0;
            var bytes = 0L;
            foreach (var f in new DirectoryInfo(path).EnumerateFiles("*", SearchOption.AllDirectories))
            {
                n++;
                bytes += f.Length;
            }
            Console.WriteLine("      " + n + " tiedostoa, " + bytes + " tavua");
        }
        return ok;
    }

    static bool CheckFile(string path, string name)
    {
        var ok = File.Exists(path);
        Console.WriteLine("  " + name + ": " + path + " [" + (ok ? "OK" : "PUUTTUVA") + "]");
        return ok;
    }
}
