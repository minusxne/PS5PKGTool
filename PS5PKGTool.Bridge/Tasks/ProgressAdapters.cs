using PS5PKGTool.Bridge.Library;
using PS5PKGTool.Core.Builders;
using PS5PKGTool.Core.Services;
using PS5PKGTool.Core.Tasks;
using PS5PKGTool.Ffpfsc;
using UFS2Tool;

namespace PS5PKGTool.Bridge.Tasks;

/// <summary>
/// Maps each engine's progress record onto the task queue's <see cref="PackageTaskProgress"/>.
/// The adapters report synchronously on the worker thread (no SynchronizationContext exists in the
/// bridge, so <see cref="Progress{T}"/> would post to the thread pool and could reorder reports).
/// </summary>
public static class ProgressAdapters
{
    public static IProgress<SonyDebugPackageProgress> SonyPkg(IProgress<PackageTaskProgress> target) =>
        new InlineProgress<SonyDebugPackageProgress>(value => target.Report(new PackageTaskProgress(
            value.Stage, 0, 0, value.CompletedBytes, value.TotalBytes, 0, 0, value.CurrentPath)));

    public static IProgress<FfpfscProgress> Ffpfsc(IProgress<PackageTaskProgress> target) =>
        new InlineProgress<FfpfscProgress>(value => target.Report(new PackageTaskProgress(
            value.Stage, 0, 0, value.BytesProcessed, value.TotalBytes, 0, 0, string.Empty)));

    public static IProgress<Ufs2Progress> Ufs2(IProgress<PackageTaskProgress> target) =>
        new InlineProgress<Ufs2Progress>(value => target.Report(new PackageTaskProgress(
            value.Stage, 0, 0, value.BytesProcessed, value.TotalBytes,
            (int)Math.Min(value.Completed, int.MaxValue),
            (int)Math.Min(value.Total, int.MaxValue), value.Unit)));

    public static IProgress<SonyPackageExtractProgress> SonyExtract(IProgress<PackageTaskProgress> target) =>
        new InlineProgress<SonyPackageExtractProgress>(value => target.Report(new PackageTaskProgress(
            "Extracting", 0, 0, value.CompletedBytes, value.TotalBytes, 0, 0, value.CurrentPath)));

    public static IProgress<Ps5ImageConversionProgress> Conversion(IProgress<PackageTaskProgress> target) =>
        new InlineProgress<Ps5ImageConversionProgress>(value => target.Report(new PackageTaskProgress(
            value.Stage, 0, 0, value.Completed, value.Total, 0, 0, string.Empty)));
}
