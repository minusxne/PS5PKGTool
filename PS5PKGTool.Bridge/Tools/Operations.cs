using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using PS5PKGTool.Bridge.Infrastructure;
using PS5PKGTool.Bridge.Tasks;
using PS5PKGTool.Core.Backends;
using PS5PKGTool.Core.Builders;
using PS5PKGTool.Core.Models;
using PS5PKGTool.Core.Services;
using PS5PKGTool.Core.Tasks;
using PS5PKGTool.Ffpfsc;
using UFS2Tool;

namespace PS5PKGTool.Bridge.Tools;

/// <summary>Package build knobs captured when a job is queued.</summary>
public sealed record PackageBuildSettings(
    Ps5InnerCompression Compression,
    int KrakenLevel,
    int KrakenThreads,
    int PlayGoChunks,
    string? DrmType,
    bool Deterministic,
    bool FakeSignModules,
    bool InjectRightSprx);

/// <summary>
/// The long-running operations behind every task, independent of how the task was queued. Ported
/// from the Windows edition's Image Tools so both editions produce identical output.
/// </summary>
public static class Operations
{
    public static Task ConvertAsync(string source, string output, Ps5ImageConversionTarget target, bool overwrite,
        bool fromPackage, ExfatBuildOptions? exfat, FfpfscBuildOptions? ffpfsc, FfpkgBuildOptions? ffpkg,
        IProgress<PackageTaskProgress> progress, CancellationToken token)
    {
        IProgress<Ps5ImageConversionProgress> bridge = ProgressAdapters.Conversion(progress);
        return fromPackage
            ? SonyPackageImageConversion.ConvertAsync(source, output, target, overwrite, bridge, token, exfat, ffpfsc, ffpkg)
            : Ps5ImageConversionService.ConvertAsync(source, output, target, overwrite, bridge, token, exfat, ffpfsc, ffpkg);
    }

    public static async Task ExtractImageAsync(string source, Ps5ImageFormat format, string output,
        IProgress<PackageTaskProgress> progress, CancellationToken token)
    {
        switch (format)
        {
            case Ps5ImageFormat.Exfat:
                await ExfatImage.ExtractDirectoryAsync(source, output, ProgressAdapters.Ffpfsc(progress), token).ConfigureAwait(false);
                break;
            case Ps5ImageFormat.Ufs2:
                await Ufs2Operations.ExtractAsync(source, output, ProgressAdapters.Ufs2(progress), token).ConfigureAwait(false);
                break;
            case Ps5ImageFormat.Pfs:
                await FfpfscImage.ExtractToDirectoryAsync(source, output, overwrite: true, ProgressAdapters.Ffpfsc(progress), token)
                    .ConfigureAwait(false);
                break;
            default:
                throw new InvalidDataException("Unsupported source image format.");
        }
    }

    public static async Task VerifyImageAsync(string source, Ps5ImageFormat format, IProgress<PackageTaskProgress> progress,
        CancellationToken token)
    {
        switch (format)
        {
            case Ps5ImageFormat.Exfat:
                await ExfatImage.VerifyAsync(source, ProgressAdapters.Ffpfsc(progress), token).ConfigureAwait(false);
                break;
            case Ps5ImageFormat.Ufs2:
                await Ufs2Operations.VerifyAsync(source, ProgressAdapters.Ufs2(progress), token).ConfigureAwait(false);
                break;
            case Ps5ImageFormat.Pfs:
                FfpfscVerificationResult result = await FfpfscImage.TryVerifyAsync(source, null, ProgressAdapters.Ffpfsc(progress), token)
                    .ConfigureAwait(false);
                if (!result.StructureValid)
                    throw new InvalidDataException("The FFPFSC structure is invalid. " + (result.Error ?? string.Empty));
                if (!result.EveryPfscBlockDecodes)
                    throw new InvalidDataException("An FFPFSC block failed to decode. " + (result.Error ?? string.Empty));
                break;
            default:
                throw new InvalidDataException("Unsupported image format.");
        }
    }

    public static Task VerifyPackageAsync(string source, string passcode, IProgress<PackageTaskProgress> progress,
        CancellationToken token) => Task.Run(() =>
    {
        progress.Report(new PackageTaskProgress("Verify", 0, 0, 0, 0, 0, 0, Path.GetFileName(source)));
        SonyDebugPackageValidationResult result = SonyDebugPackageBuilder.Validate(source, passcode);
        if (!result.IsValid) throw new InvalidDataException(result.Message);
        Logger.Info($"Package verified: {Path.GetFileName(source)} ({result.IndexedFiles:N0} indexed file(s)). {result.Message}");
    }, token);

