using PS5PKGTool.Bridge.Infrastructure;
using PS5PKGTool.Bridge.Protocol;
using PS5PKGTool.Bridge.Tasks;
using PS5PKGTool.Core.Models;
using PS5PKGTool.Core.Services;
using PS5PKGTool.Core.Tasks;

namespace PS5PKGTool.Bridge.Library;

/// <summary>One planned rename or move, as shown in the preview before anything is touched.</summary>
public sealed record OrganizePlanItem(string Id, string Name, string Target, string TargetName, string Status, string Note);

/// <summary>
/// Rename and move-to-folder for library items. Plans are computed without touching disk and shown
/// to the user first; the same computation is used when the plan is applied, so the preview cannot
/// mislead.
/// </summary>
public sealed class Organizer(BridgeState state, LibraryService library, TaskService tasks)
{
    public static readonly string[] MoveModes = ["title", "titleid", "category", "region", "source", "flat"];

    // ------------------------------------------------------------------ rename

    public static string FormatOrDefault(string? format) =>
        string.IsNullOrWhiteSpace(format) ? AppSettingsNormalizer.DefaultRenameFormat : format.Trim();

    public static Ps5RenameTokens Tokens(Ps5GameInfo game) => new(
        Title: game.Title,
        TitleId: game.TitleId,
        ContentId: game.ContentId,
        ConceptId: game.ConceptId,
        Version: game.DisplayVersion,
        ContentVersion: game.ContentVersion,
        MasterVersion: game.MasterVersion,
        Category: GameClassifier.CategoryOf(game),
        Region: GameClassifier.RegionOf(game),
        Platform: game.Platform,
        SystemVersion: game.RequiredSystemSoftware,
        SdkVersion: game.SdkVersion,
        Source: game.SourceDescription,
        Size: game.SourceSize > 0 ? GameClassifier.FormatBytes(game.SourceSize) : string.Empty,
        Language: game.DefaultLanguage,
        Drm: game.DrmType,
        Date: game.CreationDate,
        Tool: game.ToolVersion);

    public static string BaseName(Ps5GameInfo game, string format) =>
        Ps5RenameFormatter.Expand(format, Tokens(game), FallbackName(game));

    private static string FallbackName(Ps5GameInfo game)
    {
        string name = Path.GetFileNameWithoutExtension(game.RootPath);
        if (string.IsNullOrWhiteSpace(name)) name = GameClassifier.LibraryFileName(game);
        return string.IsNullOrWhiteSpace(name) ? "PS5_GAME" : name;
    }

    /// <summary>Expands a format against a sample title for the live preview in Settings.</summary>
    public static object Example(string format, Ps5GameInfo? sample)
    {
        sample ??= new Ps5GameInfo
        {
            Title = "Astro's Playroom",
            TitleId = "PPSA01325",
            ContentId = "UP9000-PPSA01325_00-ASTROSPLAYROOM00",
            ContentVersion = "01.002.000",
            RequiredSystemSoftware = "1.00",
            SdkVersion = "1.00",
            ApplicationCategory = "0",
            SourceSize = 7_408_123_904,
            DrmType = "standard",
            DefaultLanguage = "en-US",
            RootPath = "/games/PPSA01325"
        };
        string expanded = Ps5RenameFormatter.Sanitize(BaseName(sample, FormatOrDefault(format)));
        string[] unknown = System.Text.RegularExpressions.Regex.Matches(format ?? string.Empty, @"\{([^}]*)\}")
            .Select(match => match.Groups[1].Value)
            .Where(token => !Ps5RenameFormatter.TokenNames.Contains("{" + token + "}", StringComparer.OrdinalIgnoreCase))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        return new { example = expanded, unknownTokens = unknown };
    }

    public List<OrganizePlanItem> PlanRename(IReadOnlyList<Ps5GameInfo> games, string format, bool installOrder)
    {
        IEnumerable<(Ps5GameInfo Game, string BaseName)> plans = installOrder
            ? InstallOrderPlans(games, format)
            : games.Select(game => (game, BaseName(game, format)));
        var result = new List<OrganizePlanItem>();
        var claimed = new HashSet<string>(StringComparer.Ordinal);
        foreach ((Ps5GameInfo game, string baseName) in plans)
        {
            string name = GameClassifier.LibraryFileName(game);
            if (tasks.IsPathBusy(game.RootPath))
            {
                result.Add(new OrganizePlanItem(game.RootPath, name, string.Empty, string.Empty, "error", "in use by a queued or running task"));
                continue;
            }
            if (!TryResolveRenameTarget(game, baseName, claimed, out string target, out bool conflict, out string? error))
            {
                result.Add(new OrganizePlanItem(game.RootPath, name, string.Empty, string.Empty, "error", error ?? string.Empty));
                continue;
            }
            if (target.Length == 0)
            {
                result.Add(new OrganizePlanItem(game.RootPath, name, game.RootPath, name, "unchanged", "already named this way"));
                continue;
            }
            claimed.Add(target);
            result.Add(new OrganizePlanItem(game.RootPath, name, target, Path.GetFileName(target),
                conflict ? "conflict" : "rename", conflict ? "name taken, numbered instead" : string.Empty));
        }
        return result;
    }

