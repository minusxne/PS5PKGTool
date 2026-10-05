using System.Text.Json;
using PS5PKGTool.Bridge.Infrastructure;
using PS5PKGTool.Bridge.Library;
using PS5PKGTool.Bridge.Protocol;
using PS5PKGTool.Bridge.Tasks;
using PS5PKGTool.Core.Backends;
using PS5PKGTool.Core.Builders;
using PS5PKGTool.Core.Models;
using PS5PKGTool.Core.Parsers;
using PS5PKGTool.Core.Services;
using PS5PKGTool.Core.Tasks;
using PS5PKGTool.Ffpfsc;
using UFS2Tool;

namespace PS5PKGTool.Bridge.Tools;

/// <summary>
/// The Tools workspace: inspects a source, tells the UI which actions and targets make sense (and
/// why others do not), suggests outputs and safe defaults, checks free space, and queues the job.
/// </summary>
public sealed class ToolsService(BridgeState state, LibraryService library, TaskService tasks)
{
    public static readonly (int Value, string Name)[] KrakenLevels =
    [
        (-4, "HyperFast4"), (-3, "HyperFast3"), (-2, "HyperFast2"), (-1, "HyperFast1"),
        (0, "None"), (1, "SuperFast"), (2, "VeryFast"), (3, "Fast"), (4, "Normal"),
        (5, "Optimal1"), (6, "Optimal2"), (7, "Optimal3"), (8, "Optimal4"), (9, "Optimal5")
    ];

    private sealed record SourceInfo(string Path, bool IsDirectory, Ps5ImageFormat Format, bool IsPackage, SonyPkgKind? PackageKind)
    {
        public string Kind => IsDirectory ? "dump"
            : IsPackage ? "package"
            : Format switch
            {
                Ps5ImageFormat.Exfat => "exfat",
                Ps5ImageFormat.Ufs2 => "ffpkg",
                Ps5ImageFormat.Pfs => "ffpfsc",
                _ => "unknown"
            };

        public string Label => IsDirectory ? "Dump folder"
            : IsPackage ? PackageKind switch
            {
                SonyPkgKind.FinalizedDebug => "Debug package (FPKG)",
                SonyPkgKind.FinalizedPatch => "Patch package (LIH)",
                SonyPkgKind.FinalizedRetail => "Retail package",
                SonyPkgKind.MetadataContainer => "CNT metadata container",
                _ => "Package"
            }
            : Format switch
            {
                Ps5ImageFormat.Exfat => "exFAT image",
                Ps5ImageFormat.Ufs2 => "FFPKG image",
                Ps5ImageFormat.Pfs => "FFPFSC image",
                _ => "Unknown file"
            };

        public string RouteLabel => IsDirectory ? "dump" : IsPackage ? "FPKG" : TaskCatalog.FormatLabel(Format);

        public bool IsDebugPackage => IsPackage && PackageKind == SonyPkgKind.FinalizedDebug;
        public bool IsImage => !IsDirectory && !IsPackage && Format is Ps5ImageFormat.Exfat or Ps5ImageFormat.Ufs2 or Ps5ImageFormat.Pfs;
    }

    private static SourceInfo Probe(string path)
    {
        if (Directory.Exists(path)) return new SourceInfo(path, true, Ps5ImageFormat.Unknown, false, null);
        if (!File.Exists(path)) throw RpcException.NotFound("The source does not exist: " + path);
        bool isPackage = Path.GetExtension(path).Equals(".pkg", StringComparison.OrdinalIgnoreCase);
        SonyPkgKind? kind = null;
        if (isPackage)
        {
            try { kind = new SonyPkgReader().Read(path).Kind; }
            catch (Exception ex) when (ex is IOException or InvalidDataException or UnauthorizedAccessException or NotSupportedException) { }
        }
        Ps5ImageFormat format = isPackage ? Ps5ImageFormat.Unknown : Ps5ImageFormatProbe.Detect(path);
        return new SourceInfo(path, false, format, isPackage, kind);
    }

    public object Inspect(string path)
    {
        SourceInfo source = Probe(path);
        Ps5GameInfo? game = library.Find(path);
        Operations.ParamFields param = source.IsDirectory || source.IsImage
            ? Operations.ReadParamFields(path, source.Format)
            : default;
        string contentId = param.ContentId.Length > 0 ? param.ContentId : game?.ContentId ?? string.Empty;

