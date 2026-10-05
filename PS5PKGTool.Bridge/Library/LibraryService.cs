using System.Security.Cryptography;
using System.Text;
using PS5PKGTool.Bridge.Infrastructure;
using PS5PKGTool.Bridge.Protocol;
using PS5PKGTool.Core.Models;
using PS5PKGTool.Core.Services;

namespace PS5PKGTool.Bridge.Library;

/// <summary>One library item as the UI sees it. <see cref="Id"/> is the source path.</summary>
public sealed record GameRow(
    string Id,
    string Title,
    string TitleId,
    string ContentId,
    string ConceptId,
    string Category,
    string Role,
    string Region,
    string Format,
    string Source,
    string SourceKind,
    string Platform,
    long SizeBytes,
    string SizeText,
    string Version,
    string ContentVersion,
    string MasterVersion,
    string TargetVersion,
    string Firmware,
    string Sdk,
    string Drm,
    IReadOnlyList<string> Features,
    string Language,
    string CreationDate,
    string FileName,
    string Location,
    bool Missing,
    bool Superseded,
    bool MissingBase,
    int WarningCount,
    string Icon,
    string Background);

/// <summary>
/// Owns the library list: scanning, the manifest cache, the folders and sources it covers, and the
/// view/filter logic. All state changes are serialized through one lock and announced with a
/// <c>library.changed</c> event so the UI can refetch.
/// </summary>
public sealed class LibraryService
{
    private readonly BridgeState _state;
    private readonly Ps5LibraryScanner _scanner = new();
    private readonly object _gate = new();
    private List<Ps5GameInfo> _games = [];
    private FamilyIndex _family = new([]);
    private CancellationTokenSource? _scanCancellation;
    private int _sizeWalkRunning;

    public LibraryService(BridgeState state, ArtworkCache artwork)
    {
        _state = state;
        Artwork = artwork;
    }

    public ArtworkCache Artwork { get; }

    public bool IsScanning => _scanCancellation is not null;

    /// <summary>Loads the cached manifest, keeping only entries under the configured roots.</summary>
    public void LoadManifest()
    {
        List<Ps5GameInfo> games = _state.Store.LoadManifest().Games;
        int before = games.Count;
        games = games.Where(game => !string.IsNullOrWhiteSpace(game.RootPath) && IsCovered(game.RootPath) &&
                                    ExtensionMatchesKind(game)).ToList();
        lock (_gate) SetGames(games);
        if (games.Count != before) SaveManifest();
        Logger.Info($"Loaded {games.Count:N0} cached library item(s).");
        StartDumpSizeWalk();
    }

    public IReadOnlyList<Ps5GameInfo> Games
    {
        get { lock (_gate) return _games.ToArray(); }
    }

    public Ps5GameInfo? Find(string id)
    {
        lock (_gate) return _games.FirstOrDefault(game => string.Equals(game.RootPath, id, StringComparison.Ordinal));
    }

    public Ps5GameInfo Require(string id) =>
        Find(id) ?? throw RpcException.NotFound("That item is no longer in the library. Refresh the library and try again.");

    public List<Ps5GameInfo> RequireMany(IEnumerable<string> ids) => ids.Select(Require).ToList();

    public FamilyIndex Family
    {
        get { lock (_gate) return _family; }
    }

    public IReadOnlyList<GameRow> Rows()
    {
        Ps5GameInfo[] games;
        FamilyIndex family;
        lock (_gate)
        {
            games = _games.ToArray();
            family = _family;
        }
        return games.Select(game => ToRow(game, family)).ToList();
    }

    public GameRow Row(Ps5GameInfo game) => ToRow(game, Family);

    public LibraryViewResult View(LibraryViewRequest request)
    {
        Ps5GameInfo[] games;
        FamilyIndex family;
        lock (_gate)
        {
            games = _games.ToArray();
            family = _family;
        }
        return LibraryView.Build(games, family, request);
    }

