using ProsperoPkgTool.Containers;

namespace PS5PKGTool.Core.Services;

/// <summary>Free-space preflight outcome, mirroring the engine without exposing its types.</summary>
public enum Ps5DiskSpaceStatus
{
    Ok,
    NearLimit,
    Insufficient
}

/// <summary>Result of a free-space preflight, with a human-readable description.</summary>
public readonly record struct Ps5DiskSpaceCheck(Ps5DiskSpaceStatus Status, string Message);

/// <summary>
/// Thin facade over the engine's <see cref="DiskSpaceGuard"/> so the UI layer does not reference the
/// engine assembly directly.
/// </summary>
public static class Ps5DiskSpace
{
    /// <summary>Estimates and checks free space for a package build.</summary>
    /// <param name="rawPayloadBytes">Source payload upper bound (dump total, or image file length).</param>
    /// <param name="outputPath">Destination package path.</param>
    /// <param name="tempDirectory">Workspace folder, or null for the system temp folder.</param>
    public static Ps5DiskSpaceCheck Check(long rawPayloadBytes, string outputPath, string? tempDirectory)
    {
        DiskSpaceReport report = Measure(
            HostRequirements(DiskSpaceGuard.Estimate(rawPayloadBytes, outputPath, tempDirectory), outputPath, tempDirectory));
        Ps5DiskSpaceStatus status = report.Status switch
        {
            DiskSpaceStatus.Insufficient => Ps5DiskSpaceStatus.Insufficient,
            DiskSpaceStatus.NearLimit => Ps5DiskSpaceStatus.NearLimit,
            _ => Ps5DiskSpaceStatus.Ok
        };
        return new Ps5DiskSpaceCheck(status, DiskSpaceGuard.Describe(report));
    }

    /// <summary>
    /// Free-space preflight for an extract-then-build: the extracted staging tree plus the build's
    /// temp workspace and output, measured against the affected volumes.
    /// </summary>
    public static Ps5DiskSpaceCheck CheckStagedImage(long rawPayloadBytes, long stagingBytes,
        string outputPath, string? tempDirectory)
    {
        var requirements = HostRequirements(DiskSpaceGuard.Estimate(rawPayloadBytes, outputPath, tempDirectory),
            outputPath, tempDirectory).ToList();
        if (stagingBytes > 0)
        {
            string tempRoot = Ps5MountInfo.VolumeOf(tempDirectory ?? Path.GetTempPath());
            int index = requirements.FindIndex(requirement =>
                string.Equals(requirement.Root, tempRoot, StringComparison.OrdinalIgnoreCase));
            if (index >= 0)
            {
                requirements[index] = requirements[index] with
                {
                    Bytes = requirements[index].Bytes + stagingBytes,
                    What = requirements[index].What + " + staging tree",
                };
            }
            else
            {
                requirements.Add(new SpaceRequirement(tempRoot, stagingBytes, "staging tree"));
            }
        }

        DiskSpaceReport report = Measure(requirements);
        Ps5DiskSpaceStatus status = report.Status switch
        {
            DiskSpaceStatus.Insufficient => Ps5DiskSpaceStatus.Insufficient,
            DiskSpaceStatus.NearLimit => Ps5DiskSpaceStatus.NearLimit,
            _ => Ps5DiskSpaceStatus.Ok,
        };
        return new Ps5DiskSpaceCheck(status, DiskSpaceGuard.Describe(report));
    }

    /// <summary>
    /// The engine keys requirements by <see cref="Path.GetPathRoot(string)"/>, which is "/" for every
    /// path on Linux and macOS, and its default free-space probe cannot read that root there. Off
    /// Windows the requirements are re-keyed to the real mount points of the output and workspace
    /// folders (splitting the engine's combined estimate when they live on different volumes).
    /// </summary>
    private static IReadOnlyList<SpaceRequirement> HostRequirements(IReadOnlyList<SpaceRequirement> estimate,
        string outputPath, string? tempDirectory)
    {
        if (OperatingSystem.IsWindows()) return estimate;
        long total = estimate.Sum(requirement => requirement.Bytes);
        string outputVolume = Ps5MountInfo.VolumeOf(Path.GetDirectoryName(Path.GetFullPath(outputPath)) ?? outputPath);
        string tempVolume = Ps5MountInfo.VolumeOf(tempDirectory ?? Path.GetTempPath());
        if (string.Equals(outputVolume, tempVolume, StringComparison.Ordinal))
            return [new SpaceRequirement(outputVolume, total, "temp workspace + output")];
        return
        [
            new SpaceRequirement(tempVolume, total / 2, "temp workspace"),
            new SpaceRequirement(outputVolume, total - total / 2, "output"),
        ];
    }

    private static DiskSpaceReport Measure(IReadOnlyList<SpaceRequirement> requirements) =>
        OperatingSystem.IsWindows()
            ? DiskSpaceGuard.Check(requirements)
            : DiskSpaceGuard.Check(requirements, root => Ps5MountInfo.AvailableFreeSpace(root) ?? long.MaxValue);

    /// <summary>True when the exception is the engine's insufficient-free-space failure.</summary>
    public static bool IsInsufficient(Exception exception) => exception is ProsperoInsufficientSpaceException;

    /// <summary>The engine's free-space message for an insufficient-space exception.</summary>
    public static string Describe(Exception exception) =>
        exception is ProsperoInsufficientSpaceException space ? space.Message : exception.Message;
}
