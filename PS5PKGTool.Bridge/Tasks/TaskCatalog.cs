using System.Globalization;
using System.Text.Json;
using PS5PKGTool.Bridge.Tools;
using PS5PKGTool.Core.Backends;
using PS5PKGTool.Core.Builders;
using PS5PKGTool.Core.Models;
using PS5PKGTool.Core.Services;
using PS5PKGTool.Core.Tasks;
using PS5PKGTool.Ffpfsc;
using UFS2Tool;

namespace PS5PKGTool.Bridge.Tasks;

/// <summary>Additional task type for image edits (the Windows edition ran edits in a modal dialog).</summary>
public static class BridgeTaskTypes
{
    public const string ImageEdit = "Edit image";
    public const string ExtractFiles = "Extract files";
}

/// <summary>A task's flat, persisted configuration.</summary>
public sealed class TaskPayload : Dictionary<string, string>
{
    public TaskPayload() : base(StringComparer.Ordinal) { }

    public static TaskPayload Parse(string? json)
    {
        var payload = new TaskPayload();
        if (string.IsNullOrWhiteSpace(json)) return payload;
        try
        {
            Dictionary<string, string>? values = JsonSerializer.Deserialize<Dictionary<string, string>>(json);
            if (values is not null) foreach ((string key, string value) in values) payload[key] = value;
        }
        catch (JsonException)
        {
        }
        return payload;
    }

    public TaskPayload With(string key, object? value)
    {
        if (value is null) return this;
        this[key] = value switch
        {
            bool flag => flag ? "true" : "false",
            IFormattable formattable => formattable.ToString(null, CultureInfo.InvariantCulture),
            _ => value.ToString() ?? string.Empty
        };
        return this;
    }

    public string Get(string key) => TryGetValue(key, out string? value) ? value : string.Empty;

    public int GetInt(string key, int fallback = 0) =>
        int.TryParse(Get(key), NumberStyles.Integer, CultureInfo.InvariantCulture, out int value) ? value : fallback;

    public bool GetBool(string key, bool fallback = false) =>
        bool.TryParse(Get(key), out bool value) ? value : fallback;

    public string Serialize() => JsonSerializer.Serialize<Dictionary<string, string>>(this);
}

/// <summary>
/// Turns a task payload into an executable task. Both freshly queued jobs and jobs restored from
/// <c>tasks.json</c> go through <see cref="Create"/>, so a restored task always runs exactly what was
/// originally queued (including conversion options, which the Windows edition used to drop).
/// </summary>
public sealed class TaskCatalog(Func<string, Ps5GameInfo?> findGame)
{
    public sealed record Descriptor(
        string Type,
        string DisplayName,
        string SourcePath,
        string OutputPath,
        string Operation,
        string SourceFormat,
        string TargetFormat,
        string TargetQualifier,
        PackageTaskStage[] Plan,
        Func<IProgress<PackageTaskProgress>, CancellationToken, Task>? Execute);

