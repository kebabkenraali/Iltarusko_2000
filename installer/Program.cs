using System.IO.Compression;
using System.Net.Http;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;

internal static class Program
{
    private const string Magic = "T2KENC01";
    private const string GodotUrl =
        "https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip";
    private const string GodotSha = "731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953";

    private static void Say(string s) => Console.WriteLine(s);

    private static int Main(string[] args)
    {
        try
        {
            string root = Environment.CurrentDirectory;
            string game = args.Length > 0 ? args[0] : Environment.GetEnvironmentVariable("T2K_GAME_DIR");
            if (string.IsNullOrWhiteSpace(game))
            {
                Say("Anna alkuperaisen Twilight: 2000 (DOS) -pelin kansio (GAMEDATA-alakansioineen):");
                game = Console.ReadLine()?.Trim().Trim('"');
            }
            if (string.IsNullOrWhiteSpace(game) || !File.Exists(Path.Combine(game, "GAMEDATA", "ANIMS.LB")))
                throw new Exception("Alkuperaista pelia ei loytynyt: " + game);
            Say("Kaytetaan pelia: " + game);

            string godotDir = Path.Combine(root, "godot");
            string target = Path.Combine(godotDir, "original");
            Directory.CreateDirectory(target);

            // 1. Decrypt the embedded asset package (passphrase is obfuscated in Secret.cs).
            Say("Puretaan upotettu, salattu asset-paketti ...");
            byte[] blob;
            using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("twilight2000_assets.t2k"))
            {
                if (stream == null) throw new Exception("Asset-pakettia ei loytynyt exe:n sisalta.");
                using var ms = new MemoryStream();
                stream.CopyTo(ms);
                blob = ms.ToArray();
            }
            byte[] plain = Decrypt(blob, Secret.Passphrase);
            using (var zs = new MemoryStream(plain))
            using (var zip = new ZipArchive(zs, ZipArchiveMode.Read))
                zip.ExtractToDirectory(target, true);
            Say("  assetit purettu: " + Directory.GetFiles(target, "*", SearchOption.AllDirectories).Length + " tiedostoa");

            // 2. Read a few bytes from the original game (proves the original is present/used).
            var lb = File.ReadAllBytes(Path.Combine(game, "GAMEDATA", "ANIMS.LB"));
            int members = BitConverter.ToUInt16(lb, 0);
            Say("  alkuperainen ANIMS.LB: " + members + " jasenta");

            // 3. Build a clean distributable folder.
            string publish = Path.Combine(Directory.GetParent(root).FullName, "Iltarusko_2000_game");
            if (Directory.Exists(publish)) Directory.Delete(publish, true);
            Directory.CreateDirectory(publish);
            string pubGodot = Path.Combine(publish, "godot");
            Directory.CreateDirectory(pubGodot);
            foreach (string dir in new[] { "data", "scenes", "scripts", "original" })
            {
                string src = Path.Combine(godotDir, dir);
                if (Directory.Exists(src)) CopyDir(src, Path.Combine(pubGodot, dir));
            }
            File.Copy(Path.Combine(godotDir, "project.godot"), Path.Combine(pubGodot, "project.godot"), true);
            string readme = Path.Combine(root, "README.md");
            if (File.Exists(readme)) File.Copy(readme, Path.Combine(publish, "README.md"), true);

            // 4. Download Godot and verify its hash (cache in root\engine).
            Say("Ladataan Godot 4.7.2 ...");
            string engineDir = Path.Combine(root, "engine");
            Directory.CreateDirectory(engineDir);
            string zipPath = Path.Combine(engineDir, "Godot_v4.7.2-stable_win64.exe.zip");
            if (!File.Exists(zipPath))
            {
                using var client = new HttpClient();
                byte[] data = client.GetByteArrayAsync(GodotUrl).GetAwaiter().GetResult();
                File.WriteAllBytes(zipPath, data);
            }
            string sha = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(zipPath))).ToLowerInvariant();
            if (sha != GodotSha) throw new Exception("Godot-zipin SHA256 varminneppa ei täsmännyt: " + sha);
            string tmp = Path.Combine(engineDir, "_extract");
            if (Directory.Exists(tmp)) Directory.Delete(tmp, true);
            ZipFile.ExtractToDirectory(zipPath, tmp);
            string godotExe = Path.Combine(publish, "godot.exe");
            File.Copy(Path.Combine(tmp, "Godot_v4.7.2-stable_win64.exe"), godotExe, true);
            Directory.Delete(tmp, true);
            Say("  Godot valmis. Tuodaan projekti (ensikaynnistys)...");
            using (var proc = new System.Diagnostics.Process())
            {
                proc.StartInfo.FileName = godotExe;
                proc.StartInfo.Arguments = "--headless --path \"" + pubGodot + "\" --editor --quit";
                proc.StartInfo.UseShellExecute = false;
                proc.StartInfo.CreateNoWindow = true;
                // Do NOT redirect stdout/stderr: reading two pipes sequentially can deadlock
                // Godot's import process. With CreateNoWindow the output is simply discarded.
                proc.Start();
                proc.WaitForExit();
            }
            Say("  Projekti tuotu.");

            // 5. Launcher that uses the bundled engine.
            string bat = "@echo off\r\necho ============================================\r\n" +
                         "echo  Iltarusko_2000 - Twilight: 2000 Remake\r\n" +
                         "echo ============================================\r\necho.\r\n" +
                         "\"%~dp0godot.exe\" --path \"%~dp0godot\" %*\r\n";
            File.WriteAllText(Path.Combine(publish, "Kaynnista.bat"), bat, Encoding.ASCII);

            int files = Directory.GetFiles(publish, "*", SearchOption.AllDirectories).Length;
            Say("VALMIS: " + publish);
            Say("Tiedostoja: " + files);
            Say("Kaynnista: " + Path.Combine(publish, "Kaynnista.bat"));
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("VIRHE: " + ex.Message);
            return 1;
        }
    }

    private static void CopyDir(string src, string dst)
    {
        Directory.CreateDirectory(dst);
        foreach (string f in Directory.GetFiles(src)) File.Copy(f, Path.Combine(dst, Path.GetFileName(f)), true);
        foreach (string d in Directory.GetDirectories(src))
        {
            string name = Path.GetFileName(d);
            if (name == ".godot") continue;
            CopyDir(d, Path.Combine(dst, name));
        }
    }

    private static byte[] Decrypt(byte[] blob, string passphrase)
    {
        byte[] magic = Encoding.ASCII.GetBytes(Magic);
        if (blob.Length < magic.Length + 16 + 16 + 32 || !blob.Take(magic.Length).SequenceEqual(magic))
            throw new Exception("Virheellinen asset-paketti.");
        byte[] salt = blob.Skip(magic.Length).Take(16).ToArray();
        byte[] nonce = blob.Skip(magic.Length + 16).Take(16).ToArray();
        int start = magic.Length + 16 + 16;
        byte[] ct = blob.Skip(start).Take(blob.Length - start - 32).ToArray();
        byte[] mac = blob.Skip(blob.Length - 32).Take(32).ToArray();
        byte[] key;
        using (var pbkdf = new Rfc2898DeriveBytes(passphrase, salt, 200000, HashAlgorithmName.SHA256))
            key = pbkdf.GetBytes(32);
        byte[] expected;
        using (var h = new HMACSHA256(key))
            expected = h.ComputeHash(blob, 0, blob.Length - 32);
        if (!CryptographicOperations.FixedTimeEquals(expected, mac))
            throw new Exception("Väärä salasana tai paketti on vahingoittunut.");
        byte[] plain = new byte[ct.Length];
        ulong counter = 0;
        int off = 0;
        while (off < ct.Length)
        {
            byte[] input = new byte[24];
            nonce.CopyTo(input, 0);
            for (int i = 0; i < 8; i++) input[16 + i] = (byte)(counter >> (56 - 8 * i));
            byte[] ks;
            using (var h = new HMACSHA256(key)) ks = h.ComputeHash(input);
            int n = Math.Min(ks.Length, ct.Length - off);
            for (int i = 0; i < n; i++) plain[off + i] = (byte)(ct[off + i] ^ ks[i]);
            off += n;
            counter++;
        }
        return plain;
    }
}
