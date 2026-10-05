using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using PS5PKGTool.Bridge.Infrastructure;
using PS5PKGTool.Bridge.Library;
using PS5PKGTool.Bridge.Protocol;
using PS5PKGTool.Core.Assets;
using PS5PKGTool.Core.Models;
using PS5PKGTool.Core.Parsers;
using PS5PKGTool.Core.Services;

namespace PS5PKGTool.Bridge.Details;

/// <summary>A titled list of property/value rows.</summary>
public sealed record PropertyGroup(string Title, IReadOnlyList<PropertyRow> Rows);

public sealed record PropertyRow(string Label, string Value);

/// <summary>A simple table: column names and string cells, ready for a generic table view.</summary>
public sealed record DataTableDto(IReadOnlyList<string> Columns, IReadOnlyList<IReadOnlyList<string>> Rows)
{
    public static DataTableDto Empty(params string[] columns) => new(columns, []);
}

/// <summary>
/// Deep, per-title information for the details page: overview, artwork, trophies, activities,
/// executable and container data. Loads are cached per source so switching tabs is instant.
/// </summary>
public sealed class DetailsService(LibraryService library)
{
    private readonly Ps5DetailsLoader _loader = new();
    private readonly object _gate = new();
    private readonly LinkedList<(string Key, Task<Ps5GameDetails> Load)> _cache = new();
    private const int CacheSize = 12;

    public Task<Ps5GameDetails> LoadAsync(Ps5GameInfo game)
    {
        string key = game.RootPath + "|" + game.LastWriteTimeUtc.Ticks;
        lock (_gate)
        {
            for (LinkedListNode<(string Key, Task<Ps5GameDetails> Load)>? node = _cache.First; node is not null; node = node.Next)
            {
                if (node.Value.Key != key) continue;
                if (node.Value.Load.IsFaulted || node.Value.Load.IsCanceled)
                {
                    _cache.Remove(node);
                    break;
                }
                _cache.Remove(node);
                _cache.AddFirst(node);
                return node.Value.Load;
            }
            Task<Ps5GameDetails> load = _loader.LoadAsync(game, CancellationToken.None);
            _cache.AddFirst((key, load));
            while (_cache.Count > CacheSize) _cache.RemoveLast();
            return load;
        }
    }

    public void Invalidate()
    {
        lock (_gate) _cache.Clear();
    }

    public async Task<object> GetAsync(Ps5GameInfo game, CancellationToken token)
    {
        if (!GameClassifier.SourceExists(game))
            throw RpcException.NotFound("The source was not found on disk: " + game.RootPath);
        Ps5GameDetails details = await LoadAsync(game).WaitAsync(token).ConfigureAwait(false);
        ArtworkPaths art = library.Artwork.Store(game, new Ps5Artwork(details.Icon, details.Background, details.Background1,
            details.Background2), complete: true);
        string artDirectory = library.Artwork.DirectoryFor(game);

        return new
        {
            row = library.Row(game),
            overview = Overview(game, details),
            artwork = new[]
            {
                ArtworkSlot("Icon", "icon0", art.Icon, details.Icon),
                ArtworkSlot("Key art", "pic0", art.Pic0, details.Background),
                ArtworkSlot("Title screen", "pic1", art.Pic1, details.Background1),
                ArtworkSlot("Extra art", "pic2", art.Pic2, details.Background2)
            },
            sections = details.Sections.Select(pair => new
            {
                name = pair.Key,
                state = pair.Value.State.ToString(),
                stateText = pair.Value.StateText,
                origin = pair.Value.Origin,
                message = pair.Value.Message
            }).ToList(),
            errors = details.Errors,
            trophies = Trophies(details, artDirectory),
            activities = Activities(details),
            executable = Executable(details),
            files = new
            {
                count = details.Files.FileCount,
                totalBytes = details.Files.TotalSize,
                totalText = GameClassifier.FormatBytes(details.Files.TotalSize),
                largest = details.Files.LargestFiles.Take(8).Select(file => new
                {
                    path = file.RelativePath.Replace('\\', '/'),
                    sizeText = GameClassifier.FormatBytes(file.Size)
                }).ToList(),
                note = FilesNote(game)
            },
            rawParam = RawParam(game.RawParamJson),
            localizedTitles = game.LocalizedTitles.Select(pair => new { language = pair.Key, title = pair.Value }).ToList()
        };
    }

    private static object ArtworkSlot(string label, string key, string path, Ps5ImageData? data) => new
    {
        label,
        key,
        path,
        present = path.Length > 0,
        format = data is null ? "not present" : data.IsRgba ? "DDS (decoded)" : "PNG",
        width = data?.Width ?? 0,
        height = data?.Height ?? 0
    };

    private static string FilesNote(Ps5GameInfo game) => game.SourceKind switch
    {
        Ps5SourceKind.LooseDump => "Files in the dump folder.",
        Ps5SourceKind.SonyPackage => "Files inside the package (the inner filesystem when it can be decrypted, otherwise the CNT entries).",
        Ps5SourceKind.Ffpfsc => "Files inside the compressed PFSC image.",
        Ps5SourceKind.FilesystemImage => "Files inside the exFAT image.",
        Ps5SourceKind.Ffpkg => "Files inside the FFPKG (UFS2) image.",
        _ => string.Empty
    };