    public Descriptor? Create(string type, TaskPayload fields)
    {
        string source = fields.Get("source");
        string output = fields.Get("output");
        string name = Path.GetFileName(source.TrimEnd('/'));
        switch (type)
        {
            case PackageTaskTypes.ImageConvert:
            {
                if (!Enum.TryParse(fields.Get("target"), out Ps5ImageConversionTarget target)) return null;
                bool fromPackage = fields.GetBool("package");
                bool overwrite = fields.GetBool("overwrite");
                ExfatBuildOptions? exfat = target == Ps5ImageConversionTarget.Ffpkg ? null : ExfatOptions(fields);
                FfpfscBuildOptions? ffpfsc = target == Ps5ImageConversionTarget.Ffpfsc ? FfpfscOptions(fields) : null;
                FfpkgBuildOptions? ffpkg = target == Ps5ImageConversionTarget.Ffpkg ? FfpkgOptions(fields) : null;
                return new Descriptor(type, $"Convert {name}", source, output, "Convert",
                    fields.Get("sourceLabel") is { Length: > 0 } label ? label : fromPackage ? "FPKG" : "dump",
                    TargetLabel(target), string.Empty,
                    fromPackage ? PackageTaskPlans.ConvertPackage : PackageTaskPlans.ConvertImage,
                    (progress, token) => Operations.ConvertAsync(source, output, target, overwrite, fromPackage,
                        exfat, ffpfsc, ffpkg, progress, token));
            }
            case PackageTaskTypes.PackageExtract:
            {
                string kind = fields.Get("kind");
                string passcode = Passcode(fields);
                Func<IProgress<PackageTaskProgress>, CancellationToken, Task>? execute = kind switch
                {
                    "sony" => async (progress, token) => await SonyPackageExtraction.ExtractAsync(source, output, passcode,
                        ProgressAdapters.SonyExtract(progress), token).ConfigureAwait(false),
                    "exfat" => (progress, token) => Operations.ExtractImageAsync(source, Ps5ImageFormat.Exfat, output, progress, token),
                    "ffpkg" => (progress, token) => Operations.ExtractImageAsync(source, Ps5ImageFormat.Ufs2, output, progress, token),
                    "ffpfsc" => (progress, token) => Operations.ExtractImageAsync(source, Ps5ImageFormat.Pfs, output, progress, token),
                    _ => null
                };
                return new Descriptor(type, $"Extract {name}", source, output,
                    kind == "sony" ? "Extract package" : "Extract", KindLabel(kind), "folder", string.Empty,
                    PackageTaskPlans.Extract, execute);
            }
            case BridgeTaskTypes.ExtractFiles:
            {
                List<string> files = JsonSerializer.Deserialize<List<string>>(fields.Get("files") is { Length: > 0 } json ? json : "[]") ?? [];
                Ps5GameInfo? game = findGame(source);
                return new Descriptor(type, files.Count == 1
                        ? $"Extract {Path.GetFileName(files[0])}"
                        : $"Extract {files.Count:N0} files from {name}",
                    source, output, "Extract files", fields.Get("sourceLabel"), "folder", string.Empty, PackageTaskPlans.Extract,
                    game is null ? null : (progress, token) => Operations.ExtractGameFilesAsync(game, files, output, progress, token));
            }
            case PackageTaskTypes.ImageVerify:
            {
                if (!Enum.TryParse(fields.Get("format"), out Ps5ImageFormat format)) return null;
                return new Descriptor(type, $"Verify {name}", source, source, "Verify", FormatLabel(format), string.Empty,
                    string.Empty, PackageTaskPlans.Verify,
                    (progress, token) => Operations.VerifyImageAsync(source, format, progress, token));
            }
            case PackageTaskTypes.PackageVerify:
            {
                string passcode = Passcode(fields);
                return new Descriptor(type, $"Verify {name}", source, source, "Verify package", "FPKG", string.Empty,
                    string.Empty, PackageTaskPlans.Verify,
                    (progress, token) => Operations.VerifyPackageAsync(source, passcode, progress, token));
            }
            case PackageTaskTypes.ExfatRepair:
                return new Descriptor(type, $"Repair {name}", source, source, "Repair", "exFAT", "exFAT", string.Empty,
                    PackageTaskPlans.Single,
                    async (progress, token) => await ExfatImageMaintenance.RepairAsync(source, ProgressAdapters.Ffpfsc(progress), token)
                        .ConfigureAwait(false));
            case PackageTaskTypes.ExfatAmpr:
                return new Descriptor(type, $"AMPR index for {name}", source, source, "Refresh AMPR", "exFAT", "exFAT",
                    string.Empty, PackageTaskPlans.Ampr,
                    async (progress, token) => await ExfatAmprPatcher.RefreshAsync(source, ProgressAdapters.Ffpfsc(progress), token)
                        .ConfigureAwait(false));
            case PackageTaskTypes.FfpkgRebuild:
                return new Descriptor(type, $"Rebuild {name}", source, source, "Rebuild", "FFPKG", "FFPKG", string.Empty,
                    PackageTaskPlans.Single,
                    async (progress, token) => await Ufs2Operations.RebuildWithEditsAsync(source, static _ => { },
                        ProgressAdapters.Ufs2(progress), token).ConfigureAwait(false));
            case BridgeTaskTypes.ImageEdit:
            {
                if (!Enum.TryParse(fields.Get("format"), out Ps5ImageFormat format)) return null;
                List<Operations.EditOperation> operations = JsonSerializer.Deserialize<List<Operations.EditOperation>>(
                    fields.Get("operations") is { Length: > 0 } json ? json : "[]", Protocol.Json.Options) ?? [];
                return new Descriptor(type, $"Edit {name} ({operations.Count:N0} change(s))", source, source, "Edit files",
                    FormatLabel(format), FormatLabel(format), string.Empty, PackageTaskPlans.Single,
                    async (progress, token) => await Operations.ApplyEditsAsync(source, format, operations, progress, token)
                        .ConfigureAwait(false));
            }
            case PackageTaskTypes.ImageBuildPackage:
            {
                string contentId = fields.Get("contentId");
                if (source.Length == 0 || output.Length == 0 || contentId.Length == 0) return null;
                string passcode = Passcode(fields);
                IPackageBackend backend = BackendRegistry.Get(fields.Get("backend"));
                PackageBuildSettings settings = BuildSettings(fields);
                ulong? sdk = ulong.TryParse(fields.Get("sdk"), NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out ulong parsed)
                    ? parsed
                    : null;
                string? temp = fields.Get("temp") is { Length: > 0 } workspace ? workspace : null;
                bool overwrite = fields.GetBool("overwrite");
                bool lpp = backend.Id == BackendRegistry.LppId && LppBackend.IsAvailable;
                return new Descriptor(type, $"Build package from {name}", source, output, "Build package",
                    fields.Get("sourceLabel"), "FPKG", lpp ? backend.DisplayName : BackendRegistry.Get(BackendRegistry.PptId).DisplayName,
                    PackageTaskPlans.BuildPackageFor(source, lpp && !Directory.Exists(source)),
                    (progress, token) => Operations.BuildPackageAsync(source, output, contentId, passcode, overwrite, sdk, temp,
                        settings, backend, progress, token));
            }
            default:
                return null;
        }
    }