    public object ApplyRename(IReadOnlyList<Ps5GameInfo> games, string format, bool installOrder)
    {
        List<OrganizePlanItem> plan = PlanRename(games, format, installOrder);
        int renamed = 0, skipped = 0;
        var failures = new List<string>();
        foreach (OrganizePlanItem item in plan)
        {
            if (item.Status is not ("rename" or "conflict"))
            {
                if (item.Status == "error") skipped++;
                continue;
            }
            Ps5GameInfo? game = library.Find(item.Id);
            if (game is null) { skipped++; continue; }
            try
            {
                if (File.Exists(item.Target) || Directory.Exists(item.Target))
                    throw new IOException("the target name was taken since the preview");
                if (Directory.Exists(item.Id)) Directory.Move(item.Id, item.Target);
                else File.Move(item.Id, item.Target);
                library.RewritePath(game, item.Id, item.Target);
                renamed++;
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
            {
                skipped++;
                failures.Add($"{item.Name}: {ex.Message}");
                Logger.Warn($"Rename skipped for '{item.Id}': {ex.Message}");
            }
        }
        library.SaveManifest();
        library.AnnounceChanged("rename");
        Logger.Info($"Renamed {renamed:N0} item(s); skipped {skipped:N0}.");
        return new { renamed, skipped, failures };
    }

    private static IEnumerable<(Ps5GameInfo Game, string BaseName)> InstallOrderPlans(IReadOnlyList<Ps5GameInfo> games, string format)
    {
        IEnumerable<IGrouping<string, Ps5GameInfo>> groups = games
            .Where(game => game.SourceKind == Ps5SourceKind.SonyPackage)
            .GroupBy(game => game.TitleId, StringComparer.OrdinalIgnoreCase)
            .Where(group => !string.IsNullOrWhiteSpace(group.Key))
            .OrderBy(group => group.Key, StringComparer.OrdinalIgnoreCase);
        foreach (IGrouping<string, Ps5GameInfo> group in groups)
        {
            // Versions compare numerically (1.10 after 1.9), unlike the text ordering the Windows
            // edition used here.
            List<Ps5GameInfo> ordered = group
                .OrderBy(GameClassifier.RolePriority)
                .ThenBy(game => VersionKey.Parse(game.DisplayVersion))
                .ThenBy(game => game.RootPath, StringComparer.Ordinal)
                .ToList();
            for (int index = 0; index < ordered.Count; index++)
                yield return (ordered[index], $"{index:D2} - {BaseName(ordered[index], format)}");
        }
    }

    private static bool TryResolveRenameTarget(Ps5GameInfo game, string baseName, HashSet<string> claimed,
        out string target, out bool conflict, out string? error)
    {
        string source = game.RootPath;
        target = string.Empty;
        conflict = false;
        error = null;
        bool isDirectory = Directory.Exists(source);
        if (!isDirectory && !File.Exists(source))
        {
            error = "source no longer exists";
            return false;
        }
        string safeBase = Ps5RenameFormatter.Sanitize(baseName);
        if (safeBase.Length == 0)
        {
            error = "the format produced an empty name";
            return false;
        }
        string? parent = Path.GetDirectoryName(source);
        if (string.IsNullOrEmpty(parent))
        {
            error = "no parent folder";
            return false;
        }
        string extension = isDirectory ? string.Empty : Path.GetExtension(source);
        string raw = Path.Combine(parent, safeBase + extension);
        if (string.Equals(raw, source, StringComparison.Ordinal)) return true;
        conflict = File.Exists(raw) || Directory.Exists(raw) || claimed.Contains(raw);
        target = conflict ? UniquePath(raw, isDirectory, claimed) : raw;
        return true;
    }

    private static string UniquePath(string target, bool isDirectory, HashSet<string> claimed)
    {
        string? parent = Path.GetDirectoryName(target);
        string name = isDirectory ? Path.GetFileName(target) : Path.GetFileNameWithoutExtension(target);
        string extension = isDirectory ? string.Empty : Path.GetExtension(target);
        for (int index = 2; index < 10000; index++)
        {
            string candidate = Path.Combine(parent ?? string.Empty, $"{name} ({index}){extension}");
            if (!File.Exists(candidate) && !Directory.Exists(candidate) && !claimed.Contains(candidate)) return candidate;
        }
        return target;
    }

    // ------------------------------------------------------------------ move

    public static string MoveModeLabel(string mode) => mode switch
    {
        "titleid" => "Title ID",
        "category" => "Category",
        "region" => "Region",
        "source" => "Format",
        "flat" => "a single folder",
        _ => "Title"
    };