    /// <summary>Copies files out of a library item (dump, image or package) into a folder.</summary>
    public static async Task ExtractGameFilesAsync(Ps5GameInfo game, IReadOnlyList<string> relativePaths, string destination,
        IProgress<PackageTaskProgress> progress, CancellationToken token)
    {
        string root = Path.GetFullPath(destination);
        string rootPrefix = root.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        var sizes = new Dictionary<string, long>(StringComparer.Ordinal);
        using (IReadOnlyGameFileSystem files = GameFileSystem.Open(game, token))
            foreach (GameFileRecord record in files.Files)
                sizes[GameFileSystem.NormalizePath(record.RelativePath)] = record.Size;

        long total = relativePaths.Sum(path => sizes.GetValueOrDefault(GameFileSystem.NormalizePath(path)));
        long completed = 0;
        int index = 0;
        foreach (string relativePath in relativePaths)
        {
            token.ThrowIfCancellationRequested();
            index++;
            string normalized = GameFileSystem.NormalizePath(relativePath);
            string target = Path.GetFullPath(Path.Combine(root, normalized.Replace('/', Path.DirectorySeparatorChar)));
            if (!target.StartsWith(rootPrefix, StringComparison.Ordinal))
                throw new IOException("The extraction path left the destination folder: " + relativePath);
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            long baseline = completed;
            int current = index;
            var fileProgress = new Library.InlineProgress<long>(copied => progress.Report(new PackageTaskProgress(
                "Extracting", 0, 0, baseline + copied, total, current, relativePaths.Count, normalized)));
            await GameFileSystem.ExtractFileAsync(game, normalized, target, fileProgress, token).ConfigureAwait(false);
            completed += sizes.GetValueOrDefault(normalized);
        }
        progress.Report(new PackageTaskProgress("Extracting", 0, 0, total, total, relativePaths.Count, relativePaths.Count, string.Empty));
    }

    /// <summary>A fixed 16-byte seed derived from the content id + passcode for reproducible builds.</summary>
    public static byte[] DeterministicSeed(string contentId, string passcode) =>
        SHA256.HashData(Encoding.UTF8.GetBytes(contentId + "\0" + passcode))[..16];