    // ------------------------------------------------------------------ overview

    private static List<PropertyGroup> Overview(Ps5GameInfo game, Ps5GameDetails details)
    {
        var groups = new List<PropertyGroup>();
        List<PropertyRow> Group(string title)
        {
            var rows = new List<PropertyRow>();
            groups.Add(new PropertyGroup(title, rows));
            return rows;
        }
        static void Add(List<PropertyRow> rows, string label, object? value)
        {
            string text = value?.ToString() ?? string.Empty;
            if (!string.IsNullOrWhiteSpace(text)) rows.Add(new PropertyRow(label, text));
        }

        List<PropertyRow> identity = Group("Identity");
        Add(identity, "Title", game.Title);
        Add(identity, "Title ID", game.TitleId);
        Add(identity, "Content ID", game.ContentId);
        Add(identity, "Concept ID", game.ConceptId);
        Add(identity, "Category", GameClassifier.CategoryOf(game));
        Add(identity, "Region", GameClassifier.RegionOf(game));
        Add(identity, "Platform", game.Platform);
        Add(identity, "Default language", game.DefaultLanguage);
        Add(identity, "Content badge", game.ContentBadgeType);

        List<PropertyRow> versions = Group("Versions & compatibility");
        Add(versions, "Content version", game.ContentVersion);
        Add(versions, "Master version", game.MasterVersion);
        Add(versions, "Target content version", game.TargetContentVersion);
        Add(versions, "Origin content version", game.OriginContentVersion);
        Add(versions, "Required system software", game.RequiredSystemSoftware);
        Add(versions, "SDK version", game.SdkVersion);
        Add(versions, "Creation date", game.CreationDate);
        Add(versions, "Publishing tool", game.ToolVersion);
        Add(versions, "Version URI", game.VersionFileUri);

        List<PropertyRow> content = Group("Content");
        Add(content, "DRM type", game.DrmType);
        Add(content, "Declared features", string.Join(", ", game.DeclaredFeatures));
        Add(content, "Game intents", string.Join(", ", game.GameIntents));
        Add(content, "Shared add-on IDs", string.Join(", ", game.SharedAddOnServiceIds));
        Add(content, "Feature attributes",
            $"0x{game.Attribute:X8} / 0x{game.Attribute2:X8} / 0x{game.Attribute3:X8} / 0x{game.Attribute4:X8}");
        if (game.DownloadDataSize > 0) Add(content, "Download data size", GameClassifier.FormatBytes(game.DownloadDataSize));
        if (game.FlexibleMemorySize.HasValue) Add(content, "Flexible memory", GameClassifier.FormatBytes(game.FlexibleMemorySize.Value));
        Add(content, "Age levels", string.Join(", ", game.AgeLevels.Select(pair => $"{pair.Key}: {pair.Value}")));
        Add(content, "Localized titles", game.LocalizedTitles.Count > 0 ? $"{game.LocalizedTitles.Count:N0} languages" : string.Empty);

        List<PropertyRow> storage = Group("Source");
        Add(storage, "Format", game.SourceDescription);
        if (game.SourceSize > 0) Add(storage, "Size", GameClassifier.FormatBytes(game.SourceSize));
        Add(storage, "Location", game.RootPath);
        Add(storage, "Files", details.Files.FileCount > 0
            ? $"{details.Files.FileCount:N0} files, {GameClassifier.FormatBytes(details.Files.TotalSize)}"
            : string.Empty);
        if (game.SourceKind is Ps5SourceKind.Ffpfsc or Ps5SourceKind.FilesystemImage or Ps5SourceKind.Ffpkg)
        {
            Add(storage, game.SourceKind == Ps5SourceKind.Ffpfsc ? "Inner filesystem image" : "Filesystem image", game.ContainerInnerFileName);
            if (game.ContainerFileLength > 0) Add(storage, "Container file length", GameClassifier.FormatBytes(game.ContainerFileLength));
            if (game.ContainerLogicalSize > 0) Add(storage, "Inner logical length", GameClassifier.FormatBytes(game.ContainerLogicalSize));
            if (game.GameRootBytes > 0) Add(storage, "Game files", GameClassifier.FormatBytes(game.GameRootBytes));
            if (game.SourceKind == Ps5SourceKind.Ffpfsc)
            {
                if (game.ContainerStoredSize > 0) Add(storage, "Stored PFSC size", GameClassifier.FormatBytes(game.ContainerStoredSize));
                Add(storage, "PFSC blocks", game.ContainerBlockCount.ToString("N0", CultureInfo.InvariantCulture));
                if (game.ContainerLogicalSize > 0 && game.ContainerStoredSize > 0)
                    Add(storage, "Compression ratio", $"{100d * game.ContainerStoredSize / game.ContainerLogicalSize:0.#}% of original");
            }
            Add(storage, "Game root in image", game.VirtualRoot);
        }

        if (game.Package is SonyPkgSummary package)
        {
            List<PropertyRow> pkg = Group("Package");
            Add(pkg, "Package type", package.KindDisplayName);
            Add(pkg, "Package size", GameClassifier.FormatBytes(package.FileSize));
            Add(pkg, "CNT entries", $"{package.Entries.Count:N0} ({package.EncryptedEntryCount:N0} encrypted)");
            Add(pkg, "CNT content type", package.ContentType switch
            {
                0x20 => "Application (0x00000020)",
                0x21 => "Additional content (0x00000021)",
                _ => $"0x{package.ContentType:X8}"
            });
            Add(pkg, "CNT DRM type", $"0x{package.DrmType:X8}");
            Add(pkg, "CNT header flags", $"0x{package.HeaderFlags:X8}");
            if (package.SignedByte is { } signedByte)
                Add(pkg, "FIH signed byte", signedByte switch
                {
                    0x00 => "0x00 (finalized debug / FPKG)",
                    0x80 => "0x80 (finalized retail)",
                    _ => $"0x{signedByte:X2}"
                });
            if (package.PfsImageSize > 0)
            {
                Add(pkg, "PFS image", $"0x{package.PfsImageOffset:X} · " + (package.PfsImageSize <= long.MaxValue
                    ? GameClassifier.FormatBytes((long)package.PfsImageSize)
                    : $"0x{package.PfsImageSize:X} bytes"));
                if (package.NestedPfs is { } nested)
                {
                    Add(pkg, "PFS access", nested.AccessState == SonyPfsAccessState.EncryptedKeyRequired
                        ? "Retail image key required"
                        : nested.AccessState.ToString());
                    if (nested.Files.Count > 0) Add(pkg, "PFS files", nested.Files.Count.ToString("N0", CultureInfo.InvariantCulture));
                    Add(pkg, "PFS status", nested.StatusMessage);
                }
            }
        }

        List<PropertyRow> sections = Group("What could be read");
        foreach (KeyValuePair<string, SectionStatus> section in details.Sections)
            Add(sections, section.Key, section.Value.Display);
        foreach (string warning in game.DataWarnings) Add(sections, "Metadata warning", warning);

        groups.RemoveAll(group => group.Rows.Count == 0);
        return groups;
    }

