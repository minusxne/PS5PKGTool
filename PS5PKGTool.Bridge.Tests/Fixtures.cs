using System.Runtime.CompilerServices;
using System.Text.Json;
using PS5PKGTool.Core.Models;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;

namespace PS5PKGTool.Bridge.Tests;

internal static class TestEnvironment
{
    public static string Root { get; } = Path.Combine(Path.GetTempPath(), "ps5pkgtool-tests-" + Guid.NewGuid().ToString("N")[..8]);

    /// <summary>Points the bridge's XDG data and cache folders at a throwaway directory before any test runs.</summary>
    [ModuleInitializer]
    internal static void Initialize()
    {
        Directory.CreateDirectory(Root);
        Environment.SetEnvironmentVariable("XDG_DATA_HOME", Path.Combine(Root, "data"));
        Environment.SetEnvironmentVariable("XDG_CACHE_HOME", Path.Combine(Root, "cache"));
    }

    public static string NewDirectory(string name)
    {
        string path = Path.Combine(Root, name + "-" + Guid.NewGuid().ToString("N")[..6]);
        Directory.CreateDirectory(path);
        return path;
    }
}

/// <summary>Builds small, structurally valid PS5 dump folders for tests (no real game content).</summary>
internal static class SyntheticDump
{
    public static string Create(string parent, string titleId = "PPSA99999", string title = "Synthetic Test Title",
        string category = "gd", string contentVersion = "01.000.000", string region = "UP", int dataFiles = 6)
    {
        string root = Path.Combine(parent, titleId + "-" + contentVersion.Replace('.', '_') + "-" + category);
        string sceSys = Path.Combine(root, "sce_sys");
        Directory.CreateDirectory(sceSys);
        var param = new Dictionary<string, object>
        {
            ["titleId"] = titleId,
            ["contentId"] = $"{region}9999-{titleId}_00-SYNTHETICTEST000",
            ["conceptId"] = "99999",
            ["contentVersion"] = contentVersion,
            ["masterVersion"] = "01.00",
            ["requiredSystemSoftwareVersion"] = "0x0450000000000000",
            ["sdkVersion"] = "0x0450000000000000",
            ["applicationCategoryType"] = category == "gp" ? 2 : category == "ac" ? 1 : 0,
            ["applicationDrmType"] = "standard",
            ["localizedParameters"] = new Dictionary<string, object>
            {
                ["defaultLanguage"] = "en-US",
                ["en-US"] = new Dictionary<string, string> { ["titleName"] = title },
                ["ja-JP"] = new Dictionary<string, string> { ["titleName"] = title + " (JP)" }
            }
        };
        File.WriteAllText(Path.Combine(sceSys, "param.json"), JsonSerializer.Serialize(param, new JsonSerializerOptions { WriteIndented = true }));
        WritePng(Path.Combine(sceSys, "icon0.png"), 64, 64, new Rgba32(0, 112, 209));
        WritePng(Path.Combine(sceSys, "pic0.png"), 192, 108, new Rgba32(30, 30, 60));
        File.WriteAllBytes(Path.Combine(root, "eboot.bin"), MinimalElf());

        var random = new Random(titleId.GetHashCode() ^ contentVersion.GetHashCode());
        string data = Path.Combine(root, "data", "nested");
        Directory.CreateDirectory(data);
        for (int index = 0; index < dataFiles; index++)
        {
            byte[] bytes = new byte[16_384 + index * 7_919];
            // Half compressible, half random, so PFSC compression has something to do.
            for (int i = 0; i < bytes.Length / 2; i++) bytes[i] = (byte)(i % 13);
            random.NextBytes(bytes.AsSpan(bytes.Length / 2));
            File.WriteAllBytes(Path.Combine(index % 2 == 0 ? data : Path.Combine(root, "data"), $"file{index:D2}.bin"), bytes);
        }
        File.WriteAllText(Path.Combine(root, "data", "readme.txt"), "Synthetic dump used by PS5 PKG Tool tests.\n");
        return root;
    }

