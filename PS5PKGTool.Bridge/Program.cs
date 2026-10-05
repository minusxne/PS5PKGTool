using System.Reflection;
using System.Text;
using System.Text.Json;
using PS5PKGTool.Bridge;
using PS5PKGTool.Bridge.Details;
using PS5PKGTool.Bridge.Infrastructure;
using PS5PKGTool.Bridge.Library;
using PS5PKGTool.Bridge.Protocol;
using PS5PKGTool.Bridge.Tasks;
using PS5PKGTool.Bridge.Tools;
using PS5PKGTool.Core.Backends;
using PS5PKGTool.Core.Models;
using PS5PKGTool.Core.Services;

// stdout carries the protocol only: anything a library prints goes to stderr instead.
Stream protocolOut = Console.OpenStandardOutput();
Console.SetOut(new StreamWriter(Console.OpenStandardError(), new UTF8Encoding(false)) { AutoFlush = true });

if (args.Contains("--version"))
{
    Console.Error.WriteLine(Version());
    return 0;
}

ProtectDataDirectory();
var server = new RpcServer(protocolOut);
var state = new BridgeState(server);
var artwork = new ArtworkCache();
var library = new LibraryService(state, artwork);
var tasks = new TaskService(state, library.Find);
var details = new DetailsService(library);
var tools = new ToolsService(state, library, tasks);
var organizer = new Organizer(state, library, tasks);

Logger.Logged += entry => server.Emit("log", new { time = entry.Time, level = entry.Level.ToString(), message = entry.Message });

// ---------------------------------------------------------------------------------------- app

server.Register("app.hello", _ => new
{
    version = Version(),
    protocol = 1,
    os = System.Runtime.InteropServices.RuntimeInformation.OSDescription,
    runtime = System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription,
    dataDirectory = AppPaths.DataDirectory,
    cacheDirectory = AppPaths.CacheDirectory,
    logDirectory = Logger.LogDirectory,
    settingsWarning = state.StartupWarning,
    backends = BackendRegistry.All.Select(backend => new
    {
        id = backend.Id,
        name = backend.DisplayName,
        available = backend.Id != BackendRegistry.LppId || LppBackend.IsAvailable,
        reason = backend.Id == BackendRegistry.LppId ? LppBackend.UnavailableReason ?? string.Empty : string.Empty
    }),
    methods = server.Methods
});

server.Register("app.cacheInfo", _ => new
{
    artworkBytes = artwork.SizeOnDisk(),
    artworkText = GameClassifier.FormatBytes(artwork.SizeOnDisk()),
    directory = AppPaths.CacheDirectory
});

server.Register("app.clearCaches", _ =>
{
    artwork.Clear();
    details.Invalidate();
    Operations.TryDeleteDirectory(AppPaths.PreviewDirectory);
    library.AnnounceChanged("caches");
    return new { ok = true };
});

