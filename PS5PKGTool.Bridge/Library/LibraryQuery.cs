using System.Globalization;
using System.Text;
using PS5PKGTool.Core.Models;

namespace PS5PKGTool.Bridge.Library;

/// <summary>
/// The library search grammar: space-separated AND terms, quoted phrases, <c>-</c> negation,
/// <c>field:value</c> prefixes, <c>|</c> alternatives inside a value, <c>=</c> exact text matches and
/// numeric comparisons for <c>size:</c>, <c>version:</c> and <c>fw:</c>. Identical to the Windows
/// edition so saved views and habits carry over.
/// </summary>
public sealed class LibraryQuery
{
    public static readonly string[] FieldKeys =
    [
        "title", "id", "titleid", "title-id", "content", "contentid", "content-id",
        "category", "role", "region", "source", "format", "drm", "path", "location",
        "feature", "features", "size", "version", "fw", "firmware"
    ];

    /// <summary>Field hints shown by the search autocomplete.</summary>
    public static readonly (string Field, string Example, string Help)[] FieldHelp =
    [
        ("title:", "title:\"gran turismo\"", "Title contains text"),
        ("id:", "id:=PPSA01234", "Title ID (use = for an exact match)"),
        ("content:", "content:UP9000", "Content ID contains text"),
        ("category:", "category:patch|dlc", "Game, Patch, DLC or App"),
        ("role:", "role:older", "Base, Update, Update (older), DLC, App"),
        ("region:", "region:europe", "Americas, Europe, Japan, Korea, Asia, Hong Kong"),
        ("source:", "source:exfat", "Dump Files, PKG, FFPFSC, exFAT, FFPKG"),
        ("size:", "size:>50GB", "Size with >, >=, <, <=, = and B/KB/MB/GB/TB"),
        ("version:", "version:>=1.10", "Content version comparison"),
        ("fw:", "fw:<=7.00", "Required system software comparison"),
        ("feature:", "feature:vr", "Declared feature"),
        ("drm:", "drm:free", "DRM type"),
        ("path:", "path:/mnt/games", "Location contains text"),
    ];

    private readonly List<(string Body, bool Negate)> _tokens = [];

    public LibraryQuery(string? query)
    {
        Text = query?.Trim() ?? string.Empty;
        foreach (string token in Tokenize(Text))
        {
            bool negate = token.Length > 1 && token[0] == '-';
            string body = negate ? token[1..] : token;
            if (body.Length > 0) _tokens.Add((body, negate));
        }
    }

    public string Text { get; }

    public bool IsEmpty => _tokens.Count == 0;

    public bool Matches(Ps5GameInfo game, FamilyIndex family)
    {
        foreach ((string body, bool negate) in _tokens)
        {
            int colon = body.IndexOf(':');
            bool match = colon > 0
                ? MatchField(game, family, body[..colon].ToLowerInvariant(), body[(colon + 1)..])
                : MatchFreeText(game, body);
            if (negate) match = !match;
            if (!match) return false;
        }
        return true;
    }

    /// <summary>
    /// A human-readable hint when the query cannot be understood, or null when it is fine. The query
    /// still runs; this only surfaces the likely mistake.
    /// </summary>
    public static string? Validate(string? query)
    {
        if (string.IsNullOrWhiteSpace(query)) return null;
        if (query.Count(c => c == '"') % 2 != 0) return "Unbalanced quotation marks.";

        foreach (string token in Tokenize(query))
        {
            string body = token.Length > 1 && token[0] == '-' ? token[1..] : token;
            if (body.Length == 0) continue;
            int colon = body.IndexOf(':');
            if (colon <= 0) continue;

            string field = body[..colon].ToLowerInvariant();
            string value = body[(colon + 1)..];
            if (Array.IndexOf(FieldKeys, field) < 0)
                return $"Unknown field '{field}:'. Valid fields: title, id, content, category, role, region, source, size, version, fw, feature, drm, path.";
            if (value.Length == 0) return $"'{field}:' needs a value.";

            if (field == "size" && !(TryParseComparison(value, out _, out string sizeRest) && TryParseSize(sizeRest, out _))
                && !TryParseSize(value, out _))
                return $"'{value}' is not a valid size (try size:>50GB).";
            if (field is "version" or "fw" or "firmware")
            {
                if (!TryParseComparison(value, out _, out string versionRest)) continue;
                if (versionRest.Length == 0) return $"'{field}:' is missing a value after the comparison.";
                if (GameClassifier.CompareVersions(versionRest, versionRest) is null)
                    return $"'{versionRest}' is not a valid version.";
            }
        }
        return null;
    }

    public static IEnumerable<string> Tokenize(string query)
    {
        var tokens = new List<string>();
        var current = new StringBuilder();
        bool quoted = false;
        foreach (char c in query)
        {
            if (c == '"')
            {
                quoted = !quoted;
                continue;
            }
            if (!quoted && char.IsWhiteSpace(c))
            {
                if (current.Length > 0)
                {
                    tokens.Add(current.ToString());
                    current.Clear();
                }
                continue;
            }
            current.Append(c);
        }
        if (current.Length > 0) tokens.Add(current.ToString());
        return tokens;
    }

