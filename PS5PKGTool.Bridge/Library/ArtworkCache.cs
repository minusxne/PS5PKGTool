using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using PS5PKGTool.Bridge.Infrastructure;
using PS5PKGTool.Core.Models;
using PS5PKGTool.Core.Services;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;

namespace PS5PKGTool.Bridge.Library;

/// <summary>File paths of a title's artwork in the cache; empty strings mean "not present".</summary>
public sealed record ArtworkPaths(string Icon, string Pic0, string Pic1, string Pic2)
{
    public static readonly ArtworkPaths None = new(string.Empty, string.Empty, string.Empty, string.Empty);

    /// <summary>The best wide key art for a background: pic1 (title screen) over pic0.</summary>
    public string Background => Pic1.Length > 0 ? Pic1 : Pic0.Length > 0 ? Pic0 : Pic2;
}

/// <summary>
/// Decodes artwork once and keeps it as PNG files under the XDG cache directory, so the UI loads
/// images straight from disk instead of receiving bytes over the pipe. Entries are keyed by source
/// path, size and modification time, so a changed source gets fresh artwork.
/// </summary>
public sealed class ArtworkCache
{
    private const string NoneMarker = ".none";
    private readonly Ps5DetailsLoader _loader = new();
    private readonly SemaphoreSlim _throttle = new(Math.Clamp(Environment.ProcessorCount / 2, 2, 6));
    private readonly ConcurrentDictionary<string, Task<ArtworkPaths>> _inflight = new(StringComparer.Ordinal);

    public string Root { get; } = AppPaths.ArtworkCacheDirectory;

    public string DirectoryFor(Ps5GameInfo game)
    {
        string key = $"{game.RootPath}|{game.LastWriteTimeUtc.Ticks}|{game.SourceSize}";
        string hash = Convert.ToHexString(SHA1.HashData(Encoding.UTF8.GetBytes(key))).ToLowerInvariant();
        return Path.Combine(Root, hash[..2], hash);
    }

    /// <summary>Whatever artwork is already cached, without touching the source.</summary>
    public ArtworkPaths Peek(Ps5GameInfo game)
    {
        string directory = DirectoryFor(game);
        return new ArtworkPaths(Existing(directory, "icon0.png"), Existing(directory, "pic0.png"),
            Existing(directory, "pic1.png"), Existing(directory, "pic2.png"));
    }

    public bool HasIcon(Ps5GameInfo game)
    {
        string directory = DirectoryFor(game);
        return File.Exists(Path.Combine(directory, "icon0.png")) || File.Exists(Path.Combine(directory, "icon0.png" + NoneMarker));
    }

    public bool HasFullSet(Ps5GameInfo game) => File.Exists(Path.Combine(DirectoryFor(game), "complete"));

    /// <summary>Ensures the icon (and, with <paramref name="full"/>, the backgrounds) are cached.</summary>
    public Task<ArtworkPaths> EnsureAsync(Ps5GameInfo game, bool full, CancellationToken token)
    {
        if (full ? HasFullSet(game) : HasIcon(game)) return Task.FromResult(Peek(game));
        if (!GameClassifier.SourceExists(game)) return Task.FromResult(Peek(game));
        string key = game.RootPath + (full ? "|full" : "|icon");
        return _inflight.GetOrAdd(key, _ => LoadAsync(game, full, key));
    }

    private async Task<ArtworkPaths> LoadAsync(Ps5GameInfo game, bool full, string key)
    {
        await _throttle.WaitAsync().ConfigureAwait(false);
        try
        {
            using var stop = new CancellationTokenSource(TimeSpan.FromMinutes(2));
            Ps5Artwork? captured = null;
            int reports = 0;
            // Artwork is reported before the expensive trophy/executable/inventory work, so the
            // load is stopped as soon as the wanted images arrived.
            var progress = new InlineProgress<Ps5Artwork>(value =>
            {
                captured = value;
                reports++;
                if (!full || reports >= 2) stop.Cancel();
            });
            try
            {
                Ps5GameDetails details = await _loader.LoadAsync(game, stop.Token, progress).ConfigureAwait(false);
                captured = new Ps5Artwork(details.Icon, details.Background, details.Background1, details.Background2);
            }
            catch (OperationCanceledException) when (captured is not null)
            {
            }
            catch (Exception ex)
            {
                Logger.Warn($"Artwork unavailable for '{game.RootPath}': {ex.Message}");
            }
            Store(game, captured, full);
            return Peek(game);
        }
        finally
        {
            _throttle.Release();
            _inflight.TryRemove(key, out _);
        }
    }

    /// <summary>Writes the given artwork (from a details load) into the cache.</summary>
    public ArtworkPaths Store(Ps5GameInfo game, Ps5Artwork? artwork, bool complete)
    {
        string directory = DirectoryFor(game);
        try
        {
            Directory.CreateDirectory(directory);
            Write(directory, "icon0.png", artwork?.Icon, markMissing: true);
            if (complete)
            {
                Write(directory, "pic0.png", artwork?.Background, markMissing: false);
                Write(directory, "pic1.png", artwork?.Background1, markMissing: false);
                Write(directory, "pic2.png", artwork?.Background2, markMissing: false);
                File.WriteAllText(Path.Combine(directory, "complete"), game.RootPath);
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Logger.Warn($"Could not cache artwork for '{game.RootPath}': {ex.Message}");
        }
        return Peek(game);
    }

    /// <summary>Writes an image as PNG and returns its path, or an empty string when there is none.</summary>
    public static string WritePng(string path, Ps5ImageData? image)
    {
        if (image is null || image.IsEmpty) return string.Empty;
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        string temp = path + ".tmp";
        if (!image.IsRgba)
        {
            File.WriteAllBytes(temp, image.Bytes);
        }
        else
        {
            using Image<Rgba32> decoded = Image.LoadPixelData<Rgba32>(image.Bytes, image.Width, image.Height);
            decoded.SaveAsPng(temp);
        }
        File.Move(temp, path, overwrite: true);
        return path;
    }

    public long SizeOnDisk()
    {
        try
        {
            return Directory.Exists(Root)
                ? Directory.EnumerateFiles(Root, "*", SearchOption.AllDirectories).Sum(file => new FileInfo(file).Length)
                : 0;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return 0;
        }
    }

    public void Clear()
    {
        try
        {
            if (Directory.Exists(Root)) Directory.Delete(Root, recursive: true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Logger.Warn("Could not clear the artwork cache: " + ex.Message);
        }
    }

    private static void Write(string directory, string name, Ps5ImageData? image, bool markMissing)
    {
        string path = Path.Combine(directory, name);
        if (image is null || image.IsEmpty)
        {
            if (markMissing) File.WriteAllText(path + NoneMarker, string.Empty);
            return;
        }
        try
        {
            WritePng(path, image);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidOperationException or
                                   ArgumentException or NotSupportedException or UnknownImageFormatException)
        {
            Logger.Warn($"Could not write {name}: {ex.Message}");
        }
    }

    private static string Existing(string directory, string name)
    {
        string path = Path.Combine(directory, name);
        return File.Exists(path) ? path : string.Empty;
    }
}

/// <summary>An <see cref="IProgress{T}"/> that runs the handler synchronously on the reporting thread.</summary>
public sealed class InlineProgress<T>(Action<T> handler) : IProgress<T>
{
    public void Report(T value) => handler(value);
}