    private GameRow ToRow(Ps5GameInfo game, FamilyIndex family)
    {
        ArtworkPaths art = Artwork.Peek(game);
        return new GameRow(
            game.RootPath,
            string.IsNullOrWhiteSpace(game.Title) ? GameClassifier.LibraryFileName(game) : game.Title,
            game.TitleId,
            game.ContentId,
            game.ConceptId,
            GameClassifier.CategoryOf(game),
            family.RoleOf(game),
            GameClassifier.RegionOf(game),
            GameClassifier.FormatOf(game),
            game.SourceDescription,
            game.SourceKind.ToString(),
            game.Platform,
            game.SourceSize,
            game.SourceSize > 0 ? GameClassifier.FormatBytes(game.SourceSize) : string.Empty,
            game.DisplayVersion,
            game.ContentVersion,
            game.MasterVersion,
            game.TargetContentVersion,
            game.RequiredSystemSoftware,
            game.SdkVersion,
            game.DrmType,
            game.DeclaredFeatures,
            game.DefaultLanguage,
            game.CreationDate,
            GameClassifier.LibraryFileName(game),
            game.RootPath,
            !GameClassifier.SourceExists(game),
            family.IsSuperseded(game),
            family.IsMissingBase(game),
            game.DataWarnings.Count,
            art.Icon,
            art.Background);
    }

    // ------------------------------------------------------------------ scanning

    public IReadOnlyList<string> ScanRoots() => _state.Settings.LibraryFolders
        .Concat(_state.Settings.ManualSources)
        .Where(path => !string.IsNullOrWhiteSpace(path))
        .Distinct(StringComparer.Ordinal)
        .ToArray();

    /// <summary>Scans <paramref name="roots"/> (or every configured root) and merges or replaces the list.</summary>
    public async Task<object> ScanAsync(IReadOnlyList<string>? roots, bool merge, CancellationToken token)
    {
        IReadOnlyList<string> folders = roots is { Count: > 0 } ? roots : ScanRoots();
        if (folders.Count == 0)
        {
            if (!merge)
            {
                lock (_gate) SetGames([]);
                SaveManifest();
                AnnounceChanged("scan");
            }
            return new { count = 0, added = 0, errors = Array.Empty<string>() };
        }

        CancellationTokenSource? previous = Interlocked.Exchange(ref _scanCancellation,
            CancellationTokenSource.CreateLinkedTokenSource(token));
        previous?.Cancel();
        CancellationTokenSource scan = _scanCancellation!;
        _state.Server.Emit("scan.started", new { roots = folders });
        Logger.Info($"Scanning {folders.Count:N0} location(s)...");

        long lastEmit = 0;
        var progress = new InlineProgress<Ps5ScanProgress>(value =>
        {
            long now = Environment.TickCount64;
            if (now - lastEmit < 100 && value.Processed < value.Total) return;
            lastEmit = now;
            _state.Server.Emit("scan.progress", new { processed = value.Processed, total = value.Total, path = value.CurrentPath });
        });

        try
        {
            Ps5ScanResult result = await _scanner.ScanAsync(folders, _state.Settings.RecursiveScan, Games, progress, scan.Token)
                .ConfigureAwait(false);
            int added;
            lock (_gate)
            {
                if (merge)
                {
                    var byPath = _games.ToDictionary(game => game.RootPath, StringComparer.Ordinal);
                    int beforeCount = byPath.Count;
                    foreach (Ps5GameInfo game in result.Games) byPath[game.RootPath] = game;
                    added = byPath.Count - beforeCount;
                    SetGames(byPath.Values.OrderBy(game => game.Title, StringComparer.CurrentCultureIgnoreCase).ToList());
                }
                else
                {
                    added = result.Games.Count - _games.Count;
                    SetGames(result.Games);
                }
            }
            SaveManifest();
            foreach (string error in result.Errors) Logger.Warn("Scan: " + error);
            Logger.Info($"Scan finished: {result.Games.Count:N0} item(s), {result.Errors.Count:N0} problem(s).");
            AnnounceChanged("scan");
            StartDumpSizeWalk();
            return new { count = Games.Count, added, errors = result.Errors };
        }
        finally
        {
            Interlocked.CompareExchange(ref _scanCancellation, null, scan);
            scan.Dispose();
            _state.Server.Emit("scan.finished", new { });
        }
    }

    public void CancelScan() => _scanCancellation?.Cancel();

