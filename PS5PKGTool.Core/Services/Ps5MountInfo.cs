namespace PS5PKGTool.Core.Services;

/// <summary>
/// Resolves which mounted volume a path lives on. On Windows the path root (drive letter or UNC
/// share) identifies the volume; on Linux and macOS every absolute path shares the root "/", so the
/// volume is the longest mount point that prefixes the path.
/// </summary>
public static class Ps5MountInfo
{
    /// <summary>The mount point (or Windows path root) that holds <paramref name="path"/>.</summary>
    public static string VolumeOf(string path)
    {
        string full = Path.GetFullPath(path);
        if (OperatingSystem.IsWindows()) return Path.GetPathRoot(full) ?? full;

        string best = "/";
        foreach (string mount in MountPoints())
        {
            if (mount.Length <= best.Length) continue;
            string prefix = mount.EndsWith('/') ? mount : mount + "/";
            if (full.Equals(mount, StringComparison.Ordinal) || full.StartsWith(prefix, StringComparison.Ordinal))
                best = mount;
        }
        return best;
    }

    /// <summary>True when both paths are on the same volume, so a rename can move between them.</summary>
    public static bool SameVolume(string left, string right) =>
        string.Equals(VolumeOf(left), VolumeOf(right),
            OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal);

    /// <summary>Free bytes on the volume holding <paramref name="path"/>, or null when it cannot be read.</summary>
    public static long? AvailableFreeSpace(string path)
    {
        try
        {
            return new DriveInfo(VolumeOf(path)).AvailableFreeSpace;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            return null;
        }
    }

    private static IEnumerable<string> MountPoints()
    {
        DriveInfo[] drives;
        try
        {
            drives = DriveInfo.GetDrives();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            yield break;
        }
        foreach (DriveInfo drive in drives)
            yield return drive.Name;
    }
}
