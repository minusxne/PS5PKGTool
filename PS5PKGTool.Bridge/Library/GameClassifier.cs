using System.Globalization;
using PS5PKGTool.Core.Models;

namespace PS5PKGTool.Bridge.Library;

/// <summary>
/// Presentation classification of a library item: category, region, format, role in its title
/// family and sortable version keys. Ported from the Windows edition's library grid so both
/// editions label and filter items identically.
/// </summary>
public static class GameClassifier
{
    public static readonly string[] Categories = ["Game", "Patch", "DLC", "App", "Unknown"];
    public static readonly string[] Regions = ["Americas", "Europe", "Japan", "Korea", "Asia", "Hong Kong", "Other", "Unknown"];
    public static readonly string[] Formats = ["Dump Files", "PKG", "FFPFSC", "exFAT", "FFPKG"];

    public static string CategoryOf(Ps5GameInfo game)
    {
        string raw = game.ApplicationCategory;
        if (!string.IsNullOrWhiteSpace(raw))
        {
            string token = raw.Split(' ', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? raw;
            if (int.TryParse(token, NumberStyles.Integer, CultureInfo.InvariantCulture, out int number))
            {
                // Only 1 selects additional content; publisher-specific encodings such as 0x01000000
                // are base applications, matching the engine's ProsperoParam normalization.
                return number switch
                {
                    1 => "DLC",
                    2 => "Patch",
                    3 => "App",
                    _ => "Game"
                };
            }
            return raw;
        }
        return game.Package?.ContentType switch
        {
            0x20 => "Game",
            // 0x21/0x22 are PS5 additional content; real patches use the LIH patch-layer envelope.
            0x21 => "DLC",
            0x22 => "DLC",
            _ => game.SourceKind == Ps5SourceKind.LooseDump ? "Game" : "Unknown"
        };
    }

    public static string RegionOf(Ps5GameInfo game)
    {
        string id = !string.IsNullOrWhiteSpace(game.ContentId) ? game.ContentId : game.TitleId;
        if (id.Length < 1) return "Unknown";
        return char.ToUpperInvariant(id[0]) switch
        {
            'U' => "Americas",
            'E' => "Europe",
            'J' => "Japan",
            'K' => "Korea",
            'A' => "Asia",
            'H' => "Hong Kong",
            _ => "Other"
        };
    }

    /// <summary>The value the Format filter matches against.</summary>
    public static string FormatOf(Ps5GameInfo game) => game.SourceKind switch
    {
        Ps5SourceKind.LooseDump => "Dump Files",
        Ps5SourceKind.SonyPackage => "PKG",
        Ps5SourceKind.Ffpfsc => "FFPFSC",
        Ps5SourceKind.FilesystemImage => "exFAT",
        Ps5SourceKind.Ffpkg => "FFPKG",
        _ => "Other"
    };

    /// <summary>Base, Update, DLC or App, before superseded-update marking.</summary>
    public static string BaseRole(Ps5GameInfo game) => CategoryOf(game) switch
    {
        "Game" => "Base",
        "Patch" => "Update",
        "DLC" or "Add-on" => "DLC",
        "App" => "App",
        _ => "Unknown"
    };

    /// <summary>Base first, then updates, then DLC, then apps; used to order a family.</summary>
    public static int RolePriority(Ps5GameInfo game) => CategoryOf(game) switch
    {
        "Game" => 0,
        "Patch" => 1,
        "DLC" or "Add-on" => 2,
        "App" => 3,
        _ => 4
    };

    public static string FamilyKey(Ps5GameInfo game) =>
        !string.IsNullOrWhiteSpace(game.TitleId) ? game.TitleId
        : !string.IsNullOrWhiteSpace(game.ContentId) ? game.ContentId
        : LibraryFileName(game);

    public static string LibraryFileName(Ps5GameInfo game)
    {
        string trimmed = game.RootPath.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        string name = Path.GetFileName(trimmed);
        return string.IsNullOrEmpty(name) ? trimmed : name;
    }

    public static bool SourceExists(Ps5GameInfo game) =>
        game.SourceKind == Ps5SourceKind.LooseDump ? Directory.Exists(game.RootPath) : File.Exists(game.RootPath);

    public static string FormatBytes(long bytes)
    {
        string[] units = ["B", "KB", "MB", "GB", "TB"];
        double value = Math.Max(0, bytes);
        int unit = 0;
        while (value >= 1024 && unit < units.Length - 1) { value /= 1024; unit++; }
        return value.ToString(unit == 0 ? "0" : "0.##", CultureInfo.InvariantCulture) + " " + units[unit];
    }

    /// <summary>Compares dotted numeric versions ("01.020" vs "1.3"); null when either is not a version.</summary>
    public static int? CompareVersions(string? left, string? right)
    {
        long[]? a = ParseVersion(left);
        long[]? b = ParseVersion(right);
        if (a is null || b is null) return null;
        int length = Math.Max(a.Length, b.Length);
        for (int i = 0; i < length; i++)
        {
            long x = i < a.Length ? a[i] : 0;
            long y = i < b.Length ? b[i] : 0;
            if (x != y) return x < y ? -1 : 1;
        }
        return 0;
    }

    public static long[]? ParseVersion(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        var parts = new List<long>();
        foreach (string piece in value.Split('.', StringSplitOptions.RemoveEmptyEntries))
        {
            int digits = 0;
            while (digits < piece.Length && char.IsDigit(piece[digits])) digits++;
            if (digits == 0) break;
            if (!long.TryParse(piece[..digits], NumberStyles.None, CultureInfo.InvariantCulture, out long number))
                return null;
            parts.Add(number);
        }
        return parts.Count > 0 ? parts.ToArray() : null;
    }
}

/// <summary>
/// Orders dotted numeric version/system strings by value (1.10 after 1.9) with a text tie-break.
/// </summary>
public readonly record struct VersionKey(long Packed, string Raw) : IComparable<VersionKey>
{
    public static VersionKey Parse(string? value)
    {
        string raw = value ?? string.Empty;
        long packed = 0;
        long current = 0;
        bool any = false;
        int groups = 0;
        foreach (char c in raw)
        {
            if (char.IsDigit(c))
            {
                current = Math.Min(current * 10 + (c - '0'), 9_999);
                any = true;
            }
            else if (c == '.')
            {
                packed = packed * 10_000 + current;
                current = 0;
                any = false;
                if (++groups >= 3) break;
            }
        }
        if (any) packed = packed * 10_000 + current;
        return new VersionKey(packed, raw);
    }

    public int CompareTo(VersionKey other)
    {
        int byValue = Packed.CompareTo(other.Packed);
        return byValue != 0 ? byValue : string.Compare(Raw, other.Raw, StringComparison.OrdinalIgnoreCase);
    }
}

/// <summary>
/// The superseded-update index: patches for which a newer patch of the same title is in the library.
/// Rebuilt whenever the library changes so labeling and sorting never walk the whole list per item.
/// </summary>
public sealed class FamilyIndex
{
    private readonly HashSet<string> _superseded = new(StringComparer.Ordinal);
    private readonly HashSet<string> _titlesWithBase = new(StringComparer.OrdinalIgnoreCase);