    private static object RawParam(string json)
    {
        string formatted = json;
        try
        {
            if (!string.IsNullOrWhiteSpace(json))
            {
                using JsonDocument document = JsonDocument.Parse(json);
                formatted = JsonSerializer.Serialize(document.RootElement, new JsonSerializerOptions
                {
                    WriteIndented = true,
                    Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
                });
            }
        }
        catch (JsonException)
        {
        }
        return new { original = json, formatted };
    }

    // ------------------------------------------------------------------ trophies

    private static object? Trophies(Ps5GameDetails details, string artDirectory)
    {
        if (details.TrophySet is not { } set)
            return new
            {
                present = false,
                message = details.Sections.TryGetValue("Trophies", out SectionStatus? status) && status.Message.Length > 0
                    ? status.Message
                    : "No trophy set (sce_sys/trophy2/trophy00.ucp) was found for this source."
            };

        string iconDirectory = Path.Combine(artDirectory, "trophies");
        var trophies = new List<object>();
        foreach (Ps5Trophy trophy in set.Trophies)
        {
            string icon = Path.Combine(iconDirectory, $"trop{trophy.Id:D3}.png");
            try
            {
                if (!File.Exists(icon))
                {
                    if (trophy.IconPng is { Length: > 0 } png)
                    {
                        Directory.CreateDirectory(iconDirectory);
                        File.WriteAllBytes(icon, png);
                    }
                    else icon = ArtworkCache.WritePng(icon, trophy.Icon);
                }
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidOperationException or ArgumentException)
            {
                icon = string.Empty;
            }
            trophies.Add(new
            {
                id = trophy.Id,
                grade = trophy.Grade,
                hidden = trophy.Hidden,
                hasReward = trophy.HasReward,
                name = trophy.Name,
                description = trophy.Description,
                unlockCondition = trophy.UnlockCondition,
                udsStatId = trophy.UdsStatId,
                icon
            });
        }
        return new
        {
            present = true,
            title = set.Title,
            npCommunicationId = set.NpCommunicationId,
            version = set.TrophySetVersion,
            language = set.SelectedLanguage,
            languages = set.Languages,
            integrityValid = set.IntegrityValid,
            counts = new
            {
                platinum = set.Trophies.Count(trophy => trophy.Grade.Equals("Platinum", StringComparison.OrdinalIgnoreCase)),
                gold = set.Trophies.Count(trophy => trophy.Grade.Equals("Gold", StringComparison.OrdinalIgnoreCase)),
                silver = set.Trophies.Count(trophy => trophy.Grade.Equals("Silver", StringComparison.OrdinalIgnoreCase)),
                bronze = set.Trophies.Count(trophy => trophy.Grade.Equals("Bronze", StringComparison.OrdinalIgnoreCase)),
                hidden = set.Trophies.Count(trophy => trophy.Hidden),
                total = set.Trophies.Count
            },
            trophies
        };
    }

    // ------------------------------------------------------------------ activities

    private static object Activities(Ps5GameDetails details)
    {
        if (details.Uds is not { } uds)
            return new { present = false, message = "No activities or UDS data (sce_sys/uds/uds00.ucp) was found for this source." };