    /// <summary>
    /// Loose dump sizes are not measured during the scan (that would walk every folder up front);
    /// they are filled in afterwards in the background and saved back to the manifest.
    /// </summary>
    private void StartDumpSizeWalk()
    {
        if (Interlocked.Exchange(ref _sizeWalkRunning, 1) == 1) return;
        _ = Task.Run(() =>
        {
            try
            {
                int updated = 0;
                foreach (Ps5GameInfo game in Games.Where(game => game.SourceKind == Ps5SourceKind.LooseDump && game.SourceSize <= 0))
                {
                    if (!Directory.Exists(game.RootPath)) continue;
                    long total = 0;
                    try
                    {
                        foreach (string file in Directory.EnumerateFiles(game.RootPath, "*", new EnumerationOptions
                                 {
                                     RecurseSubdirectories = true,
                                     IgnoreInaccessible = true,
                                     AttributesToSkip = FileAttributes.ReparsePoint
                                 }))
                            total += new FileInfo(file).Length;
                    }
                    catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
                    {
                        continue;
                    }
                    game.SourceSize = total;
                    updated++;
                    if (updated % 10 == 0) AnnounceChanged("sizes");
                }
                if (updated > 0)
                {
                    SaveManifest();
                    AnnounceChanged("sizes");
                }
            }
            finally
            {
                Interlocked.Exchange(ref _sizeWalkRunning, 0);
            }
        });
    }

    // ------------------------------------------------------------------ folders and sources

    public void AddFolder(string path)
    {
        string full = AppSettingsNormalizer.NormalizePath(path);
        if (!Directory.Exists(full)) throw RpcException.NotFound("The folder does not exist: " + full);
        _state.UpdateSettings(settings =>
        {
            if (!settings.LibraryFolders.Contains(full, StringComparer.Ordinal)) settings.LibraryFolders.Add(full);
            RememberRecent(settings, full);
        });
    }

    public void RemoveFolder(string path)
    {
        _state.UpdateSettings(settings =>
            settings.LibraryFolders.RemoveAll(folder => string.Equals(folder, path, StringComparison.Ordinal)));
        PruneUncovered();
    }

    /// <summary>Remembers a single dump folder, package or image outside the library folders.</summary>
    public void AddSource(string path)
    {
        string full = AppSettingsNormalizer.NormalizePath(path);
        if (!Directory.Exists(full) && !File.Exists(full)) throw RpcException.NotFound("The path does not exist: " + full);
        _state.UpdateSettings(settings =>
        {
            if (!IsUnderLibrary(settings, full) && !settings.ManualSources.Contains(full, StringComparer.Ordinal))
                settings.ManualSources.Add(full);
            if (Directory.Exists(full)) RememberRecent(settings, full);
        });
    }

    public void RemoveSource(string path)
    {
        _state.UpdateSettings(settings =>
            settings.ManualSources.RemoveAll(source => string.Equals(source, path, StringComparison.Ordinal)));
        PruneUncovered();
    }

    public void ClearRecent() => _state.UpdateSettings(settings => settings.RecentFolders.Clear());

    private static void RememberRecent(AppSettings settings, string path)
    {
        settings.RecentFolders.RemoveAll(existing => string.Equals(existing, path, StringComparison.Ordinal));
        settings.RecentFolders.Insert(0, path);
        if (settings.RecentFolders.Count > 10) settings.RecentFolders.RemoveRange(10, settings.RecentFolders.Count - 10);
    }

    private void PruneUncovered()
    {
        int removed;
        lock (_gate)
        {
            var kept = _games.Where(game => IsCovered(game.RootPath)).ToList();
            removed = _games.Count - kept.Count;
            if (removed > 0) SetGames(kept);
        }
        if (removed > 0)
        {
            SaveManifest();
            AnnounceChanged("folders");
        }
    }

    public bool IsCovered(string path) =>
        IsUnderLibrary(_state.Settings, path) ||
        _state.Settings.ManualSources.Any(source => IsSameOrUnder(path, source));

    public static bool IsUnderLibrary(AppSettings settings, string path) =>
        settings.LibraryFolders.Any(folder => IsSameOrUnder(path, folder));

    public bool IsManagedPath(string path) => IsCovered(path);

    private static bool IsSameOrUnder(string path, string folder)
    {
        if (string.IsNullOrWhiteSpace(folder)) return false;
        string prefix = folder.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        return path.Equals(prefix, StringComparison.Ordinal) ||
               path.StartsWith(prefix + Path.DirectorySeparatorChar, StringComparison.Ordinal);
    }

    private static bool ExtensionMatchesKind(Ps5GameInfo game) => game.SourceKind switch
    {
        Ps5SourceKind.SonyPackage => game.RootPath.EndsWith(".pkg", StringComparison.OrdinalIgnoreCase),
        Ps5SourceKind.Ffpfsc => game.RootPath.EndsWith(".ffpfsc", StringComparison.OrdinalIgnoreCase),
        Ps5SourceKind.Ffpkg => game.RootPath.EndsWith(".ffpkg", StringComparison.OrdinalIgnoreCase),
        Ps5SourceKind.FilesystemImage => game.RootPath.EndsWith(".exfat", StringComparison.OrdinalIgnoreCase),
        _ => true
    };