    private static bool MatchFreeText(Ps5GameInfo game, string value) =>
        MatchAny(value, part =>
            ContainsText(game.Title, part) ||
            ContainsText(game.TitleId, part) ||
            ContainsText(game.ContentId, part) ||
            ContainsText(game.RootPath, part) ||
            ContainsText(game.SourceDescription, part) ||
            game.LocalizedTitles.Values.Any(title => ContainsText(title, part)));

    private static bool MatchField(Ps5GameInfo game, FamilyIndex family, string field, string value) => field switch
    {
        "title" => MatchText(game.Title, value) || game.LocalizedTitles.Values.Any(title => MatchText(title, value)),
        "id" or "titleid" or "title-id" => MatchText(game.TitleId, value),
        "content" or "contentid" or "content-id" => MatchText(game.ContentId, value),
        "category" => MatchAny(value, part => ContainsText(GameClassifier.CategoryOf(game), part)),
        "role" => MatchAny(value, part => ContainsText(family.RoleOf(game), part)),
        "region" => MatchAny(value, part => ContainsText(GameClassifier.RegionOf(game), part)),
        "source" or "format" => MatchAny(value, part =>
            ContainsText(game.SourceDescription, part) || ContainsText(GameClassifier.FormatOf(game), part)),
        "drm" => MatchAny(value, part => ContainsText(game.DrmType, part)),
        "path" or "location" => MatchAny(value, part => ContainsText(game.RootPath, part)),
        "feature" or "features" => MatchAny(value, part => game.DeclaredFeatures.Any(feature => ContainsText(feature, part))),
        "size" => MatchSize(value, game.SourceSize),
        "version" => MatchVersion(value, game.DisplayVersion),
        "fw" or "firmware" => MatchVersion(value, game.RequiredSystemSoftware),
        _ => MatchFreeText(game, value)
    };

    private static bool MatchText(string? source, string value)
    {
        if (value.StartsWith('='))
            return string.Equals(source, value[1..].Trim(), StringComparison.OrdinalIgnoreCase);
        return MatchAny(value, part => ContainsText(source, part));
    }

    private static bool MatchAny(string value, Func<string, bool> predicate)
    {
        foreach (string part in value.Split('|', StringSplitOptions.RemoveEmptyEntries))
            if (predicate(part)) return true;
        return false;
    }

    private static bool ContainsText(string? source, string value) =>
        !string.IsNullOrEmpty(source) && source.Contains(value, StringComparison.OrdinalIgnoreCase);

    private static bool MatchSize(string value, long size)
    {
        if (TryParseComparison(value, out string op, out string rest) && TryParseSize(rest, out long target))
            return Satisfies(size.CompareTo(target), op);
        return TryParseSize(value, out long minimum) && size >= minimum;
    }

    private static bool MatchVersion(string value, string candidate)
    {
        if (TryParseComparison(value, out string op, out string rest))
            return GameClassifier.CompareVersions(candidate, rest) is int comparison && Satisfies(comparison, op);
        return ContainsText(candidate, value);
    }

    private static bool TryParseComparison(string value, out string op, out string rest)
    {
        foreach (string candidate in new[] { ">=", "<=", ">", "<", "=" })
        {
            if (value.StartsWith(candidate, StringComparison.Ordinal))
            {
                op = candidate;
                rest = value[candidate.Length..].Trim();
                return true;
            }
        }
        op = "=";
        rest = value;
        return false;
    }

    private static bool Satisfies(int comparison, string op) => op switch
    {
        ">" => comparison > 0,
        "<" => comparison < 0,
        ">=" => comparison >= 0,
        "<=" => comparison <= 0,
        _ => comparison == 0
    };

    public static bool TryParseSize(string value, out long bytes)
    {
        bytes = 0;
        if (string.IsNullOrWhiteSpace(value)) return false;
        string text = value.Trim().ToUpperInvariant().Replace(" ", string.Empty);
        int digits = 0;
        while (digits < text.Length && (char.IsDigit(text[digits]) || text[digits] == '.')) digits++;
        if (digits == 0 ||
            !double.TryParse(text[..digits], NumberStyles.Float, CultureInfo.InvariantCulture, out double number))
            return false;
        double multiplier = text[digits..] switch
        {
            "" or "B" => 1d,
            "K" or "KB" or "KIB" => 1024d,
            "M" or "MB" or "MIB" => 1024d * 1024d,
            "G" or "GB" or "GIB" => 1024d * 1024d * 1024d,
            "T" or "TB" or "TIB" => 1024d * 1024d * 1024d * 1024d,
            _ => 0d
        };
        if (multiplier == 0d) return false;
        bytes = (long)(number * multiplier);
        return true;
    }
}