        string TrophyRefs(int statId) => details.TrophySet is not { } set
            ? string.Empty
            : string.Join(", ", set.Trophies.Where(trophy => trophy.UdsStatId == statId).Select(trophy => trophy.Id));

        return new
        {
            present = true,
            npCommunicationId = uds.NpCommunicationId,
            integrityValid = uds.IntegrityValid,
            events = uds.Events.Select(item => new
            {
                name = item.Name,
                type = item.Type,
                group = item.DefinitionGroup,
                properties = item.Properties.Select(property => new
                {
                    path = property.Path,
                    type = property.DataType,
                    itemType = property.ItemType,
                    mapped = property.MappedProperty
                }).ToList()
            }).ToList(),
            stats = new DataTableDto(["ID", "Name", "Group", "Type", "Aggregation", "Origin", "Enum", "Min", "Max", "Initial", "Trophies"],
                uds.Stats.Select(stat => (IReadOnlyList<string>)
                [
                    stat.StatId.ToString(CultureInfo.InvariantCulture), stat.Name, stat.DefinitionGroup, stat.DataType,
                    stat.Aggregation, stat.Origin, stat.EnumId.ToString(CultureInfo.InvariantCulture), stat.MinValue,
                    stat.MaxValue, stat.InitialValue, TrophyRefs(stat.StatId)
                ]).ToList()),
            enums = new DataTableDto(["Enum", "Group", "Source", "Values", "Sample"],
                uds.EnumGroups.Select(group => (IReadOnlyList<string>)
                [
                    group.EnumId.ToString(CultureInfo.InvariantCulture), group.DefinitionGroup, group.SourceId,
                    group.ValueCount.ToString(CultureInfo.InvariantCulture), string.Join(", ", group.Values.Take(4))
                ]).ToList()),
            rules = new DataTableDto(["Rule", "Group", "Event", "Condition", "Input", "Convert", "Output stat"],
                uds.Rules.Select(rule => (IReadOnlyList<string>)
                [
                    rule.RuleId.ToString(CultureInfo.InvariantCulture), rule.DefinitionGroup, rule.EventName, rule.Condition,
                    rule.Input, rule.Convert, $"{rule.OutputStatName} (#{rule.OutputStatId})"
                ]).ToList())
        };
    }

    // ------------------------------------------------------------------ executable

    private static object Executable(Ps5GameDetails details)
    {
        if (details.Executable is not { } executable)
        {
            string message = details.Sections.TryGetValue("Executable", out SectionStatus? status) && status.Message.Length > 0
                ? "eboot.bin could not be read: " + status.Message
                : "eboot.bin was not found.";
            return new { present = false, message };
        }

        static string Machine(ushort machine) => machine switch
        {
            0x3E => "x86-64",
            0xB7 => "aarch64",
            0x03 => "x86",
            _ => $"machine 0x{machine:X4}"
        };
        static string ProgramType(uint type) => type switch
        {
            0 => "PT_NULL",
            1 => "PT_LOAD",
            2 => "PT_DYNAMIC",
            3 => "PT_INTERP",
            4 => "PT_NOTE",
            5 => "PT_SHLIB",
            6 => "PT_PHDR",
            7 => "PT_TLS",
            _ => $"0x{type:X}"
        };

        var header = new List<PropertyRow>();
        void Add(string label, string value)
        {
            if (!string.IsNullOrEmpty(value)) header.Add(new PropertyRow(label, value));
        }
        Add("Container", executable.IsSelf ? "SELF " + executable.SelfMagic : "Plain ELF (no SELF container)");
        if (executable.IsSelf)
        {
            Add("SELF version", executable.SelfVersion.ToString(CultureInfo.InvariantCulture));
            Add("Program type", $"0x{executable.SelfProgramType:X8}");
            Add("Header size", $"0x{executable.SelfHeaderSize:X}");
            Add("Metadata size", $"0x{executable.SelfMetadataSize:X}");
            if (executable.SelfDeclaredFileSize > 0) Add("Declared file size", GameClassifier.FormatBytes((long)executable.SelfDeclaredFileSize));
            Add("Segment count", executable.SelfSegmentCount.ToString(CultureInfo.InvariantCulture));
            Add("Flags", $"0x{executable.SelfFlags:X}");
        }
        Add("ELF offset", $"0x{executable.ElfOffset:X}");
        Add("ELF class", executable.ElfClass == 2 ? "ELF64" : executable.ElfClass.ToString(CultureInfo.InvariantCulture));
        Add("Machine", Machine(executable.Machine));
        Add("Entry point", $"0x{executable.EntryPoint:X}");
        Add("Program headers", executable.ProgramHeaderCount.ToString(CultureInfo.InvariantCulture));
        Add("Sections", executable.SectionHeaderCount.ToString(CultureInfo.InvariantCulture));
        Add("File size", GameClassifier.FormatBytes(executable.FileSize));