        var actions = new List<object>();
        void Action(string id, string label, string description, bool enabled, string reason = "") =>
            actions.Add(new { id, label, description, enabled, reason });

        string packageReason = source.PackageKind switch
        {
            SonyPkgKind.FinalizedPatch => "Patch packages cannot be decoded. Use a finalized debug (FPKG) package.",
            SonyPkgKind.FinalizedRetail => "Retail packages are encrypted with keys this tool does not have. Use a debug (FPKG) package.",
            _ => "Only debug (FPKG) packages can be converted, extracted or verified."
        };
        bool canConvert = source.IsDirectory || source.IsDebugPackage || source.IsImage;
        Action("convert", "Create / Convert", "Turn this source into an exFAT, FFPKG or FFPFSC image, or build a debug package.",
            canConvert, source.IsPackage && !source.IsDebugPackage ? packageReason : canConvert ? "" : "Unknown source format.");
        Action("extract", "Extract", "Copy every file out to a folder (an unpacked dump).",
            source.IsDebugPackage || source.IsImage,
            source.IsDirectory ? "A dump folder is already extracted." : source.IsPackage ? packageReason : "");
        Action("verify", "Verify", "Read the whole source back and check its structure and data.",
            source.IsDebugPackage || source.IsImage,
            source.IsDirectory ? "Dump folders have nothing to verify." : source.IsPackage ? packageReason : "");
        Action("edit", "Edit files", "Replace, add or delete files inside the image without rebuilding it by hand.",
            source.Format is Ps5ImageFormat.Exfat or Ps5ImageFormat.Ufs2, "Only exFAT and FFPKG images can be edited.");
        Action("repair", "Repair", "Restore a damaged exFAT image from its backup boot region and rebuild its metadata.",
            source.Format == Ps5ImageFormat.Exfat, "Only exFAT images can be repaired.");
        Action("ampr", "Refresh AMPR", "Create or refresh the ampr_emu.index at the root of an exFAT image.",
            source.Format == Ps5ImageFormat.Exfat, "Only exFAT images have an AMPR index.");
        Action("rebuild", "Rebuild", "Re-create all FFPKG metadata from the readable files, then swap it in after verifying.",
            source.Format == Ps5ImageFormat.Ufs2, "Only FFPKG images can be rebuilt.");

        var targets = new List<object>();
        void Target(string id, string label, string extension, string description) =>
            targets.Add(new { id, label, extension, description, output = SuggestOutput(path, extension) });
        bool Supports(Ps5ImageConversionTarget target) =>
            source.IsDirectory || source.IsDebugPackage || Ps5ImageConversionService.IsSupported(source.Format, target);
        if (canConvert)
        {
            if (Supports(Ps5ImageConversionTarget.Exfat))
                Target("exfat", "exFAT image", ".exfat", "A plain exFAT filesystem image. Widely supported and editable.");
            if (Supports(Ps5ImageConversionTarget.Ffpkg))
                Target("ffpkg", "FFPKG image", ".ffpkg", "A UFS2 filesystem image. Editable and space-efficient.");
            if (Supports(Ps5ImageConversionTarget.Ffpfsc))
                Target("ffpfsc", "FFPFSC image", ".ffpfsc", "A compressed PFSC image. Smallest on disk, read-only.");
            if (!source.IsPackage)
                Target("pkg", "Debug package (FPKG)", ".pkg", "An installable debug package built from this source.");
        }

        long estimate = EstimateBytes(path);
        return new
        {
            source = path,
            name = Path.GetFileName(path.TrimEnd('/')),
            kind = source.Kind,
            kindLabel = source.Label,
            explanation = Explanation(source),
            gameId = game?.RootPath ?? string.Empty,
            title = game?.Title ?? param.TitleName,
            titleId = game?.TitleId ?? param.TitleId,
            contentId,
            version = game?.DisplayVersion ?? param.ContentVersion,
            sizeBytes = estimate,
            sizeText = GameClassifier.FormatBytes(estimate),
            actions,
            targets,
            extractOutput = SuggestOutput(path, "-files"),
            canBuildPackage = contentId.Length > 0,
            buildBlockedReason = contentId.Length > 0 ? string.Empty : "The source has no content ID in sce_sys/param.json, so a package cannot be built from it.",
            passcode = state.DefaultPasscode
        };
    }