    // ------------------------------------------------------------------ list maintenance

    public int Clear()
    {
        CancelScan();
        int count;
        lock (_gate)
        {
            count = _games.Count;
            SetGames([]);
        }
        SaveManifest();
        AnnounceChanged("clear");
        Logger.Info("Library list emptied.");
        return count;
    }

    public int RemoveMissing()
    {
        int removed;
        lock (_gate)
        {
            var kept = _games.Where(GameClassifier.SourceExists).ToList();
            removed = _games.Count - kept.Count;
            if (removed > 0) SetGames(kept);
        }
        if (removed > 0)
        {
            SaveManifest();
            AnnounceChanged("missing");
        }
        return removed;
    }

    /// <summary>Drops items whose sources were deleted (moved to the trash) by the UI.</summary>
    public int Forget(IEnumerable<string> ids)
    {
        var set = new HashSet<string>(ids, StringComparer.Ordinal);
        int removed;
        lock (_gate)
        {
            var kept = _games.Where(game => !set.Contains(game.RootPath)).ToList();
            removed = _games.Count - kept.Count;
            if (removed > 0) SetGames(kept);
        }
        _state.UpdateSettings(settings =>
        {
            settings.LibraryFolders.RemoveAll(set.Contains);
            settings.ManualSources.RemoveAll(set.Contains);
            settings.RecentFolders.RemoveAll(set.Contains);
        });
        if (removed > 0)
        {
            SaveManifest();
            AnnounceChanged("forget");
        }
        return removed;
    }

    /// <summary>Records that a source moved (rename or move) and keeps settings pointing at it.</summary>
    public void RewritePath(Ps5GameInfo game, string source, string target)
    {
        lock (_gate)
        {
            game.RootPath = target;
            game.ParamPath = ReplacePathPrefix(game.ParamPath, source, target);
            _family = new FamilyIndex(_games);
        }
        _state.UpdateSettings(settings =>
        {
            ReplaceSettingPath(settings.LibraryFolders, source, target);
            ReplaceSettingPath(settings.ManualSources, source, target);
            ReplaceSettingPath(settings.RecentFolders, source, target);
        });
    }

    private static void ReplaceSettingPath(List<string> paths, string source, string target)
    {
        for (int index = 0; index < paths.Count; index++)
            if (string.Equals(paths[index], source, StringComparison.Ordinal))
                paths[index] = target;
    }

    private static string ReplacePathPrefix(string value, string source, string target)
    {
        if (string.IsNullOrEmpty(value) || value.Length <= source.Length) return value;
        if (!value.StartsWith(source, StringComparison.Ordinal)) return value;
        char next = value[source.Length];
        return next is '\\' or '/' or ':' ? target + value[source.Length..] : value;
    }

    public void SaveManifest()
    {
        Ps5GameInfo[] games;
        lock (_gate) games = _games.ToArray();
        try
        {
            _state.Store.SaveManifest(games);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Logger.Error("The library manifest could not be saved: " + ex.Message);
        }
    }

    public void AnnounceChanged(string reason) => _state.Server.Emit("library.changed", new { reason });

    private void SetGames(List<Ps5GameInfo> games)
    {
        _games = games;
        _family = new FamilyIndex(games);
    }

    // ------------------------------------------------------------------ reports

    public async Task<object> FindDuplicatesAsync(CancellationToken token)
    {
        List<IGrouping<string, Ps5GameInfo>> groups = Games
            .GroupBy(DuplicateKey, StringComparer.OrdinalIgnoreCase)
            .Where(group => group.Count() > 1)
            .OrderByDescending(group => group.Count())
            .ToList();
        var fingerprints = new Dictionary<string, string>(StringComparer.Ordinal);
        await Task.Run(() =>
        {
            foreach (Ps5GameInfo game in groups.SelectMany(group => group))
            {
                token.ThrowIfCancellationRequested();
                fingerprints[game.RootPath] = Fingerprint(game);
            }
        }, token).ConfigureAwait(false);

        var result = groups.Select(group =>
        {
            bool identical = group.All(game => fingerprints.GetValueOrDefault(game.RootPath, string.Empty).Length > 0) &&
                             group.Select(game => fingerprints[game.RootPath]).Distinct(StringComparer.Ordinal).Count() == 1;
            Ps5GameInfo first = group.First();
            return new
            {
                key = group.Key,
                title = first.Title,
                titleId = first.TitleId,
                verdict = identical ? "identical" : "possible",
                items = group.Select(game => new
                {
                    id = game.RootPath,
                    format = game.SourceDescription,
                    sizeText = GameClassifier.FormatBytes(game.SourceSize),
                    version = game.DisplayVersion,
                    hash = fingerprints.GetValueOrDefault(game.RootPath, string.Empty) is { Length: > 0 } hash
                        ? hash[..Math.Min(16, hash.Length)]
                        : string.Empty
                }).ToList()
            };
        }).ToList();
        return new { groups = result, identical = result.Count(group => group.verdict == "identical") };
    }