    private static string Passcode(TaskPayload fields) =>
        fields.Get("passcode") is { Length: > 0 } passcode ? passcode : SonyDebugPackageCredentials.DefaultPasscode;

    public static ExfatBuildOptions ExfatOptions(TaskPayload fields)
    {
        int cluster = fields.GetInt("cluster");
        return new ExfatBuildOptions
        {
            ClusterSize = cluster > 0 ? cluster : null,
            GenerateAmprIndex = fields.GetBool("ampr", true)
        };
    }

    public static FfpfscBuildOptions FfpfscOptions(TaskPayload fields) => new()
    {
        Compression = new PfscCompressionOptions
        {
            CompressionLevel = Math.Clamp(fields.GetInt("level", 7), 1, 9),
            MinimumGainPercent = Math.Clamp(fields.GetInt("gain", 1), 0, 100)
        }
    };

    public static FfpkgBuildOptions FfpkgOptions(TaskPayload fields)
    {
        int block = fields.GetInt("block", 32768) == 65536 ? 65536 : 32768;
        int fragment = fields.GetInt("fragment", 4096) == 65536 ? 65536 : 4096;
        if (fragment > block) fragment = block;
        int density = fields.GetInt("density", 262144) is 524288 or 1048576 ? fields.GetInt("density") : 262144;
        return new FfpkgBuildOptions
        {
            BlockSize = block,
            FragmentSize = fragment,
            BytesPerInode = density,
            MinFreePercent = Math.Clamp(fields.GetInt("minFree"), 0, 50)
        };
    }

    public static PackageBuildSettings BuildSettings(TaskPayload fields)
    {
        Ps5InnerCompression compression = Enum.TryParse(fields.Get("compression"), out Ps5InnerCompression parsed)
            ? parsed
            : Ps5InnerCompression.Auto;
        string drm = fields.Get("drm");
        return new PackageBuildSettings(compression,
            Math.Clamp(fields.GetInt("krakenLevel", 7), -4, 9),
            Math.Clamp(fields.GetInt("krakenThreads"), 0, 256),
            Math.Clamp(fields.GetInt("playgo", 1), 1, 1000),
            drm.Length > 0 ? drm : null,
            fields.GetBool("deterministic"),
            fields.GetBool("fakeSign", true),
            fields.GetBool("rightSprx", true));
    }

    public static string TargetLabel(Ps5ImageConversionTarget target) => target switch
    {
        Ps5ImageConversionTarget.Exfat => "exFAT",
        Ps5ImageConversionTarget.Ffpkg => "FFPKG",
        _ => "FFPFSC"
    };

    public static string FormatLabel(Ps5ImageFormat format) => format switch
    {
        Ps5ImageFormat.Exfat => "exFAT",
        Ps5ImageFormat.Ufs2 => "FFPKG",
        Ps5ImageFormat.Pfs => "FFPFSC",
        _ => "image"
    };

    private static string KindLabel(string kind) => kind switch
    {
        "sony" => "FPKG",
        "exfat" => "exFAT",
        "ffpkg" => "FFPKG",
        "ffpfsc" => "FFPFSC",
        _ => kind
    };
}