    private static string Explanation(SourceInfo source) =>
        source.IsDirectory ? "An unpacked game folder. It can be packed into any image format or built into a debug package."
        : source.IsDebugPackage ? "A finalized debug package. Its files can be extracted, verified, or converted into an image."
        : source.IsPackage ? "This package cannot be decoded here: only debug (FPKG) packages built with a known passcode are readable."
        : source.Format switch
        {
            Ps5ImageFormat.Exfat => "An exFAT filesystem image. It can be converted, extracted, verified, edited, repaired and re-indexed.",
            Ps5ImageFormat.Ufs2 => "An FFPKG (UFS2) image. It can be converted, extracted, verified, edited and rebuilt.",
            Ps5ImageFormat.Pfs => "A compressed FFPFSC image. It can be converted, extracted and verified.",
            _ => "This file is not a recognised PS5 image or package."
        };

    private string SuggestOutput(string source, string suffix)
    {
        bool directory = Directory.Exists(source);
        string trimmed = source.TrimEnd('/');
        string name = directory ? Path.GetFileName(trimmed) : Path.GetFileNameWithoutExtension(trimmed);
        string? parent = !string.IsNullOrWhiteSpace(state.Settings.OutputDirectory) && Directory.Exists(state.Settings.OutputDirectory)
            ? state.Settings.OutputDirectory
            : Path.GetDirectoryName(trimmed);
        return Path.Combine(parent ?? trimmed, name + suffix);
    }