    private static string DuplicateKey(Ps5GameInfo game)
    {
        if (!string.IsNullOrWhiteSpace(game.ContentId)) return "content:" + game.ContentId;
        if (!string.IsNullOrWhiteSpace(game.TitleId)) return $"title:{game.TitleId}:{game.SourceSize}";
        return $"file:{Path.GetFileName(game.RootPath)}:{game.SourceSize}";
    }

    private static string Fingerprint(Ps5GameInfo game)
    {
        try
        {
            byte[] param = GameFileSystem.ReadFileChunk(game, "sce_sys/param.json", 0, 4 * 1024 * 1024).Data;
            return param.Length == 0 ? string.Empty : Convert.ToHexString(SHA256.HashData(param));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException or
                                   InvalidDataException or NotSupportedException or InvalidOperationException)
        {
            return string.Empty;
        }
    }

    /// <summary>Titles that have updates in the library but no base game.</summary>
    public object PatchesMissingBase()
    {
        FamilyIndex family = Family;
        var groups = Games.Where(family.IsMissingBase)
            .GroupBy(game => game.TitleId, StringComparer.OrdinalIgnoreCase)
            .OrderBy(group => group.Key, StringComparer.OrdinalIgnoreCase)
            .Select(group => new
            {
                titleId = group.Key,
                title = group.First().Title,
                ids = group.Select(game => game.RootPath).ToList()
            }).ToList();
        return new { groups };
    }

    public int ExportCsv(IReadOnlyList<Ps5GameInfo> games, string path)
    {
        var builder = new StringBuilder();
        builder.AppendLine("Title,TitleId,ContentId,Category,Role,Region,Source,SizeBytes,Version,RequiredFirmware,DRM,FileName,Path");
        FamilyIndex family = Family;
        foreach (Ps5GameInfo game in games)
        {
            string[] fields =
            [
                game.Title, game.TitleId, game.ContentId, GameClassifier.CategoryOf(game), family.RoleOf(game),
                GameClassifier.RegionOf(game), game.SourceDescription, game.SourceSize.ToString(System.Globalization.CultureInfo.InvariantCulture),
                game.DisplayVersion, game.RequiredSystemSoftware, game.DrmType, GameClassifier.LibraryFileName(game), game.RootPath
            ];
            builder.AppendLine(string.Join(',', fields.Select(Csv)));
        }
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        File.WriteAllText(path, builder.ToString(), new UTF8Encoding(true));
        return games.Count;
    }

    public static string Csv(string? value)
    {
        value ??= string.Empty;
        return value.IndexOfAny([',', '"', '\n', '\r']) >= 0 ? "\"" + value.Replace("\"", "\"\"") + "\"" : value;
    }

    /// <summary>A short, human library summary for the home screen.</summary>
    public object Stats()
    {
        Ps5GameInfo[] games = Games.ToArray();
        FamilyIndex family = Family;
        return new
        {
            total = games.Length,
            totalBytes = games.Sum(game => Math.Max(0, game.SourceSize)),
            totalText = GameClassifier.FormatBytes(games.Sum(game => Math.Max(0, game.SourceSize))),
            games = games.Count(game => GameClassifier.CategoryOf(game) == "Game"),
            patches = games.Count(game => GameClassifier.CategoryOf(game) == "Patch"),
            dlc = games.Count(game => GameClassifier.CategoryOf(game) == "DLC"),
            apps = games.Count(game => GameClassifier.CategoryOf(game) == "App"),
            missing = games.Count(game => !GameClassifier.SourceExists(game)),
            superseded = games.Count(family.IsSuperseded),
            missingBase = games.Count(family.IsMissingBase),
            formats = games.GroupBy(GameClassifier.FormatOf).ToDictionary(group => group.Key, group => group.Count())
        };
    }
}