        return new
        {
            present = true,
            summary = $"{(executable.IsSelf ? "SELF " + executable.SelfMagic : "Plain ELF")} · {GameClassifier.FormatBytes(executable.FileSize)} · " +
                      $"{Machine(executable.Machine)} · entry 0x{executable.EntryPoint:X} · {executable.Modules.Count} modules",
            header,
            modules = new DataTableDto(["Module", "Kind", "Size", "Path"],
                executable.Modules.Select(module => (IReadOnlyList<string>)
                    [module.Name, module.Kind, GameClassifier.FormatBytes(module.Size), module.RelativePath.Replace('\\', '/')]).ToList()),
            modulePaths = executable.Modules.Select(module => module.RelativePath.Replace('\\', '/')).ToList(),
            programs = new DataTableDto(["Idx", "Type", "Flags", "Offset", "VAddr", "PAddr", "File size", "Mem size", "Align"],
                executable.ProgramHeaders.Select(program => (IReadOnlyList<string>)
                [
                    program.Index.ToString(CultureInfo.InvariantCulture), ProgramType(program.Type), $"0x{program.Flags:X}",
                    $"0x{program.Offset:X}", $"0x{program.VirtualAddress:X}", $"0x{program.PhysicalAddress:X}",
                    GameClassifier.FormatBytes(program.FileSize), GameClassifier.FormatBytes(program.MemorySize), $"0x{program.Align:X}"
                ]).ToList()),
            sections = new DataTableDto(["Idx", "Name offset", "Type", "Flags", "Address", "Offset", "Size"],
                executable.SectionHeaders.Select(section => (IReadOnlyList<string>)
                [
                    section.Index.ToString(CultureInfo.InvariantCulture), $"0x{section.Name:X8}", $"0x{section.Type:X8}",
                    $"0x{section.Flags:X}", $"0x{section.Address:X}", $"0x{section.Offset:X}", GameClassifier.FormatBytes(section.Size)
                ]).ToList()),
            segments = new DataTableDto(["Idx", "Flags", "File offset", "File size", "Mem size"],
                executable.SelfSegments.Select(segment => (IReadOnlyList<string>)
                [
                    segment.Index.ToString(CultureInfo.InvariantCulture), $"0x{segment.Flags:X}", $"0x{segment.FileOffset:X}",
                    GameClassifier.FormatBytes(segment.FileSize), GameClassifier.FormatBytes(segment.MemorySize)
                ]).ToList())
        };
    }

    public static async Task<object> EbootHashAsync(Ps5GameInfo game, CancellationToken token) =>
        await Task.Run(() =>
        {
            using IReadOnlyGameFileSystem files = GameFileSystem.Open(game, token);
            if (!files.FileExists("eboot.bin")) throw RpcException.NotFound("eboot.bin was not found.");
            using Stream stream = files.OpenRead("eboot.bin");
            byte[] hash = SHA256.HashData(stream);
            return (object)new { sha256 = Convert.ToHexString(hash) };
        }, token).ConfigureAwait(false);

    // ------------------------------------------------------------------ container