    private static void WritePng(string path, int width, int height, Rgba32 color)
    {
        using var image = new Image<Rgba32>(width, height, color);
        image.SaveAsPng(path);
    }

    /// <summary>A tiny ELF64 x86-64 executable: header plus one PT_LOAD segment, enough for fake-signing.</summary>
    private static byte[] MinimalElf()
    {
        byte[] elf = new byte[8192];
        elf[0] = 0x7F; elf[1] = (byte)'E'; elf[2] = (byte)'L'; elf[3] = (byte)'F';
        elf[4] = 2; // 64-bit
        elf[5] = 1; // little endian
        elf[6] = 1; // version
        elf[9] = 0;
        BitConverter.GetBytes((ushort)2).CopyTo(elf, 16);    // ET_EXEC
        BitConverter.GetBytes((ushort)0x3E).CopyTo(elf, 18); // x86-64
        BitConverter.GetBytes(1u).CopyTo(elf, 20);
        BitConverter.GetBytes(0x400000ul).CopyTo(elf, 24);   // entry
        BitConverter.GetBytes(64ul).CopyTo(elf, 32);         // e_phoff
        BitConverter.GetBytes((ushort)64).CopyTo(elf, 52);   // e_ehsize
        BitConverter.GetBytes((ushort)56).CopyTo(elf, 54);   // e_phentsize
        BitConverter.GetBytes((ushort)1).CopyTo(elf, 56);    // e_phnum
        // One PT_LOAD segment covering a small code area.
        BitConverter.GetBytes(1u).CopyTo(elf, 64);           // p_type
        BitConverter.GetBytes(5u).CopyTo(elf, 68);           // p_flags R+X
        BitConverter.GetBytes(0x1000ul).CopyTo(elf, 72);     // p_offset
        BitConverter.GetBytes(0x400000ul).CopyTo(elf, 80);   // p_vaddr
        BitConverter.GetBytes(0x400000ul).CopyTo(elf, 88);   // p_paddr
        BitConverter.GetBytes(0x1000ul).CopyTo(elf, 96);     // p_filesz
        BitConverter.GetBytes(0x1000ul).CopyTo(elf, 104);    // p_memsz
        BitConverter.GetBytes(0x4000ul).CopyTo(elf, 112);    // p_align
        return elf;
    }

    public static Ps5GameInfo Game(string titleId, string category, string version = "01.000.000", string contentId = "",
        long size = 1024, Ps5SourceKind kind = Ps5SourceKind.LooseDump, string root = "") => new()
    {
        TitleId = titleId,
        ContentId = contentId.Length > 0 ? contentId : $"UP9999-{titleId}_00-TEST000000000000",
        Title = "Title " + titleId,
        ApplicationCategory = category,
        ContentVersion = version,
        SourceSize = size,
        SourceKind = kind,
        RootPath = root.Length > 0 ? root : "/games/" + titleId + "-" + version + "-" + category
    };

    public static void AssertTreesEqual(string expected, string actual)
    {
        string[] left = Directory.EnumerateFiles(expected, "*", SearchOption.AllDirectories)
            .Select(file => Path.GetRelativePath(expected, file)).Order(StringComparer.Ordinal).ToArray();
        string[] right = Directory.EnumerateFiles(actual, "*", SearchOption.AllDirectories)
            .Select(file => Path.GetRelativePath(actual, file))
            .Where(file => !file.Equals("ampr_emu.index", StringComparison.OrdinalIgnoreCase))
            .Order(StringComparer.Ordinal).ToArray();
        Assert.Equal(left, right);
        foreach (string relative in left)
            Assert.True(File.ReadAllBytes(Path.Combine(expected, relative)).AsSpan()
                .SequenceEqual(File.ReadAllBytes(Path.Combine(actual, relative))), "Content differs: " + relative);
    }
}