    /// <summary>
    /// Builds a debug package from a dump folder or an image. The package is written to a private
    /// job folder, verified with the canonical reader and only then moved into place, so a failed
    /// build never leaves a half-written .pkg behind.
    /// </summary>
    public static async Task BuildPackageAsync(string source, string output, string contentId, string passcode,
        bool overwrite, ulong? sdkVersionOverride, string? tempDirectory, PackageBuildSettings settings,
        IPackageBackend backend, IProgress<PackageTaskProgress> progress, CancellationToken token)
    {
        if (!overwrite && File.Exists(output))
            throw new IOException($"The output file already exists: {output}");
        string outputDirectory = Path.GetDirectoryName(Path.GetFullPath(output)) ?? Directory.GetCurrentDirectory();
        Directory.CreateDirectory(outputDirectory);
        string jobDirectory = Path.Combine(outputDirectory, ".ps5pkgtool-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(jobDirectory);
        string partial = Path.Combine(jobDirectory, Path.GetFileName(output) + ".partial");
        var options = new SonyDebugPackageBuildOptions
        {
            ContentId = contentId,
            Passcode = passcode,
            SdkVersionOverride = sdkVersionOverride,
            TempDirectory = tempDirectory,
            Log = Logger.Info,
            Compression = settings.Compression,
            KrakenLevel = settings.KrakenLevel,
            KrakenThreads = settings.KrakenThreads,
            PlayGoChunkCount = settings.PlayGoChunks,
            DrmTypeOverride = settings.DrmType,
            Seed = settings.Deterministic ? DeterministicSeed(contentId, passcode) : null,
            FakeSignModules = settings.FakeSignModules,
            InjectRightSprx = settings.InjectRightSprx
        };
        IProgress<SonyDebugPackageProgress> bridge = ProgressAdapters.SonyPkg(progress);
        bool isDirectory = Directory.Exists(source);

        IPackageBackend effective = backend;
        if (effective.Id == BackendRegistry.LppId && !LppBackend.IsAvailable)
        {
            Logger.Warn($"LibProsperoPkg is unavailable on this system ({LppBackend.UnavailableReason}); building with ProsperoPkgTool.");
            effective = BackendRegistry.Get(BackendRegistry.PptId);
        }
        // LibProsperoPkg builds only from a folder, so an image source is extracted to a staging tree
        // first; ProsperoPkgTool reads the image directly.
        bool stageFromImage = !isDirectory && effective.Id == BackendRegistry.LppId;

        string? staging = null;
        try
        {
            string buildSource = source;
            if (stageFromImage)
            {
                long rawBytes = VolumeDebugPackageBuilder.EstimatePayloadBytes(source);
                Ps5DiskSpaceCheck space = Ps5DiskSpace.CheckStagedImage(rawBytes, rawBytes, output, tempDirectory);
                if (space.Status == Ps5DiskSpaceStatus.Insufficient)
                    throw new IOException("Not enough free disk space to extract and build this image package.\n\n" + space.Message);
                staging = Path.Combine(string.IsNullOrWhiteSpace(tempDirectory) ? Path.GetTempPath() : tempDirectory,
                    "PS5PKGTool-image-" + Guid.NewGuid().ToString("N"));
                Directory.CreateDirectory(staging);
                Logger.Info("LibProsperoPkg: extracting " + Path.GetFileName(source) + " to a staging workspace before the build...");
                progress.Report(new PackageTaskProgress("Extract image", 0, 0, 0, rawBytes, 0, 0, Path.GetFileName(source)));
                await ExtractImageAsync(source, Ps5ImageFormatProbe.Detect(source), staging, progress, token).ConfigureAwait(false);
                buildSource = staging;
            }

            async Task BuildAsync()
            {
                if (isDirectory || staging is not null)
                    await effective.BuildFromDirectoryAsync(buildSource, partial, options, bridge, token).ConfigureAwait(false);
                else
                    await effective.BuildFromImageAsync(source, partial, options, bridge, token).ConfigureAwait(false);
            }

            try
            {
                await BuildAsync().ConfigureAwait(false);
            }
            catch (Exception ex) when (effective.Id == BackendRegistry.LppId && IsBackendFailure(ex))
            {
                // LibProsperoPkg can fail to lay out a title, or (on Linux) to load one of its native
                // helpers; fall back to ProsperoPkgTool automatically instead of failing the job.
                Logger.Info($"{effective.DisplayName} could not build this title ({ex.Message}); retrying with ProsperoPkgTool.");
                effective = BackendRegistry.Get(BackendRegistry.PptId);
                TryDeleteFile(partial);
                await BuildAsync().ConfigureAwait(false);
            }
            VerifyBuiltPackage(partial, passcode, effective);
            token.ThrowIfCancellationRequested();
            File.Move(partial, output, overwrite);
        }
        catch
        {
            TryDeleteFile(partial);
            throw;
        }
        finally
        {
            TryDeleteDirectory(jobDirectory);
            if (staging is not null) TryDeleteDirectory(staging);
        }
    }

    private static bool IsBackendFailure(Exception ex) =>
        ex is BackendNotSupportedException or DllNotFoundException or TypeInitializationException or
            BadImageFormatException or EntryPointNotFoundException or FileLoadException or
            System.Reflection.TargetInvocationException;

    private static void VerifyBuiltPackage(string packagePath, string passcode, IPackageBackend backend)
    {
        try
        {
            PackageReaderVerificationResult result = PackageReaderVerification.Inspect(packagePath, passcode);
            Logger.Info($"Verified with the canonical reader (built by {backend.DisplayName}): " +
                $"{result.FileCount:N0} file(s), eboot.bin {(result.HasEboot ? "present" : "missing")}.");
            if (result.FileCount == 0) throw new InvalidDataException("the reconstructed filesystem is empty");
            if (!result.HasEboot) throw new InvalidDataException("the expected /uroot/eboot.bin is missing");
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            throw new InvalidDataException("The built package failed canonical-reader verification: " + ex.Message, ex);
        }
    }

    // ------------------------------------------------------------------ image edits

    public sealed record EditOperation(string Kind, string ImagePath, string? SourcePath);

    public static async Task<string> ApplyEditsAsync(string imagePath, Ps5ImageFormat format,
        IReadOnlyList<EditOperation> operations, IProgress<PackageTaskProgress> progress, CancellationToken token)
    {
        if (operations.Count == 0) throw new InvalidOperationException("There are no pending changes to apply.");
        if (format == Ps5ImageFormat.Exfat)
        {
            List<ExfatEditOperation> edits = operations.Select(operation => operation.Kind switch
            {
                "replace" => ExfatEditOperation.Replace(operation.ImagePath, Require(operation.SourcePath)),
                "addFile" => ExfatEditOperation.AddFile(operation.ImagePath, Require(operation.SourcePath)),
                "addFolder" => ExfatEditOperation.AddDirectoryTree(operation.ImagePath, Require(operation.SourcePath)),
                "mkdir" => ExfatEditOperation.AddDirectory(operation.ImagePath),
                "delete" => ExfatEditOperation.Delete(operation.ImagePath),
                _ => throw new InvalidOperationException("Unknown edit: " + operation.Kind)
            }).ToList();
            ExfatEditResult result = await ExfatImageMaintenance.ApplyEditsAsync(imagePath, edits, ProgressAdapters.Ffpfsc(progress), token)
                .ConfigureAwait(false);
            return $"Applied {result.OperationCount:N0} change(s){(result.Rebuilt ? " (image rebuilt)" : string.Empty)}.";
        }
        if (format == Ps5ImageFormat.Ufs2)
        {
            List<Ufs2EditOperation> edits = operations.Select(operation => operation.Kind switch
            {
                "replace" => Ufs2EditOperation.Replace(operation.ImagePath, Require(operation.SourcePath)),
                "addFile" => Ufs2EditOperation.AddFile(operation.ImagePath, Require(operation.SourcePath)),
                "addFolder" => Ufs2EditOperation.AddDirectoryTree(operation.ImagePath, Require(operation.SourcePath)),
                "mkdir" => Ufs2EditOperation.AddDirectory(operation.ImagePath),
                "delete" => Ufs2EditOperation.Delete(operation.ImagePath),
                _ => throw new InvalidOperationException("Unknown edit: " + operation.Kind)
            }).ToList();
            await Ufs2Operations.ApplyEditsAsync(imagePath, edits, ProgressAdapters.Ufs2(progress), token).ConfigureAwait(false);
            return $"Applied {edits.Count:N0} change(s).";
        }
        throw new NotSupportedException("Only exFAT and FFPKG images can be edited.");
    }

    private static string Require(string? sourcePath) =>
        !string.IsNullOrWhiteSpace(sourcePath) ? sourcePath : throw new InvalidOperationException("A source file is required.");

    // ------------------------------------------------------------------ param.json

    public readonly record struct ParamFields(string ContentId, string TitleId, string ContentVersion, string TitleName);

    /// <summary>Reads identity fields straight from a dump's or image's sce_sys/param.json.</summary>
    public static ParamFields ReadParamFields(string source, Ps5ImageFormat format)
    {
        byte[]? bytes = TryReadParamBytes(source, format);
        if (bytes is null || bytes.Length == 0) return default;
        try
        {
            using JsonDocument document = JsonDocument.Parse(bytes);
            JsonElement root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return default;
            return new ParamFields(ReadString(root, "contentId"), ReadString(root, "titleId"),
                ReadString(root, "contentVersion"), ReadString(root, "titleName"));
        }
        catch (JsonException)
        {
            return default;
        }
    }

    private static string ReadString(JsonElement root, string name) =>
        root.TryGetProperty(name, out JsonElement element) && element.ValueKind == JsonValueKind.String
            ? element.GetString() ?? string.Empty
            : string.Empty;

    private static byte[]? TryReadParamBytes(string source, Ps5ImageFormat format)
    {
        try
        {
            if (Directory.Exists(source))
            {
                string path = Path.Combine(source, "sce_sys", "param.json");
                return File.Exists(path) ? File.ReadAllBytes(path) : null;
            }
            switch (format)
            {
                case Ps5ImageFormat.Exfat:
                    using (var volume = new ExfatVolume(File.OpenRead(source)))
                        return volume.ReadAllBytes("sce_sys/param.json", 4 * 1024 * 1024);
                case Ps5ImageFormat.Ufs2:
                    using (var volume = new Ufs2Volume(source))
                        return volume.ReadAllBytes("sce_sys/param.json", 4 * 1024 * 1024);
                case Ps5ImageFormat.Pfs:
                    using (var volume = FfpfscVolume.Open(source))
                        return volume.ReadAllBytes("sce_sys/param.json", 4 * 1024 * 1024);
                default:
                    return null;
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidDataException or
                                   ArgumentException or NotSupportedException)
        {
            return null;
        }
    }

    public static void TryDeleteFile(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }

    public static void TryDeleteDirectory(string path)
    {
        try { if (Directory.Exists(path)) Directory.Delete(path, recursive: true); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }
}