    public async Task<object> ContainerAsync(Ps5GameInfo game, CancellationToken token)
    {
        if (!GameClassifier.SourceExists(game)) throw RpcException.NotFound("The source was not found on disk.");
        Ps5GameDetails? details = null;
        try { details = await LoadAsync(game).WaitAsync(token).ConfigureAwait(false); }
        catch (Exception ex) when (ex is not OperationCanceledException) { }

        return await Task.Run(() =>
        {
            SonyPkgSummary? package = game.Package;
            var header = new List<PropertyRow>();
            void Add(string label, string value)
            {
                if (!string.IsNullOrEmpty(value)) header.Add(new PropertyRow(label, value));
            }
            Add("Kind", package?.KindDisplayName ?? game.SourceDescription);
            Add("Location", game.RootPath);
            if (package is not null)
            {
                Add("File size", GameClassifier.FormatBytes(package.FileSize));
                Add("Signed byte", package.SignedByte.HasValue ? $"0x{package.SignedByte:X2}" : string.Empty);
                Add("Format version", package.FormatVersion?.ToString(CultureInfo.InvariantCulture) ?? string.Empty);
                Add("PFS offset", $"0x{package.PfsImageOffset:X}");
                Add("PFS size", GameClassifier.FormatBytes((long)Math.Min(package.PfsImageSize, long.MaxValue)));
                Add("PFS superblock offset", $"0x{package.PfsSuperblockOffset:X}");
                Add("Embedded CNT offset", $"0x{package.EmbeddedCntOffset:X}");
                Add("Header flags", $"0x{package.HeaderFlags:X8}");
                Add("System entry count", package.SystemEntryCount.ToString(CultureInfo.InvariantCulture));
                Add("Body offset", $"0x{package.BodyOffset:X}");
                Add("Body size", GameClassifier.FormatBytes((long)Math.Min(package.BodySize, long.MaxValue)));
                Add("Content ID", package.ContentId);
                Add("DRM type", $"0x{package.DrmType:X8}");
                Add("Content type", package.ContentType == 0x20 ? "0x00000020  GD (game data)" : $"0x{package.ContentType:X8}");
                Add("Content flags", $"0x{package.ContentFlags:X8}");
                Add("CNT entries", package.Entries.Count.ToString("N0", CultureInfo.InvariantCulture));
                Add("Encrypted entries", package.EncryptedEntryCount.ToString("N0", CultureInfo.InvariantCulture));
                if (package.NestedPfs is { } pfs)
                {
                    Add("PFS access", pfs.AccessState.ToString());
                    if (pfs.BlockSize > 0) Add("PFS block size", GameClassifier.FormatBytes(pfs.BlockSize));
                    if (pfs.InodeCount > 0) Add("PFS inodes", pfs.InodeCount.ToString("N0", CultureInfo.InvariantCulture));
                    Add("PFS status", pfs.StatusMessage);
                }
            }

            DataTableDto segments = package is null
                ? DataTableDto.Empty("Name", "Offset", "Size", "Note")
                : new DataTableDto(["Name", "Offset", "Size", "Note"], package.Segments.Select(segment => (IReadOnlyList<string>)
                [
                    segment.Name switch
                    {
                        "SC" => "SC (embedded CNT)",
                        "CNT" => "CNT (metadata container)",
                        "LIH" => "LIH (patch layer)",
                        _ => segment.Name
                    },
                    $"0x{segment.Offset:X}", GameClassifier.FormatBytes(segment.Size),
                    segment.Name switch
                    {
                        "SC" or "CNT" => "Block-aligned (64 KiB); not the logical CNT length",
                        "LIH" => "Patch layer header",
                        _ => string.Empty
                    }
                ]).ToList());

            DataTableDto entries = package is null
                ? DataTableDto.Empty("Id", "Name", "Offset", "Size", "Stored", "Encrypted", "Key")
                : new DataTableDto(["Id", "Name", "Offset", "Size", "Stored", "Encrypted", "Key"],
                    package.Entries.OrderBy(entry => entry.Id).Select(entry => (IReadOnlyList<string>)
                    [
                        $"0x{entry.Id:X4}", entry.DisplayName, $"0x{entry.DataOffset:X}", GameClassifier.FormatBytes(entry.DataSize),
                        GameClassifier.FormatBytes(entry.StoredSize), entry.IsEncrypted ? "yes" : "no",
                        entry.KeyIndex.ToString(CultureInfo.InvariantCulture)
                    ]).ToList());

            byte[] sfoBytes = ReadParamSfo(game, package);
            var sfo = new DataTableDto(["Key", "Format", "Value"],
                Ps5SfoReader.Read(sfoBytes).Select(entry => (IReadOnlyList<string>)[entry.Key, entry.Format, entry.Value]).ToList());

            var keystone = new DataTableDto(["File", "Status", "Size", "Leading bytes"],
                new[] { "sce_sys/keystone", "sce_sys/nptitle.dat", "sce_sys/about/right.sprx" }
                    .Select(path => ExtraFileRow(game, path)).ToList());

            SonyPkgSegment? siSegment = package?.Segments.FirstOrDefault(segment => segment.Name.Equals("SI", StringComparison.OrdinalIgnoreCase));
            var si = new DataTableDto(["Member", "Size"], siSegment is null
                ? []
                : Ps5SiReader.List(game.RootPath, siSegment.Offset, siSegment.Size)
                    .Select(member => (IReadOnlyList<string>)[member.Name, GameClassifier.FormatBytes(member.Size)]).ToList());

            return (object)new
            {
                isPackage = package is not null,
                header,
                segments,
                entries,
                sfo,
                keystone,
                si,
                playGo = PlayGo(game, details, siSegment)
            };
        }, token).ConfigureAwait(false);
    }

    private static object PlayGo(Ps5GameInfo game, Ps5GameDetails? details, SonyPkgSegment? siSegment)
    {
        byte[]? plgx = null;
        if (siSegment is not null)
        {
            try { plgx = Ps5SiReader.ReadMember(game.RootPath, siSegment.Offset, siSegment.Size, "playgo-chunk.dat"); }
            catch (Exception ex) when (ex is IOException or InvalidDataException) { }
        }
        if (plgx is not { Length: > 0 }) plgx = ReadGameFile(game, "sce_sys/playgo-chunk.dat") is { Length: > 0 } fromFiles ? fromFiles : null;
        bool hasPlgx = plgx is { Length: > 0 };
        byte[] hashTable = ReadGameFile(game, "sce_sys/playgo-hash-table.dat");
        byte[] ficm = ReadGameFile(game, "sce_sys/playgo-ficm.dat");
        string[] paths = (details?.Files.Files ?? []).Select(file => file.RelativePath.Replace('\\', '/')).ToArray();
        Ps5PlayGoSummary summary = Ps5PlayGoReader.Read(plgx, hashTable, ficm, Ps5PlayGoReader.BuildPathMap(paths));
        int resolved = summary.Files.Count(file => !string.IsNullOrEmpty(file.Path));
        string text = summary.Chunks.Count == 0 && summary.Files.Count == 0
            ? "No PlayGo metadata was found for this source." + (summary.Notice.Length > 0 ? " " + summary.Notice : string.Empty)
            : (hasPlgx ? $"PlayGo v{summary.VersionMajor}.{summary.VersionMinor} · " : "File mapping only · ") +
              $"{summary.Chunks.Count:N0} chunks · {summary.Scenarios.Count:N0} scenarios · default scenario {summary.DefaultScenarioId} · " +
              $"{resolved:N0} of {summary.Files.Count:N0} files mapped" + (summary.Notice.Length > 0 ? " · " + summary.Notice : string.Empty);
        return new
        {
            summary = text,
            chunks = new DataTableDto(["Chunk", "Label", "Extents", "Language mask", "Size"], summary.Chunks.Select(chunk => (IReadOnlyList<string>)
            [
                chunk.Id.ToString(CultureInfo.InvariantCulture), chunk.Label, chunk.ExtentCount.ToString(CultureInfo.InvariantCulture),
                $"0x{chunk.LanguageMask:X16}", GameClassifier.FormatBytes(chunk.TotalBytes)
            ]).ToList()),
            scenarios = new DataTableDto(["Scenario", "Label", "Initial", "Chunks", "Sequence"], summary.Scenarios.Select(scenario => (IReadOnlyList<string>)
            [
                scenario.Id.ToString(CultureInfo.InvariantCulture), scenario.Label,
                scenario.InitialChunkCount.ToString(CultureInfo.InvariantCulture),
                scenario.Chunks.Count.ToString(CultureInfo.InvariantCulture), string.Join(" ", scenario.Chunks)
            ]).ToList()),
            files = new DataTableDto(["Path", "Chunk", "Path hash"], summary.Files.Take(20000).Select(file => (IReadOnlyList<string>)
                [file.Path, file.ChunkId.ToString(CultureInfo.InvariantCulture), $"0x{file.PathHash:X16}"]).ToList())
        };
    }

