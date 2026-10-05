using PS5PKGTool.Bridge.Library;
using PS5PKGTool.Bridge.Protocol;
using PS5PKGTool.Bridge.Tools;
using PS5PKGTool.Core.Models;

namespace PS5PKGTool.Bridge.Tests;

public class LibraryLogicTests
{
    private static readonly Ps5GameInfo[] Sample =
    [
        SyntheticDump.Game("PPSA00001", "0", "01.000.000", size: 50L << 30),
        SyntheticDump.Game("PPSA00001", "2", "01.002.000", size: 2L << 30),
        SyntheticDump.Game("PPSA00001", "2", "01.010.000", size: 3L << 30),
        SyntheticDump.Game("PPSA00002", "1", "01.000.000", contentId: "EP9999-PPSA00002_00-DLC0000000000000", size: 1L << 20),
        SyntheticDump.Game("PPSA00003", "2", "01.001.000", contentId: "JP9999-PPSA00003_00-PATCH00000000000"),
    ];

    [Theory]
    [InlineData("0", "Game")]
    [InlineData("2", "Patch")]
    [InlineData("1", "DLC")]
    [InlineData("3", "App")]
    [InlineData("16777216", "Game")]
    public void Category_follows_the_application_category(string raw, string expected) =>
        Assert.Equal(expected, GameClassifier.CategoryOf(SyntheticDump.Game("PPSA00001", raw)));

    [Fact]
    public void Region_comes_from_the_content_id_prefix()
    {
        Assert.Equal("Americas", GameClassifier.RegionOf(Sample[0]));
        Assert.Equal("Europe", GameClassifier.RegionOf(Sample[3]));
        Assert.Equal("Japan", GameClassifier.RegionOf(Sample[4]));
    }

    [Fact]
    public void Older_updates_are_marked_superseded_and_lonely_patches_lack_a_base()
    {
        var family = new FamilyIndex(Sample);
        Assert.Equal("Update (older)", family.RoleOf(Sample[1]));
        Assert.Equal("Update", family.RoleOf(Sample[2]));
        Assert.False(family.IsMissingBase(Sample[2]));
        Assert.True(family.IsMissingBase(Sample[4]));
    }

    [Theory]
    [InlineData("", 5)]
    [InlineData("category:patch", 3)]
    [InlineData("category:patch|dlc", 4)]
    [InlineData("-category:patch", 2)]
    [InlineData("id:=PPSA00001", 3)]
    [InlineData("id:PPSA0000", 5)]
    [InlineData("size:>10GB", 1)]
    [InlineData("size:<=2GB", 3)]
    [InlineData("version:>=1.2", 2)]
    [InlineData("role:older", 1)]
    [InlineData("region:europe", 1)]
    [InlineData("\"Title PPSA00002\"", 1)]
    public void Query_grammar_matches_like_the_windows_edition(string query, int expected)
    {
        var family = new FamilyIndex(Sample);
        var parsed = new LibraryQuery(query);
        Assert.Equal(expected, Sample.Count(game => parsed.Matches(game, family)));
    }

    [Theory]
    [InlineData("title:\"open", "Unbalanced")]
    [InlineData("colour:red", "Unknown field")]
    [InlineData("size:big", "not a valid size")]
    [InlineData("fw:>=", "missing a value")]
    public void Invalid_queries_get_a_hint(string query, string fragment) =>
        Assert.Contains(fragment, LibraryQuery.Validate(query) ?? string.Empty, StringComparison.OrdinalIgnoreCase);

    [Fact]
    public void Valid_queries_have_no_hint() => Assert.Null(LibraryQuery.Validate("title:astro size:>1GB fw:<=7.00 -drm:free"));

    [Fact]
    public void Versions_sort_numerically()
    {
        Assert.True(VersionKey.Parse("1.10").CompareTo(VersionKey.Parse("1.9")) > 0);
        Assert.Equal(-1, GameClassifier.CompareVersions("01.002", "1.10"));
    }

    [Fact]
    public void Family_grouping_orders_base_then_newest_update()
    {
        LibraryViewResult view = LibraryView.Build(Sample, new FamilyIndex(Sample), new LibraryViewRequest { GroupBy = "family" });
        LibraryViewGroup first = view.Groups[0];
        Assert.Equal("PPSA00001", first.Key);
        Assert.Equal([Sample[0].RootPath, Sample[2].RootPath, Sample[1].RootPath], first.Ids);
        Assert.Equal(view.Groups.SelectMany(group => group.Ids), view.Ids);
    }

    [Fact]
    public void Multi_key_sort_and_filters_combine()
    {
        LibraryViewResult view = LibraryView.Build(Sample, new FamilyIndex(Sample), new LibraryViewRequest
        {
            Categories = ["Patch"],
            SortKeys = ["Size:desc"]
        });
        Assert.Equal([Sample[2].RootPath, Sample[1].RootPath, Sample[4].RootPath], view.Ids);
        Assert.Empty(view.Groups);
        Assert.Equal(5, view.TotalCount);
    }

    [Fact]
    public void Size_text_parses_both_unit_styles()
    {
        Assert.True(LibraryQuery.TryParseSize("1.5GB", out long gb));
        Assert.True(LibraryQuery.TryParseSize("1.5GiB", out long gib));
        Assert.Equal(gb, gib);
    }

    [Theory]
    [InlineData("/out/game.exfat", "exfat")]
    [InlineData("/out/game.FFPKG", "ffpkg")]
    [InlineData("/out/game.ffpfsc", "ffpfsc")]
    [InlineData("/out/game.pkg", "pkg")]
    [InlineData("/out/game.img", "ffpkg")]
    [InlineData("/out/game", "exfat")]
    public void Output_extension_matching_the_target_or_unknown_is_accepted(string output, string target) =>
        ToolsService.CheckOutputExtension(output, target);

    [Theory]
    [InlineData("/out/game.exfat", "ffpkg")]
    [InlineData("/out/game.ffpkg", "exfat")]
    [InlineData("/out/game.exfat", "ffpfsc")]
    [InlineData("/out/game.ffpfsc", "pkg")]
    public void Output_named_for_another_format_is_refused(string output, string target)
    {
        RpcException error = Assert.Throws<RpcException>(() => ToolsService.CheckOutputExtension(output, target));
        Assert.Equal("bad_request", error.Code);
    }
}