    private static long EstimateBytes(string source)
    {
        try
        {
            if (Directory.Exists(source))
                return Directory.EnumerateFiles(source, "*", new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true })
                    .Sum(file => new FileInfo(file).Length);
            if (File.Exists(source)) return new FileInfo(source).Length;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
        }
        return 0;
    }

    /// <summary>Builder choices, option tables and the per-builder defaults for the package form.</summary>
    public object BuildOptions()
    {
        bool lppAvailable = LppBackend.IsAvailable;
        string preferred = BackendRegistry.IsKnown(state.Settings.BuildBackend) ? state.Settings.BuildBackend : BackendRegistry.DefaultId;
        if (preferred == BackendRegistry.LppId && !lppAvailable) preferred = BackendRegistry.PptId;
        return new
        {
            defaultBackend = preferred,
            builders = BackendRegistry.All.Select(backend => new
            {
                id = backend.Id,
                name = backend.DisplayName,
                available = backend.Id != BackendRegistry.LppId || lppAvailable,
                reason = backend.Id == BackendRegistry.LppId && !lppAvailable ? LppBackend.UnavailableReason ?? "Not available." : string.Empty,
                note = backend.Id == BackendRegistry.LppId
                    ? "The default third-party builder. Builds from folders (images are extracted first). Ignores fake-sign and right.sprx options."
                    : "This app's own builder. Reads images directly, without extracting them first. Still experimental.",
                defaults = backend.Id == BackendRegistry.LppId
                    ? new { compression = "Auto", krakenLevel = 7, krakenThreads = 0, playGo = 64, deterministic = true, fakeSign = true, rightSprx = true }
                    : new { compression = "Auto", krakenLevel = 7, krakenThreads = 0, playGo = 1, deterministic = false, fakeSign = true, rightSprx = true }
            }).ToList(),
            sdkVersions = Ps5SdkVersions.Releases.Select((release, index) => new { index, version = release.Version, major = release.Major }).ToList(),
            krakenLevels = KrakenLevels.Select(level => new { value = level.Value, name = $"{level.Value} · {level.Name}" }).ToList(),
            drmModes = new[]
            {
                new { id = "upgradable", label = "Upgradable" },
                new { id = "free", label = "Free" },
                new { id = "standard", label = "Standard" },
                new { id = "", label = "Keep source value" }
            },
            compressionModes = new[]
            {
                new { id = "Auto", label = "Auto (Kraken where it helps)" },
                new { id = "Kraken", label = "Kraken (always)" },
                new { id = "Stored", label = "Uncompressed" }
            },
            tempDirectory = Path.GetTempPath().TrimEnd('/'),
            passcode = state.DefaultPasscode
        };
    }

    /// <summary>The free-space preflight for an output (and, for packages, the workspace).</summary>
    public object DiskCheck(string source, string output, string? temp, string target)
    {
        long raw = EstimateBytes(source);
        if (output.Length == 0) return new { status = "Ok", message = string.Empty };
        Ps5DiskSpaceCheck check;
        if (target == "pkg")
        {
            check = Ps5DiskSpace.Check(raw, output, string.IsNullOrWhiteSpace(temp) ? null : temp);
        }
        else
        {
            string directory = Path.GetDirectoryName(Path.GetFullPath(output)) ?? output;
            long? free = Ps5MountInfo.AvailableFreeSpace(Directory.Exists(directory) ? directory : Path.GetPathRoot(directory) ?? "/");
            if (free is null) return new { status = "Ok", message = string.Empty };
            long need = (long)(raw * 1.05) + 64L * 1024 * 1024;
            Ps5DiskSpaceStatus status = free < need ? Ps5DiskSpaceStatus.Insufficient
                : free < need * 1.15 ? Ps5DiskSpaceStatus.NearLimit
                : Ps5DiskSpaceStatus.Ok;
            check = new Ps5DiskSpaceCheck(status,
                $"needs up to ~{GameClassifier.FormatBytes(need)} on {Ps5MountInfo.VolumeOf(directory)}, {GameClassifier.FormatBytes(free.Value)} free");
        }
        return new
        {
            status = check.Status.ToString(),
            message = check.Message,
            free = Ps5MountInfo.AvailableFreeSpace(Path.GetDirectoryName(Path.GetFullPath(output)) ?? "/") is { } bytes
                ? GameClassifier.FormatBytes(bytes)
                : string.Empty,
            volume = Ps5MountInfo.VolumeOf(Path.GetDirectoryName(Path.GetFullPath(output)) ?? "/")
        };
    }

    /// <summary>Validates the request and queues the job.</summary>
    public object Enqueue(RpcRequest request)
    {
        string path = request.RequireStr("source");
        string action = request.RequireStr("action");
        SourceInfo source = Probe(path);
        string output = request.Str("output").Trim();
        bool overwrite = request.Bool("overwrite");
        JsonElement options = request.Element("options") ?? default;
        string passcode = OptionString(options, "passcode") is { Length: > 0 } custom ? custom : state.DefaultPasscode;
        if (passcode.Length != 32) throw RpcException.BadRequest("The passcode must be exactly 32 characters.");
        if (tasks.IsPathBusy(path) && action is "repair" or "ampr" or "rebuild")
            throw RpcException.BadRequest("Another queued or running task is using this image. Wait for it to finish first.");

        var payload = new TaskPayload().With("source", path).With("sourceLabel", source.RouteLabel);
        string type;
        switch (action)
        {
            case "convert":
            {
                string target = request.RequireStr("target");
                if (output.Length == 0) throw RpcException.BadRequest("Choose an output file.");
                if (string.Equals(Path.GetFullPath(output), Path.GetFullPath(path), StringComparison.Ordinal))
                    throw RpcException.BadRequest("The output must be different from the source.");
                if (!overwrite && File.Exists(output))
                    throw RpcException.BadRequest("The output file already exists. Turn on Overwrite or choose another name.");
                if (target == "pkg") return EnqueueBuild(source, output, overwrite, passcode, options, payload);
                Ps5ImageConversionTarget conversion = target switch
                {
                    "exfat" => Ps5ImageConversionTarget.Exfat,
                    "ffpkg" => Ps5ImageConversionTarget.Ffpkg,
                    "ffpfsc" => Ps5ImageConversionTarget.Ffpfsc,
                    _ => throw RpcException.BadRequest("Unknown target: " + target)
                };
                type = PackageTaskTypes.ImageConvert;
                payload.With("output", output).With("target", conversion.ToString()).With("overwrite", overwrite)
                    .With("package", source.IsDebugPackage)
                    .With("cluster", OptionInt(options, "cluster", 0)).With("ampr", OptionBool(options, "ampr", true))
                    .With("level", OptionInt(options, "level", 7)).With("gain", OptionInt(options, "gain", 1))
                    .With("block", OptionInt(options, "block", 32768)).With("fragment", OptionInt(options, "fragment", 4096))
                    .With("density", OptionInt(options, "density", 262144)).With("minFree", OptionInt(options, "minFree", 0));
                break;
            }
            case "extract":
            {
                if (output.Length == 0) throw RpcException.BadRequest("Choose an output folder.");
                if (Directory.Exists(output) && Directory.EnumerateFileSystemEntries(output).Any()) output = AvailableDirectory(output);
                type = PackageTaskTypes.PackageExtract;
                payload.With("output", output).With("kind", source.IsPackage ? "sony" : source.Format switch
                {
                    Ps5ImageFormat.Exfat => "exfat",
                    Ps5ImageFormat.Ufs2 => "ffpkg",
                    _ => "ffpfsc"
                });
                if (source.IsPackage && passcode != SonyDebugPackageCredentials.DefaultPasscode) payload.With("passcode", passcode);
                break;
            }
            case "verify":
                if (source.IsPackage)
                {
                    type = PackageTaskTypes.PackageVerify;
                    if (passcode != SonyDebugPackageCredentials.DefaultPasscode) payload.With("passcode", passcode);
                }
                else
                {
                    type = PackageTaskTypes.ImageVerify;
                    payload.With("format", source.Format.ToString());
                }
                break;
            case "repair":
                type = PackageTaskTypes.ExfatRepair;
                break;
            case "ampr":
                type = PackageTaskTypes.ExfatAmpr;
                break;
            case "rebuild":
                type = PackageTaskTypes.FfpkgRebuild;
                break;
            default:
                throw RpcException.BadRequest("Unknown action: " + action);
        }
        QueuedPackageTask task = tasks.Enqueue(type, payload);
        return new { taskId = task.Id, output };
    }

    private object EnqueueBuild(SourceInfo source, string output, bool overwrite, string passcode, JsonElement options, TaskPayload payload)
    {
        if (source.IsPackage) throw RpcException.BadRequest("A package cannot be rebuilt into another package.");
        Operations.ParamFields param = Operations.ReadParamFields(source.Path, source.Format);
        string contentId = param.ContentId.Length > 0 ? param.ContentId : library.Find(source.Path)?.ContentId ?? string.Empty;
        if (contentId.Length == 0)
            throw RpcException.BadRequest("The source does not contain a content ID, so a package cannot be built from it.");
        if (OptionString(options, "packageType") == "AC")
            throw RpcException.BadRequest("AC (additional content) packages are not supported yet. Choose APP.");

        string backendId = OptionString(options, "backend") is { Length: > 0 } requested ? requested : state.Settings.BuildBackend;
        IPackageBackend backend = BackendRegistry.Get(backendId);
        string? temp = OptionString(options, "temp") is { Length: > 0 } workspace ? workspace : null;
        if (temp is not null && !Directory.Exists(temp)) throw RpcException.BadRequest("The workspace folder does not exist: " + temp);

        Ps5DiskSpaceCheck space = Ps5DiskSpace.Check(EstimateBytes(source.Path), output, temp);
        if (space.Status == Ps5DiskSpaceStatus.Insufficient)
            throw new RpcException("disk_space", "Not enough free disk space to build this package. " + space.Message);

        int sdkIndex = OptionInt(options, "sdk", -1);
        ulong? sdk = sdkIndex >= 0 ? Ps5SdkVersions.ExecutableVersionAt(sdkIndex) : null;
        payload.With("output", output).With("contentId", contentId).With("backend", backend.Id)
            .With("overwrite", overwrite)
            .With("sdk", sdk?.ToString("X16"))
            .With("temp", temp)
            .With("compression", OptionString(options, "compression") is { Length: > 0 } compression ? compression : "Auto")
            .With("krakenLevel", OptionInt(options, "krakenLevel", 7))
            .With("krakenThreads", OptionInt(options, "krakenThreads", 0))
            .With("playgo", OptionInt(options, "playGo", backend.Id == BackendRegistry.LppId ? 64 : 1))
            .With("drm", OptionString(options, "drm", "upgradable"))
            .With("deterministic", OptionBool(options, "deterministic", backend.Id == BackendRegistry.LppId))
            .With("fakeSign", OptionBool(options, "fakeSign", true))
            .With("rightSprx", OptionBool(options, "rightSprx", true));
        if (passcode != SonyDebugPackageCredentials.DefaultPasscode) payload.With("passcode", passcode);
        QueuedPackageTask task = tasks.Enqueue(PackageTaskTypes.ImageBuildPackage, payload);
        if (space.Status == Ps5DiskSpaceStatus.NearLimit) Logger.Warn("Low free disk space for this build. " + space.Message);
        return new { taskId = task.Id, output, warning = space.Status == Ps5DiskSpaceStatus.NearLimit ? space.Message : string.Empty };
    }

    private static string AvailableDirectory(string path)
    {
        for (int index = 2; index < 10000; index++)
        {
            string candidate = $"{path} ({index})";
            if (!Directory.Exists(candidate) && !File.Exists(candidate)) return candidate;
        }
        return path;
    }

    private static string OptionString(JsonElement options, string name, string fallback = "") =>
        options.ValueKind == JsonValueKind.Object && options.TryGetProperty(name, out JsonElement value) && value.ValueKind == JsonValueKind.String
            ? value.GetString() ?? fallback
            : fallback;

    private static int OptionInt(JsonElement options, string name, int fallback) =>
        options.ValueKind == JsonValueKind.Object && options.TryGetProperty(name, out JsonElement value)
            ? value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out int number) ? number
            : value.ValueKind == JsonValueKind.String && int.TryParse(value.GetString(), out number) ? number
            : fallback
            : fallback;

    private static bool OptionBool(JsonElement options, string name, bool fallback) =>
        options.ValueKind == JsonValueKind.Object && options.TryGetProperty(name, out JsonElement value)
            ? value.ValueKind switch { JsonValueKind.True => true, JsonValueKind.False => false, _ => fallback }
            : fallback;

    // ------------------------------------------------------------------ image editor

    public object EditorEntries(string path)
    {
        SourceInfo source = Probe(path);
        if (source.Format == Ps5ImageFormat.Exfat)
        {
            using var volume = new ExfatVolume(File.OpenRead(path));
            return new
            {
                format = "exfat",
                entries = volume.Entries.Select(entry => new { path = entry.Path, isDirectory = entry.IsDirectory, size = entry.Size })
                    .OrderBy(entry => entry.path, StringComparer.OrdinalIgnoreCase).ToList()
            };
        }
        if (source.Format == Ps5ImageFormat.Ufs2)
        {
            using var volume = new Ufs2Volume(path);
            return new
            {
                format = "ffpkg",
                entries = volume.Entries.Where(entry => entry.Path is not ("" or "/"))
                    .Select(entry => new { path = entry.Path.TrimStart('/'), isDirectory = entry.IsDirectory, size = entry.Size })
                    .OrderBy(entry => entry.path, StringComparer.OrdinalIgnoreCase).ToList()
            };
        }
        throw RpcException.BadRequest("Only exFAT and FFPKG images can be edited.");
    }

    public object EditorApply(string path, List<Operations.EditOperation> operations)
    {
        SourceInfo source = Probe(path);
        if (source.Format is not (Ps5ImageFormat.Exfat or Ps5ImageFormat.Ufs2))
            throw RpcException.BadRequest("Only exFAT and FFPKG images can be edited.");
        if (operations.Count == 0) throw RpcException.BadRequest("There are no pending changes.");
        if (tasks.IsPathBusy(path)) throw RpcException.BadRequest("Another queued or running task is using this image.");
        foreach (Operations.EditOperation operation in operations)
            if (operation.Kind is "replace" or "addFile" && !File.Exists(operation.SourcePath ?? string.Empty))
                throw RpcException.NotFound("The file to add was not found: " + operation.SourcePath);
            else if (operation.Kind == "addFolder" && !Directory.Exists(operation.SourcePath ?? string.Empty))
                throw RpcException.NotFound("The folder to add was not found: " + operation.SourcePath);
        TaskPayload payload = new TaskPayload().With("source", path).With("format", source.Format.ToString())
            .With("operations", JsonSerializer.Serialize(operations, Json.Options));
        QueuedPackageTask task = tasks.Enqueue(BridgeTaskTypes.ImageEdit, payload);
        return new { taskId = task.Id };
    }

    /// <summary>Queues extraction of files from a library item.</summary>
    public object ExtractFiles(Ps5GameInfo game, IReadOnlyList<string> files, string destination)
    {
        if (files.Count == 0) throw RpcException.BadRequest("Select one or more files to extract.");
        if (string.IsNullOrWhiteSpace(destination)) throw RpcException.BadRequest("Choose a destination folder.");
        Directory.CreateDirectory(destination);
        TaskPayload payload = new TaskPayload().With("source", game.RootPath).With("output", destination)
            .With("sourceLabel", game.SourceDescription)
            .With("files", JsonSerializer.Serialize(files));
        QueuedPackageTask task = tasks.Enqueue(BridgeTaskTypes.ExtractFiles, payload);
        return new { taskId = task.Id };
    }
}