    private static byte[] ReadParamSfo(Ps5GameInfo game, SonyPkgSummary? package)
    {
        const uint ParamSfoEntryId = 0x1000;
        const int MaximumSfoBytes = 1 << 20;
        SonyPkgEntry? entry = package?.Entries.FirstOrDefault(candidate => candidate.Id == ParamSfoEntryId);
        if (entry is not null && !entry.IsEncrypted && entry.DataSize > 0 && entry.DataSize <= MaximumSfoBytes)
        {
            try { return new SonyPkgReader().ReadEntryBytes(game.RootPath, package!, entry, MaximumSfoBytes); }
            catch (InvalidDataException) { }
        }
        return ReadGameFile(game, "sce_sys/param.sfo");
    }

    private static byte[] ReadGameFile(Ps5GameInfo game, string path)
    {
        try { return GameFileSystem.ReadFileChunk(game, path, 0, 4 * 1024 * 1024).Data; }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidDataException or
                                   NotSupportedException or ArgumentException) { return []; }
    }

    private static IReadOnlyList<string> ExtraFileRow(Ps5GameInfo game, string path)
    {
        try
        {
            GameFileChunk chunk = GameFileSystem.ReadFileChunk(game, path, 0, 16);
            return [path, "present", GameClassifier.FormatBytes(chunk.FileSize), Convert.ToHexString(chunk.Data)];
        }
        catch (FileNotFoundException) { return [path, "not present", string.Empty, string.Empty]; }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidDataException or
                                   NotSupportedException or ArgumentException)
        {
            return [path, "read failed: " + ex.Message, string.Empty, string.Empty];
        }
    }

    // ------------------------------------------------------------------ files

    public async Task<object> FilesAsync(Ps5GameInfo game, CancellationToken token)
    {
        Ps5GameDetails details = await LoadAsync(game).WaitAsync(token).ConfigureAwait(false);
        return new
        {
            note = FilesNote(game),
            totalBytes = details.Files.TotalSize,
            files = details.Files.Files.Select(file => new
            {
                path = file.RelativePath.Replace('\\', '/'),
                size = file.Size,
                origin = file.Origin,
                encrypted = file.IsEncrypted
            }).ToList()
        };
    }

    /// <summary>Identifies a file and returns what the viewer should show: image, text, media or hex.</summary>
    public async Task<object> PreviewAsync(Ps5GameInfo game, string relativePath, int maxPreviewMb, CancellationToken token)
    {
        string path = GameFileSystem.NormalizePath(relativePath);
        string extension = Path.GetExtension(path).ToLowerInvariant();
        GameFileChunk head = await Task.Run(() => GameFileSystem.ReadFileChunk(game, path, 0, 64, token), token).ConfigureAwait(false);
        long size = head.FileSize;
        AssetInspection inspection = size == 0 ? AssetInspection.Unknown("Empty file") : AssetInspector.Inspect(path, head.Data);
        var info = new
        {
            path,
            name = Path.GetFileName(path),
            size,
            sizeText = GameClassifier.FormatBytes(size),
            category = inspection.Category.ToString(),
            format = inspection.Format,
            description = inspection.Description,
            metadata = inspection.Metadata.Select(item => new { name = item.Name, value = item.Value }).ToList()
        };
        long limit = Math.Max(1, maxPreviewMb) * 1024L * 1024L;

        if (IsImage(extension, inspection) && size <= Math.Max(limit, 256L * 1024 * 1024))
        {
            string cached = await ExtractToPreviewAsync(game, path, size, token).ConfigureAwait(false);
            if (extension == ".dds" || inspection.Format.Contains("DDS", StringComparison.OrdinalIgnoreCase))
            {
                string png = cached + ".png";
                if (!File.Exists(png))
                {
                    await using FileStream input = File.OpenRead(cached);
                    byte[] decoded = Ps5ImageCodec.DecodeDdsToPng(input);
                    await File.WriteAllBytesAsync(png, decoded, token).ConfigureAwait(false);
                }
                cached = png;
            }
            return new { kind = "image", info, file = cached };
        }

        if (IsMedia(extension, inspection))
            return new { kind = "media", info, file = string.Empty };

        if (size <= limit)
        {
            const int maximumText = 1024 * 1024;
            GameFileChunk chunk = await Task.Run(() => GameFileSystem.ReadFileChunk(game, path, 0, (int)Math.Min(size, maximumText), token), token)
                .ConfigureAwait(false);
            if (TryDecodeText(chunk.Data, out string text))
            {
                if (extension == ".json") text = PrettyJson(text);
                return new { kind = "text", info, text, truncated = chunk.HasNext };
            }
        }
        return new { kind = "hex", info, file = string.Empty };
    }

    /// <summary>Extracts a file into the preview cache for media playback or "open with".</summary>
    public async Task<string> ExtractToPreviewAsync(Ps5GameInfo game, string relativePath, long size, CancellationToken token)
    {
        string path = GameFileSystem.NormalizePath(relativePath);
        if (game.SourceKind == Ps5SourceKind.LooseDump)
        {
            string direct = Path.Combine(game.RootPath, path.Replace('/', Path.DirectorySeparatorChar));
            if (File.Exists(direct)) return direct;
        }
        string key = Convert.ToHexString(SHA1.HashData(Encoding.UTF8.GetBytes($"{game.RootPath}|{game.LastWriteTimeUtc.Ticks}|{path}")))
            .ToLowerInvariant();
        string directory = Path.Combine(AppPaths.PreviewDirectory, key[..2]);
        string target = Path.Combine(directory, key + Path.GetExtension(path));
        if (File.Exists(target) && (size < 0 || new FileInfo(target).Length == size)) return target;
        Directory.CreateDirectory(directory);
        string partial = target + ".partial";
        await GameFileSystem.ExtractFileAsync(game, path, partial, null, token).ConfigureAwait(false);
        File.Move(partial, target, overwrite: true);
        return target;
    }

    public static async Task<object> HexPageAsync(Ps5GameInfo game, string relativePath, long offset, int pageBytes, CancellationToken token)
    {
        GameFileChunk chunk = await Task.Run(() => GameFileSystem.ReadFileChunk(game, GameFileSystem.NormalizePath(relativePath),
            Math.Max(0, offset), Math.Clamp(pageBytes, 256, 256 * 1024), token), token).ConfigureAwait(false);
        var output = new StringBuilder(Math.Max(128, chunk.Data.Length * 5));
        for (int row = 0; row < chunk.Data.Length; row += 16)
        {
            int count = Math.Min(16, chunk.Data.Length - row);
            output.Append((chunk.Offset + row).ToString("X10", CultureInfo.InvariantCulture)).Append("  ");
            for (int column = 0; column < 16; column++)
            {
                output.Append(column < count ? chunk.Data[row + column].ToString("X2", CultureInfo.InvariantCulture) : "  ");
                output.Append(column == 7 ? "  " : " ");
            }
            output.Append(" ");
            for (int column = 0; column < count; column++)
            {
                byte value = chunk.Data[row + column];
                output.Append(value is >= 0x20 and <= 0x7E ? (char)value : '·');
            }
            output.Append('\n');
        }
        return new
        {
            text = output.ToString(),
            offset = chunk.Offset,
            length = chunk.Data.Length,
            fileSize = chunk.FileSize,
            hasPrevious = chunk.HasPrevious,
            hasNext = chunk.HasNext
        };
    }

    private static bool IsImage(string extension, AssetInspection inspection) =>
        extension is ".dds" or ".png" or ".jpg" or ".jpeg" or ".bmp" or ".gif" or ".webp" ||
        inspection.Category == AssetCategory.Image;

    private static bool IsMedia(string extension, AssetInspection inspection) =>
        extension is ".mp3" or ".wav" or ".aac" or ".m4a" or ".flac" or ".mp4" or ".m4v" or ".mov" or ".avi" or
            ".mpeg" or ".mpg" or ".webm" or ".mkv" or ".ogg" or ".oga" or ".opus" or ".3gp" or ".ts" or ".m2ts" or ".at9" ||
        inspection.Category is AssetCategory.Audio or AssetCategory.Video;

    private static bool TryDecodeText(byte[] data, out string text)
    {
        text = string.Empty;
        try
        {
            text = new UTF8Encoding(false, true).GetString(data);
        }
        catch (DecoderFallbackException)
        {
            return false;
        }
        if (text.Length == 0) return true;
        int invalid = text.Count(character => char.IsControl(character) && character is not '\r' and not '\n' and not '\t' and not '\f' and not '\b');
        return invalid <= Math.Max(1, text.Length / 100);
    }

    private static string PrettyJson(string text)
    {
        try
        {
            using JsonDocument document = JsonDocument.Parse(text);
            return JsonSerializer.Serialize(document.RootElement, new JsonSerializerOptions
            {
                WriteIndented = true,
                Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
            });
        }
        catch (JsonException)
        {
            return text;
        }
    }
}
