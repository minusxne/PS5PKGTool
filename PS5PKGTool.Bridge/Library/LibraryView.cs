using PS5PKGTool.Core.Models;

namespace PS5PKGTool.Bridge.Library;

/// <summary>What the client asks to see: query, filter sets, sort keys and grouping.</summary>
public sealed class LibraryViewRequest
{
    public string Query { get; set; } = string.Empty;
    public List<string> Categories { get; set; } = [];
    public List<string> Regions { get; set; } = [];
    public List<string> Formats { get; set; } = [];
    /// <summary>Ordered sort keys such as "Title:asc" or "Size:desc".</summary>
    public List<string> SortKeys { get; set; } = [];
    /// <summary>"", family, titleid, category, region, source or firmware.</summary>
    public string GroupBy { get; set; } = string.Empty;
}

public sealed record LibraryViewGroup(string Key, string Label, int Count, IReadOnlyList<string> Ids);

public sealed record LibraryViewResult(
    IReadOnlyList<string> Ids,
    IReadOnlyList<LibraryViewGroup> Groups,
    int VisibleCount,
    int TotalCount,
    string? Warning);

/// <summary>Filters, sorts and groups the library the same way the Windows grid does.</summary>
public static class LibraryView
{
    public static readonly string[] SortColumns =
        ["Title", "TitleId", "ContentId", "Category", "Role", "Region", "Source", "Size", "Version", "Firmware",
         "Features", "Drm", "FileName", "Location"];

    public static LibraryViewResult Build(IReadOnlyList<Ps5GameInfo> games, FamilyIndex family, LibraryViewRequest request)
    {
        var query = new LibraryQuery(request.Query);
        var categories = new HashSet<string>(request.Categories, StringComparer.OrdinalIgnoreCase);
        var regions = new HashSet<string>(request.Regions, StringComparer.OrdinalIgnoreCase);
        var formats = new HashSet<string>(request.Formats, StringComparer.OrdinalIgnoreCase);

        List<Ps5GameInfo> visible = games.Where(game =>
                (categories.Count == 0 || categories.Contains(GameClassifier.CategoryOf(game))) &&
                (regions.Count == 0 || regions.Contains(GameClassifier.RegionOf(game))) &&
                (formats.Count == 0 || formats.Contains(GameClassifier.FormatOf(game))) &&
                query.Matches(game, family))
            .ToList();

        string groupBy = request.GroupBy ?? string.Empty;
        if (groupBy == "family") visible.Sort(FamilyComparison);
        else
        {
            Comparison<Ps5GameInfo> comparison = SortComparison(ParseSortKeys(request.SortKeys), family);
            visible.Sort((a, b) =>
            {
                int result = comparison(a, b);
                return result != 0 ? result : string.Compare(a.Title, b.Title, StringComparison.CurrentCultureIgnoreCase);
            });
        }

        var groups = new List<LibraryViewGroup>();
        if (groupBy.Length > 0)
        {
            // Groups keep the item order inside them and are listed by key (family keeps title order).
            IEnumerable<IGrouping<string, Ps5GameInfo>> grouped = visible.GroupBy(game => GroupKey(game, groupBy),
                StringComparer.OrdinalIgnoreCase);
            grouped = groupBy == "firmware"
                ? grouped.OrderBy(group => VersionKey.Parse(group.Key))
                : grouped.OrderBy(group => group.Key.Length == 0 ? "￿" : group.Key, StringComparer.CurrentCultureIgnoreCase);
            foreach (IGrouping<string, Ps5GameInfo> group in grouped)
            {
                string label = GroupLabel(groupBy, group.Key, group.First());
                groups.Add(new LibraryViewGroup(group.Key, label, group.Count(),
                    group.Select(game => game.RootPath).ToList()));
            }
            visible = groups.SelectMany(group => group.Ids)
                .Join(visible, id => id, game => game.RootPath, (_, game) => game).ToList();
        }

        return new LibraryViewResult(visible.Select(game => game.RootPath).ToList(), groups, visible.Count,
            games.Count, LibraryQuery.Validate(request.Query));
    }