server.Register("log.recent", request =>
{
    int count = Math.Clamp(request.Int("count", 400), 1, 5000);
    try
    {
        if (!File.Exists(Logger.LogPath)) return new { lines = Array.Empty<string>() };
        using var stream = new FileStream(Logger.LogPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        using var reader = new StreamReader(stream);
        var lines = new LinkedList<string>();
        while (reader.ReadLine() is { } line)
        {
            lines.AddLast(line);
            if (lines.Count > count) lines.RemoveFirst();
        }
        return new { lines = lines.ToArray() };
    }
    catch (IOException ex)
    {
        return new { lines = new[] { "The log could not be read: " + ex.Message } };
    }
});

// ---------------------------------------------------------------------------------------- settings

server.Register("settings.get", _ => new
{
    settings = state.Settings,
    renamePresets = Ps5RenameFormats.Presets.Select(preset => new { label = preset.Label, format = preset.Format }),
    renameTokens = Ps5RenameFormatter.TokenNames,
    groupKeys = AppSettingsNormalizer.GroupKeys
});

server.Register("settings.set", request =>
{
    JsonElement values = request.Element("values") ?? throw RpcException.BadRequest("Missing 'values'.");
    string before = state.Settings.DebugPasscode;
    bool foldersChanged = false;
    state.UpdateSettings(settings =>
    {
        string snapshot = JsonSerializer.Serialize(settings.LibraryFolders) + JsonSerializer.Serialize(settings.RecursiveScan);
        ApplySettingValues(settings, values);
        foldersChanged = snapshot != JsonSerializer.Serialize(settings.LibraryFolders) + JsonSerializer.Serialize(settings.RecursiveScan);
    });
    if (values.TryGetProperty("debugPasscode", out JsonElement passcode) && passcode.GetString() is { Length: > 0 } text &&
        !AppSettingsNormalizer.IsValidPasscode(text))
    {
        state.UpdateSettings(settings => settings.DebugPasscode = before);
        throw RpcException.BadRequest("The passcode must be blank or exactly 32 printable characters.");
    }
    return new { settings = state.Settings, rescan = foldersChanged };
});

server.Register("settings.renameExample", request =>
    Organizer.Example(request.Str("format"), request.Str("id") is { Length: > 0 } id ? library.Find(id) : library.Games.FirstOrDefault()));

server.Register("settings.export", request =>
{
    string path = request.RequireStr("path");
    AppSettings copy = JsonSerializer.Deserialize<AppSettings>(JsonSerializer.Serialize(state.Settings))!;
    if (!request.Bool("includePasscode")) copy.DebugPasscode = string.Empty;
    File.WriteAllText(path, JsonSerializer.Serialize(copy, new JsonSerializerOptions { WriteIndented = true }));
    return new { path, includedPasscode = request.Bool("includePasscode") };
});

server.Register("settings.importPreview", request =>
{
    AppSettings candidate = ReadSettingsFile(request.RequireStr("path"));
    return new { changes = DescribeChanges(state.Settings, candidate) };
});

server.Register("settings.importApply", request =>
{
    AppSettings candidate = ReadSettingsFile(request.RequireStr("path"));
    state.ReplaceSettings(candidate);
    return new { settings = state.Settings };
});

server.Register("settings.reset", _ =>
{
    AppSettings current = state.Settings;
    state.ReplaceSettings(new AppSettings
    {
        LibraryFolders = [.. current.LibraryFolders],
        ManualSources = [.. current.ManualSources],
        RecentFolders = [.. current.RecentFolders],
        SavedViews = [.. current.SavedViews],
        LibraryColumnOrder = [.. current.LibraryColumnOrder],
        LibraryHiddenColumns = [.. current.LibraryHiddenColumns],
        LibrarySortKeys = [.. current.LibrarySortKeys],
        WindowWidth = current.WindowWidth,
        WindowHeight = current.WindowHeight,
        WindowMaximized = current.WindowMaximized
    });
    return new { settings = state.Settings };
});

server.Register("views.save", request =>
{
    SavedLibraryView view = request.Object<SavedLibraryView>("view") ?? throw RpcException.BadRequest("Missing 'view'.");
    if (string.IsNullOrWhiteSpace(view.Name)) throw RpcException.BadRequest("A saved view needs a name.");
    state.UpdateSettings(settings =>
    {
        settings.SavedViews.RemoveAll(existing => existing.Name.Equals(view.Name.Trim(), StringComparison.OrdinalIgnoreCase));
        settings.SavedViews.Add(view);
    });
    return new { views = state.Settings.SavedViews };
});

server.Register("views.delete", request =>
{
    string name = request.RequireStr("name");
    state.UpdateSettings(settings => settings.SavedViews.RemoveAll(view => view.Name.Equals(name, StringComparison.OrdinalIgnoreCase)));
    return new { views = state.Settings.SavedViews };
});

// ---------------------------------------------------------------------------------------- library

server.Register("library.list", _ => new { items = library.Rows(), scanning = library.IsScanning, roots = library.ScanRoots() });

server.Register("library.view", request =>
{
    var view = new LibraryViewRequest
    {
        Query = request.Str("query"),
        Categories = request.StrList("categories"),
        Regions = request.StrList("regions"),
        Formats = request.StrList("formats"),
        SortKeys = request.StrList("sortKeys"),
        GroupBy = request.Str("groupBy")
    };
    return library.View(view);
});

server.Register("library.stats", _ => library.Stats());

server.Register("library.queryHelp", _ => new
{
    fields = LibraryQuery.FieldHelp.Select(item => new { field = item.Field, example = item.Example, help = item.Help }),
    categories = GameClassifier.Categories,
    regions = GameClassifier.Regions,
    formats = GameClassifier.Formats,
    sortColumns = LibraryView.SortColumns
});

server.Register("library.scan", async request =>
    await library.ScanAsync(request.StrList("roots") is { Count: > 0 } roots ? roots : null, request.Bool("merge"), request.Token)
        .ConfigureAwait(false));

server.Register("library.cancelScan", _ =>
{
    library.CancelScan();
    return new { ok = true };
});

server.Register("library.addFolder", async request =>
{
    string path = request.RequireStr("path");
    library.AddFolder(path);
    if (!request.Bool("scan", true)) return new { added = 0 };
    return await library.ScanAsync([AppSettingsNormalizer.NormalizePath(path)], merge: true, request.Token).ConfigureAwait(false);
});

server.Register("library.removeFolder", request =>
{
    library.RemoveFolder(request.RequireStr("path"));
    return new { ok = true };
});

server.Register("library.addSource", async request =>
{
    string path = AppSettingsNormalizer.NormalizePath(request.RequireStr("path"));
    library.AddSource(path);
    return await library.ScanAsync([path], merge: true, request.Token).ConfigureAwait(false);
});

server.Register("library.removeSource", request =>
{
    library.RemoveSource(request.RequireStr("path"));
    return new { ok = true };
});

server.Register("library.clearRecent", _ =>
{
    library.ClearRecent();
    return new { ok = true };
});

server.Register("library.clear", _ => new { removed = library.Clear() });
server.Register("library.removeMissing", _ => new { removed = library.RemoveMissing() });
server.Register("library.forget", request => new { removed = library.Forget(request.StrList("ids")) });
server.Register("library.saveManifest", _ =>
{
    library.SaveManifest();
    return new { count = library.Games.Count };
});

server.Register("library.thumbnails", async request =>
{
    List<string> ids = request.StrList("ids");
    bool full = request.Bool("full");
    var result = new Dictionary<string, object>(StringComparer.Ordinal);
    await Parallel.ForEachAsync(ids.Distinct(StringComparer.Ordinal), new ParallelOptions
    {
        MaxDegreeOfParallelism = 4,
        CancellationToken = request.Token
    }, async (id, token) =>
    {
        if (library.Find(id) is not { } game) return;
        ArtworkPaths paths = await artwork.EnsureAsync(game, full, token).ConfigureAwait(false);
        lock (result) result[id] = new { icon = paths.Icon, background = paths.Background, pic0 = paths.Pic0, pic1 = paths.Pic1 };
    }).ConfigureAwait(false);
    return new { items = result };
});

server.Register("library.duplicates", async request => await library.FindDuplicatesAsync(request.Token).ConfigureAwait(false));
server.Register("library.missingBase", _ => library.PatchesMissingBase());

server.Register("library.exportCsv", request =>
{
    List<string> ids = request.StrList("ids");
    IReadOnlyList<Ps5GameInfo> games = ids.Count > 0 ? library.RequireMany(ids) : library.Games;
    if (games.Count == 0) throw RpcException.BadRequest("There is nothing to export.");
    return new { count = library.ExportCsv(games, request.RequireStr("path")) };
});

server.Register("library.saveArtwork", async request =>
{
    string folder = request.RequireStr("folder");
    Directory.CreateDirectory(folder);
    int saved = 0;
    foreach (Ps5GameInfo game in library.RequireMany(request.StrList("ids")))
    {
        ArtworkPaths paths = await artwork.EnsureAsync(game, full: true, request.Token).ConfigureAwait(false);
        string baseName = Ps5RenameFormatter.Sanitize(string.IsNullOrWhiteSpace(game.Title) ? GameClassifier.LibraryFileName(game) : game.Title);
        if (game.TitleId.Length > 0) baseName = $"{game.TitleId} - {baseName}";
        foreach ((string file, string name) in new[] { (paths.Icon, "icon0"), (paths.Pic0, "pic0"), (paths.Pic1, "pic1"), (paths.Pic2, "pic2") })
        {
            if (file.Length == 0) continue;
            string target = UniqueFile(Path.Combine(folder, $"{baseName}-{name}.png"));
            File.Copy(file, target);
            saved++;
        }
    }
    return new { saved, folder };
});

server.Register("library.renamePlan", request =>
{
    List<Ps5GameInfo> games = request.Bool("all") ? library.Games.ToList() : library.RequireMany(request.StrList("ids"));
    string format = Organizer.FormatOrDefault(request.Str("format") is { Length: > 0 } custom ? custom : state.Settings.RenameFormat);
    return new { format, items = organizer.PlanRename(games, format, request.Bool("installOrder")) };
});

server.Register("library.renameApply", request =>
{
    List<Ps5GameInfo> games = request.Bool("all") ? library.Games.ToList() : library.RequireMany(request.StrList("ids"));
    string format = Organizer.FormatOrDefault(request.Str("format") is { Length: > 0 } custom ? custom : state.Settings.RenameFormat);
    return organizer.ApplyRename(games, format, request.Bool("installOrder"));
});

server.Register("library.movePlan", request =>
{
    string mode = request.Str("mode", "title");
    string destination = request.RequireStr("destination");
    List<OrganizePlanItem> items = organizer.PlanMove(library.RequireMany(request.StrList("ids")), destination, mode);
    return new
    {
        items,
        modeLabel = Organizer.MoveModeLabel(mode),
        destinationCovered = library.IsCovered(destination),
        confirm = state.Settings.ConfirmMove
    };
});

server.Register("library.moveEnqueue", request =>
    organizer.EnqueueMove(library.RequireMany(request.StrList("ids")), request.RequireStr("destination"), request.Str("mode", "title"),
        request.Bool("addToLibrary")));

server.Register("library.busy", request => new
{
    busy = request.StrList("ids").Where(tasks.IsPathBusy).ToList(),
    managed = request.StrList("ids").All(library.IsManagedPath)
});

// ---------------------------------------------------------------------------------------- details

server.Register("details.get", async request =>
    await details.GetAsync(library.Require(request.RequireStr("id")), request.Token).ConfigureAwait(false));

server.Register("details.container", async request =>
    await details.ContainerAsync(library.Require(request.RequireStr("id")), request.Token).ConfigureAwait(false));

server.Register("details.ebootHash", async request =>
    await DetailsService.EbootHashAsync(library.Require(request.RequireStr("id")), request.Token).ConfigureAwait(false));

server.Register("files.list", async request =>
    await details.FilesAsync(library.Require(request.RequireStr("id")), request.Token).ConfigureAwait(false));

server.Register("files.preview", async request =>
    await details.PreviewAsync(library.Require(request.RequireStr("id")), request.RequireStr("path"), state.Settings.MaxPreviewMb,
        request.Token).ConfigureAwait(false));

server.Register("files.hex", async request =>
    await DetailsService.HexPageAsync(library.Require(request.RequireStr("id")), request.RequireStr("path"), request.Long("offset"),
        request.Int("length", state.Settings.HexPageKb * 1024), request.Token).ConfigureAwait(false));

server.Register("files.materialize", async request =>
{
    Ps5GameInfo game = library.Require(request.RequireStr("id"));
    string file = await details.ExtractToPreviewAsync(game, request.RequireStr("path"), request.Long("size", -1), request.Token)
        .ConfigureAwait(false);
    return new { file };
});

server.Register("files.extract", request =>
    tools.ExtractFiles(library.Require(request.RequireStr("id")), request.StrList("paths"), request.RequireStr("destination")));

// ---------------------------------------------------------------------------------------- tools

server.Register("tools.inspect", request => tools.Inspect(AppSettingsNormalizer.NormalizePath(request.RequireStr("source"))));
server.Register("tools.buildOptions", _ => tools.BuildOptions());
server.Register("tools.diskCheck", request =>
    tools.DiskCheck(request.RequireStr("source"), request.Str("output"), request.Str("temp"), request.Str("target")));
server.Register("tools.enqueue", request => tools.Enqueue(request));
server.Register("editor.open", request => tools.EditorEntries(request.RequireStr("source")));
server.Register("editor.apply", request =>
    tools.EditorApply(request.RequireStr("source"),
        request.Element("operations")?.Deserialize<List<Operations.EditOperation>>(Json.Options) ?? []));

// ---------------------------------------------------------------------------------------- tasks

server.Register("tasks.list", _ => new { tasks = tasks.Snapshot(), summary = tasks.Summary() });
server.Register("tasks.cancel", request => new { ok = tasks.Cancel(request.RequireStr("id")) });
server.Register("tasks.cancelAll", _ => new { cancelled = tasks.CancelAll() });
server.Register("tasks.retry", request => new { ok = tasks.Retry(request.RequireStr("id")) });
server.Register("tasks.remove", request => new { ok = tasks.Remove(request.RequireStr("id")) });
server.Register("tasks.clearCompleted", _ => new { removed = tasks.ClearCompleted() });
server.Register("tasks.startNext", _ =>
{
    tasks.StartNext();
    return new { ok = true };
});
server.Register("tasks.setAutoStart", request =>
{
    tasks.AutoStart = request.Bool("value", true);
    return new { autoStart = tasks.AutoStart };
});
server.Register("tasks.report", request => new { report = tasks.Report(request.RequireStr("id")) });

// ---------------------------------------------------------------------------------------- run

Logger.Info($"PS5 PKG Tool bridge {Version()} starting ({System.Runtime.InteropServices.RuntimeInformation.OSDescription}).");
library.LoadManifest();
tasks.Restore();
server.Emit("ready", new { version = Version() });

Task reader = server.RunAsync(Console.OpenStandardInput());
await server.Shutdown.ConfigureAwait(false);
Logger.Info("Bridge shutting down.");
await tasks.DisposeAsync().ConfigureAwait(false);
library.SaveManifest();
return 0;

// ---------------------------------------------------------------------------------------- helpers

static string Version() =>
    typeof(RpcServer).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion.Split('+')[0]
    ?? "0.0.0";

static void ProtectDataDirectory()
{
    // tasks.json can hold a custom debug passcode so a queued build can be retried after a restart;
    // keep the data directory private to the user.
    if (OperatingSystem.IsWindows()) return;
    try
    {
        File.SetUnixFileMode(AppPaths.DataDirectory, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
    }
    catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
    {
    }
}

static string UniqueFile(string path)
{
    if (!File.Exists(path)) return path;
    string directory = Path.GetDirectoryName(path) ?? string.Empty;
    string name = Path.GetFileNameWithoutExtension(path);
    string extension = Path.GetExtension(path);
    for (int index = 2; index < 10000; index++)
    {
        string candidate = Path.Combine(directory, $"{name} ({index}){extension}");
        if (!File.Exists(candidate)) return candidate;
    }
    return path;
}

static AppSettings ReadSettingsFile(string path)
{
    try
    {
        AppSettings settings = JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(path),
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? throw new InvalidDataException("The file did not contain settings.");
        return AppSettingsNormalizer.Normalize(settings);
    }
    catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException or InvalidDataException)
    {
        throw RpcException.BadRequest("The settings file could not be read: " + ex.Message);
    }
}

static List<string> DescribeChanges(AppSettings before, AppSettings after)
{
    var changes = new List<string>();
    void Change(string label, object? left, object? right)
    {
        string a = left?.ToString() ?? string.Empty;
        string b = right?.ToString() ?? string.Empty;
        if (!string.Equals(a, b, StringComparison.Ordinal))
            changes.Add($"{label}: {(a.Length == 0 ? "(none)" : a)} → {(b.Length == 0 ? "(none)" : b)}");
    }
    void Paths(string label, List<string> left, List<string> right)
    {
        var removed = left.Except(right, StringComparer.Ordinal).ToList();
        var added = right.Except(left, StringComparer.Ordinal).ToList();
        if (removed.Count > 0) changes.Add($"{label} removed: {string.Join(", ", removed.Take(5))}");
        if (added.Count > 0) changes.Add($"{label} added: {string.Join(", ", added.Take(5))}");
    }
    static string Mask(string value) => string.IsNullOrEmpty(value) ? string.Empty : new string('•', value.Length);
    Paths("Library folders", before.LibraryFolders, after.LibraryFolders);
    Paths("Single sources", before.ManualSources, after.ManualSources);
    Change("Scan subfolders", before.RecursiveScan, after.RecursiveScan);
    Change("Refresh on startup", before.RefreshOnStartup, after.RefreshOnStartup);
    Change("View", before.ViewMode, after.ViewMode);
    Change("List row height", before.GridRowHeight, after.GridRowHeight);
    Change("Background art", before.BackgroundArt, after.BackgroundArt);
    Change("Reduce motion", before.ReduceMotion, after.ReduceMotion);
    Change("Default grouping", before.DefaultGroupBy, after.DefaultGroupBy);
    Change("Rename format", before.RenameFormat, after.RenameFormat);
    Change("Max preview (MiB)", before.MaxPreviewMb, after.MaxPreviewMb);
    Change("Hex page (KiB)", before.HexPageKb, after.HexPageKb);
    Change("Default output folder", before.OutputDirectory, after.OutputDirectory);
    Change("Default builder", before.BuildBackend, after.BuildBackend);
    Change("Debug passcode", Mask(before.DebugPasscode), Mask(after.DebugPasscode));
    Change("Open output after success", before.OpenOutputAfterTask, after.OpenOutputAfterTask);
    Change("Confirm moves", before.ConfirmMove, after.ConfirmMove);
    Change("Confirm trash", before.ConfirmDelete, after.ConfirmDelete);
    Change("Delete permanently", before.PermanentDelete, after.PermanentDelete);
    return changes;
}

/// <summary>Applies a partial settings object sent by the UI (camelCase property names).</summary>
static void ApplySettingValues(AppSettings settings, JsonElement values)
{
    if (values.ValueKind != JsonValueKind.Object) return;
    foreach (JsonProperty property in values.EnumerateObject())
    {
        PropertyInfo? target = typeof(AppSettings).GetProperties()
            .FirstOrDefault(candidate => candidate.Name.Equals(property.Name, StringComparison.OrdinalIgnoreCase) && candidate.CanWrite);
        if (target is null) continue;
        try
        {
            object? value = property.Value.Deserialize(target.PropertyType, Json.Options);
            if (value is not null || !target.PropertyType.IsValueType) target.SetValue(settings, value);
        }
        catch (JsonException)
        {
            throw RpcException.BadRequest($"Invalid value for '{property.Name}'.");
        }
    }
}
