namespace PS5PKGTool.Bridge.Infrastructure;

/// <summary>
/// Where the Linux edition keeps its files, following the XDG base directory spec. Settings, the
/// library manifest, the task queue and logs live in the data directory (the same folder .NET's
/// LocalApplicationData resolves to, so it matches the layout of the Windows edition); decoded
/// artwork and preview extracts live in the cache directory and can be deleted at any time.
/// </summary>
public static class AppPaths
{
    public static string DataDirectory { get; } = Resolve("XDG_DATA_HOME", Path.Combine(".local", "share"),
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData));

    public static string CacheDirectory { get; } = Resolve("XDG_CACHE_HOME", ".cache", Path.GetTempPath());

    public static string ArtworkCacheDirectory => Path.Combine(CacheDirectory, "art");

    public static string PreviewDirectory => Path.Combine(CacheDirectory, "preview");

    public static string TaskQueuePath => Path.Combine(DataDirectory, "tasks.json");

    private static string Resolve(string variable, string homeRelative, string fallback)
    {
        string? configured = Environment.GetEnvironmentVariable(variable);
        string root;
        if (!string.IsNullOrWhiteSpace(configured) && Path.IsPathRooted(configured))
            root = configured;
        else
        {
            string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            root = string.IsNullOrEmpty(home) ? fallback : Path.Combine(home, homeRelative);
        }
        string directory = Path.Combine(root, "PS5PKGTool");
        Directory.CreateDirectory(directory);
        return directory;
    }
}