    public List<OrganizePlanItem> PlanMove(IReadOnlyList<Ps5GameInfo> games, string destinationRoot, string mode)
    {
        var result = new List<OrganizePlanItem>();
        var claimed = new HashSet<string>(StringComparer.Ordinal);
        foreach (Ps5GameInfo game in games)
        {
            string source = game.RootPath;
            string name = GameClassifier.LibraryFileName(game);
            string? note = null;
            string target = string.Empty;
            string status = "move";
            if (tasks.IsPathBusy(source)) note = "in use by a queued or running task";
            else if (string.IsNullOrWhiteSpace(source) || (!Directory.Exists(source) && !File.Exists(source))) note = "source not found";
            else if (GroupFolder(game, mode) is not { } group) note = $"no {MoveModeLabel(mode)} value";
            else
            {
                target = Path.Combine(destinationRoot, group, name);
                if (string.Equals(target, source, StringComparison.Ordinal))
                {
                    status = "unchanged";
                    note = "already in the destination";
                }
                else if (File.Exists(target) || Directory.Exists(target) || !claimed.Add(target)) note = "destination already exists";
            }
            if (note is not null && status != "unchanged") status = "error";
            result.Add(new OrganizePlanItem(source, name, target,
                target.Length > 0 ? Path.GetRelativePath(destinationRoot, target) : string.Empty, status, note ?? string.Empty));
        }
        return result;
    }

    public object EnqueueMove(IReadOnlyList<Ps5GameInfo> games, string destinationRoot, string mode, bool addToLibrary)
    {
        if (!Directory.Exists(destinationRoot)) throw RpcException.NotFound("The destination folder does not exist.");
        List<OrganizePlanItem> plan = PlanMove(games, destinationRoot, mode).Where(item => item.Status == "move").ToList();
        if (plan.Count == 0) throw RpcException.BadRequest("Nothing can be moved: every item was skipped in the preview.");
        string label = MoveModeLabel(mode);
        var moved = new List<(string Source, string Target)>();
        var skipped = new List<string>();
        QueuedPackageTask task = tasks.EnqueueTransient(PackageTaskTypes.LibraryMove, $"Move {plan.Count:N0} item(s) by {label}",
            (progress, token) =>
            {
                int index = 0;
                foreach (OrganizePlanItem item in plan)
                {
                    token.ThrowIfCancellationRequested();
                    progress.Report(new PackageTaskProgress("Moving", 0, 0, 0, 0, index, plan.Count, item.Name));
                    index++;
                    try
                    {
                        if (File.Exists(item.Target) || Directory.Exists(item.Target))
                            throw new IOException("destination already exists");
                        Directory.CreateDirectory(Path.GetDirectoryName(item.Target)!);
                        LibraryFileMover.Move(item.Id, item.Target, token, progress);
                        lock (moved) moved.Add((item.Id, item.Target));
                        Logger.Info($"Moved {item.Id} -> {item.Target}");
                    }
                    catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
                    {
                        skipped.Add($"{item.Name}: {ex.Message}");
                        Logger.Warn($"Move failed for '{item.Id}': {ex.Message}");
                    }
                }
                progress.Report(new PackageTaskProgress("Moving", 0, 0, 0, 0, plan.Count, plan.Count, string.Empty));
                return Task.CompletedTask;
            },
            destinationRoot, "Move", "library", label,
            _ =>
            {
                lock (moved)
                    foreach ((string source, string target) in moved)
                        if (library.Find(source) is { } game)
                            library.RewritePath(game, source, target);
                if (addToLibrary)
                    state.UpdateSettings(settings =>
                    {
                        if (!LibraryService.IsUnderLibrary(settings, destinationRoot)) settings.LibraryFolders.Add(destinationRoot);
                    });
                library.SaveManifest();
                library.AnnounceChanged("move");
                Logger.Info($"Move by {label}: {moved.Count:N0} moved, {skipped.Count:N0} skipped.");
            });
        return new { taskId = task.Id, count = plan.Count };
    }

    private static string? GroupFolder(Ps5GameInfo game, string mode)
    {
        string category = GameClassifier.CategoryOf(game);
        return mode switch
        {
            "title" => category switch
            {
                "DLC" or "Add-on" => Path.Combine("Addon", SafeFolder(game.TitleId, "UNKNOWN_TITLEID")),
                "App" => Path.Combine("App", SafeFolder(game.Title, "UNKNOWN_TITLE")),
                "Game" or "Patch" => Path.Combine("Base + Update", SafeFolder(game.Title, "UNKNOWN_TITLE")),
                _ => null
            },
            "titleid" => SafeFolder(game.TitleId, "UNKNOWN_TITLEID"),
            "category" => category switch
            {
                "Game" => "Game",
                "Patch" => "Patch",
                "DLC" or "Add-on" => "Dlc",
                "App" => "App",
                _ => null
            },
            "region" => SafeFolder(GameClassifier.RegionOf(game), "Other"),
            "source" => SafeFolder(game.SourceDescription, "Other"),
            "flat" => string.Empty,
            _ => null
        };
    }

    private static string SafeFolder(string value, string fallback)
    {
        string safe = Ps5RenameFormatter.Sanitize(value);
        return safe.Length > 0 ? safe : Ps5RenameFormatter.Sanitize(fallback);
    }
}
