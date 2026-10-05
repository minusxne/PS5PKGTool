using PS5PKGTool.Bridge.Tools;
using PS5PKGTool.Core.Backends;
using PS5PKGTool.Core.Builders;
using PS5PKGTool.Core.Services;
using PS5PKGTool.Core.Tasks;
using PS5PKGTool.Ffpfsc;
using Xunit.Abstractions;

namespace PS5PKGTool.Bridge.Tests;

/// <summary>
/// End-to-end round trips on a synthetic dump, through the same operations the task queue runs:
/// pack into each image format, verify, extract, and compare every byte with the original.
/// </summary>
public class PipelineTests(ITestOutputHelper output)
{
    private static readonly IProgress<PackageTaskProgress> NoProgress = new Library.InlineProgress<PackageTaskProgress>(_ => { });

    [Theory]
    [InlineData(Ps5ImageConversionTarget.Exfat, Ps5ImageFormat.Exfat, ".exfat")]
    [InlineData(Ps5ImageConversionTarget.Ffpkg, Ps5ImageFormat.Ufs2, ".ffpkg")]
    [InlineData(Ps5ImageConversionTarget.Ffpfsc, Ps5ImageFormat.Pfs, ".ffpfsc")]
    public async Task Dump_converts_verifies_and_extracts_byte_identical(Ps5ImageConversionTarget target, Ps5ImageFormat format,
        string extension)
    {
        string work = TestEnvironment.NewDirectory("convert-" + target);
        string dump = SyntheticDump.Create(work);
        string image = Path.Combine(work, "out" + extension);

        await Operations.ConvertAsync(dump, image, target, overwrite: false, fromPackage: false,
            target == Ps5ImageConversionTarget.Ffpkg ? null : new ExfatBuildOptions(),
            target == Ps5ImageConversionTarget.Ffpfsc ? new FfpfscBuildOptions() : null,
            target == Ps5ImageConversionTarget.Ffpkg ? new FfpkgBuildOptions() : null,
            NoProgress, CancellationToken.None);
        Assert.True(File.Exists(image));
        Assert.Equal(format, Ps5ImageFormatProbe.Detect(image));

        await Operations.VerifyImageAsync(image, format, NoProgress, CancellationToken.None);

        string extracted = Path.Combine(work, "extracted");
        await Operations.ExtractImageAsync(image, format, extracted, NoProgress, CancellationToken.None);
        SyntheticDump.AssertTreesEqual(dump, extracted);

        // The content ID used for package builds is read straight from the image.
        Assert.Equal("UP9999-PPSA99999_00-SYNTHETICTEST000", Operations.ReadParamFields(image, format).ContentId);
    }

    public static TheoryData<string> Backends() => [BackendRegistry.PptId, BackendRegistry.LppId];

    [Theory]
    [MemberData(nameof(Backends))]
    public async Task Dump_builds_a_debug_package_that_reads_back(string backendId)
    {
        if (backendId == BackendRegistry.LppId && !LppBackend.IsAvailable)
        {
            output.WriteLine("LibProsperoPkg unavailable: " + LppBackend.UnavailableReason);
            return;
        }
        string work = TestEnvironment.NewDirectory("build-" + backendId);
        string dump = SyntheticDump.Create(work);
        string package = Path.Combine(work, "UP9999-PPSA99999_00-SYNTHETICTEST000.pkg");
        var settings = new PackageBuildSettings(Ps5InnerCompression.Auto, 7, 0, backendId == BackendRegistry.LppId ? 64 : 1,
            "upgradable", Deterministic: true, FakeSignModules: true, InjectRightSprx: true);

        await Operations.BuildPackageAsync(dump, package, "UP9999-PPSA99999_00-SYNTHETICTEST000",
            SonyDebugPackageCredentials.DefaultPasscode, overwrite: false, null, work, settings,
            BackendRegistry.Get(backendId), NoProgress, CancellationToken.None);
        Assert.True(File.Exists(package));
        Assert.Empty(Directory.EnumerateDirectories(work, ".ps5pkgtool-*"));

        await Operations.VerifyPackageAsync(package, SonyDebugPackageCredentials.DefaultPasscode, NoProgress, CancellationToken.None);

        string extracted = Path.Combine(work, "extracted");
        await SonyPackageExtraction.ExtractAsync(package, extracted, SonyDebugPackageCredentials.DefaultPasscode, null, CancellationToken.None);
        // Builders fake-sign executables (ELF in, fSELF out), so eboot.bin changes by design.
        byte[] eboot = File.ReadAllBytes(Path.Combine(extracted, "eboot.bin"));
        Assert.False(eboot.AsSpan(0, 4).SequenceEqual("\u007FELF"u8), "eboot.bin was not fake-signed");
        foreach (string file in new[] { "data/readme.txt", "data/nested/file00.bin", "data/file01.bin" })
            Assert.True(File.ReadAllBytes(Path.Combine(dump, file)).AsSpan()
                .SequenceEqual(File.ReadAllBytes(Path.Combine(extracted, file))), "Content differs: " + file);
    }

    [Fact]
    public async Task Debug_package_converts_to_an_image()
    {
        string work = TestEnvironment.NewDirectory("pkg-to-image");
        string dump = SyntheticDump.Create(work);
        string package = Path.Combine(work, "test.pkg");
        await Operations.BuildPackageAsync(dump, package, "UP9999-PPSA99999_00-SYNTHETICTEST000",
            SonyDebugPackageCredentials.DefaultPasscode, false, null, work,
            new PackageBuildSettings(Ps5InnerCompression.Stored, 7, 0, 1, null, true, true, true),
            BackendRegistry.Get(BackendRegistry.PptId), NoProgress, CancellationToken.None);

        string image = Path.Combine(work, "from-pkg.exfat");
        await Operations.ConvertAsync(package, image, Ps5ImageConversionTarget.Exfat, false, fromPackage: true,
            new ExfatBuildOptions(), null, null, NoProgress, CancellationToken.None);
        await Operations.VerifyImageAsync(image, Ps5ImageFormat.Exfat, NoProgress, CancellationToken.None);
        string extracted = Path.Combine(work, "extracted");
        await Operations.ExtractImageAsync(image, Ps5ImageFormat.Exfat, extracted, NoProgress, CancellationToken.None);
        Assert.True(File.Exists(Path.Combine(extracted, "eboot.bin")));
    }
}