    public FamilyIndex(IReadOnlyCollection<Ps5GameInfo> games)
    {
        var highest = new Dictionary<string, VersionKey>(StringComparer.OrdinalIgnoreCase);
        foreach (Ps5GameInfo game in games)
        {
            if (string.IsNullOrWhiteSpace(game.TitleId)) continue;
            string category = GameClassifier.CategoryOf(game);
            if (category == "Game") _titlesWithBase.Add(game.TitleId);
            if (category != "Patch") continue;
            VersionKey key = VersionKey.Parse(game.DisplayVersion);
            if (!highest.TryGetValue(game.TitleId, out VersionKey best) || key.CompareTo(best) > 0)
                highest[game.TitleId] = key;
        }
        foreach (Ps5GameInfo game in games)
        {
            if (string.IsNullOrWhiteSpace(game.TitleId) || GameClassifier.CategoryOf(game) != "Patch") continue;
            if (highest.TryGetValue(game.TitleId, out VersionKey best) &&
                VersionKey.Parse(game.DisplayVersion).CompareTo(best) < 0)
                _superseded.Add(game.RootPath);
        }
    }

    public bool IsSuperseded(Ps5GameInfo game) => _superseded.Contains(game.RootPath);

    /// <summary>True for a patch whose base game is not in the library.</summary>
    public bool IsMissingBase(Ps5GameInfo game) =>
        GameClassifier.CategoryOf(game) == "Patch" && !string.IsNullOrWhiteSpace(game.TitleId) &&
        !_titlesWithBase.Contains(game.TitleId);

    public string RoleOf(Ps5GameInfo game)
    {
        string role = GameClassifier.BaseRole(game);
        return role == "Update" && IsSuperseded(game) ? "Update (older)" : role;
    }
}