    public static string GroupKey(Ps5GameInfo game, string groupBy) => groupBy switch
    {
        "family" => GameClassifier.FamilyKey(game),
        "titleid" => game.TitleId,
        "category" => GameClassifier.CategoryOf(game),
        "region" => GameClassifier.RegionOf(game),
        "source" => game.SourceDescription,
        "firmware" => game.RequiredSystemSoftware,
        _ => string.Empty
    };

    private static string GroupLabel(string groupBy, string key, Ps5GameInfo sample)
    {
        string value = key.Length == 0 ? "(none)" : key;
        return groupBy switch
        {
            // A family header reads better with the title than with a bare ID.
            "family" => string.IsNullOrWhiteSpace(sample.Title) ? value : $"{sample.Title}  ·  {value}",
            "titleid" => value,
            "firmware" => key.Length == 0 ? "Firmware unknown" : "Firmware " + value,
            _ => value
        };
    }

    /// <summary>Family order: by title ID, then base, updates (newest first), DLC and apps.</summary>
    private static int FamilyComparison(Ps5GameInfo a, Ps5GameInfo b)
    {
        int byFamily = string.Compare(GameClassifier.FamilyKey(a), GameClassifier.FamilyKey(b), StringComparison.OrdinalIgnoreCase);
        if (byFamily != 0) return byFamily;
        int byRole = GameClassifier.RolePriority(a).CompareTo(GameClassifier.RolePriority(b));
        if (byRole != 0) return byRole;
        return VersionKey.Parse(b.DisplayVersion).CompareTo(VersionKey.Parse(a.DisplayVersion));
    }

    public static List<(string Column, bool Ascending)> ParseSortKeys(IEnumerable<string>? keys)
    {
        var result = new List<(string, bool)>();
        foreach (string key in keys ?? [])
        {
            string[] parts = key.Split(':', 2);
            string column = SortColumns.FirstOrDefault(name => name.Equals(parts[0].Trim(), StringComparison.OrdinalIgnoreCase)) ?? string.Empty;
            if (column.Length == 0) continue;
            bool ascending = parts.Length < 2 || !parts[1].Trim().Equals("desc", StringComparison.OrdinalIgnoreCase);
            result.Add((column, ascending));
        }
        return result;
    }

    private static Comparison<Ps5GameInfo> SortComparison(List<(string Column, bool Ascending)> keys, FamilyIndex family)
    {
        if (keys.Count == 0) keys = [("Title", true)];
        var comparisons = keys.Select(key => KeyComparison(key, family)).ToList();
        return (a, b) =>
        {
            foreach (Comparison<Ps5GameInfo> comparison in comparisons)
            {
                int result = comparison(a, b);
                if (result != 0) return result;
            }
            return 0;
        };
    }

    private static Comparison<Ps5GameInfo> KeyComparison((string Column, bool Ascending) key, FamilyIndex family)
    {
        Func<Ps5GameInfo, object?> selector = key.Column switch
        {
            "TitleId" => game => game.TitleId,
            "ContentId" => game => game.ContentId,
            "Category" => game => GameClassifier.CategoryOf(game),
            "Role" => game => family.RoleOf(game),
            "Region" => game => GameClassifier.RegionOf(game),
            "Source" => game => game.SourceDescription,
            "Size" => game => game.SourceSize,
            "Version" => game => VersionKey.Parse(game.DisplayVersion),
            "Firmware" => game => VersionKey.Parse(game.RequiredSystemSoftware),
            "Features" => game => string.Join(", ", game.DeclaredFeatures),
            "Drm" => game => game.DrmType,
            "FileName" => game => GameClassifier.LibraryFileName(game),
            "Location" => game => game.RootPath,
            _ => game => game.Title
        };
        int sign = key.Ascending ? 1 : -1;
        return (a, b) =>
        {
            object? left = selector(a);
            object? right = selector(b);
            int result = left is long lx && right is long ly
                ? lx.CompareTo(ly)
                : left is VersionKey vx && right is VersionKey vy
                    ? vx.CompareTo(vy)
                    : string.Compare(left?.ToString(), right?.ToString(), StringComparison.CurrentCultureIgnoreCase);
            return result * sign;
        };
    }
}
