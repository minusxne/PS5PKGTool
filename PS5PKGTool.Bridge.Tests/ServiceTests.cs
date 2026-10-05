using System.IO.Pipelines;
using System.Text;
using System.Text.Json;
using PS5PKGTool.Bridge.Details;
using PS5PKGTool.Bridge.Library;
using PS5PKGTool.Bridge.Protocol;
using PS5PKGTool.Bridge.Tasks;

namespace PS5PKGTool.Bridge.Tests;

/// <summary>The services wired the way the bridge wires them, over a real temporary library.</summary>
public sealed class ServiceTests : IAsyncLifetime
{
    private readonly RpcServer _server = new(Stream.Null);
    private BridgeState _state = null!;
    private LibraryService _library = null!;
    private TaskService _tasks = null!;
    private string _libraryRoot = null!;

    public Task InitializeAsync()
    {
        _state = new BridgeState(_server);
        _state.ReplaceSettings(new Infrastructure.AppSettings());
        _library = new LibraryService(_state, new ArtworkCache());
        _tasks = new TaskService(_state, _library.Find);
        _libraryRoot = TestEnvironment.NewDirectory("library");
        return Task.CompletedTask;
    }

    public async Task DisposeAsync() => await _tasks.DisposeAsync();

    [Fact]
    public async Task Scan_finds_dumps_and_rows_are_classified()
    {
        SyntheticDump.Create(_libraryRoot, "PPSA10001", "Base Game");
        SyntheticDump.Create(_libraryRoot, "PPSA10001", "Base Game", category: "gp", contentVersion: "01.001.000");
        SyntheticDump.Create(_libraryRoot, "PPSA10002", "Other Game", region: "EP");

        _library.AddFolder(_libraryRoot);
        await _library.ScanAsync(null, merge: false, CancellationToken.None);

        IReadOnlyList<GameRow> rows = _library.Rows();
        Assert.Equal(3, rows.Count);
        GameRow patch = rows.Single(row => row.Category == "Patch");
        Assert.Equal("Update", patch.Role);
        Assert.Equal("Base Game", patch.Title);
        Assert.Equal("Dump Files", patch.Format);
        Assert.Contains(rows, row => row.Region == "Europe");

        LibraryViewResult view = _library.View(new LibraryViewRequest { GroupBy = "family" });
        Assert.Equal(2, view.Groups.Count);
    }

    [Fact]
    public async Task Details_include_overview_artwork_and_files()
    {
        string dump = SyntheticDump.Create(_libraryRoot, "PPSA10003", "Detail Game");
        _library.AddSource(dump);
        await _library.ScanAsync([dump], merge: true, CancellationToken.None);
        var details = new DetailsService(_library);

        object result = await details.GetAsync(_library.Require(dump), CancellationToken.None);
        using JsonDocument document = JsonDocument.Parse(JsonSerializer.Serialize(result, Json.Options));
        JsonElement root = document.RootElement;
        Assert.Contains(root.GetProperty("overview").EnumerateArray(), group => group.GetProperty("title").GetString() == "Identity");
        string icon = root.GetProperty("artwork")[0].GetProperty("path").GetString()!;
        Assert.True(File.Exists(icon));
        Assert.True(root.GetProperty("files").GetProperty("count").GetInt32() >= 8);

        object preview = await details.PreviewAsync(_library.Require(dump), "data/readme.txt", 16, CancellationToken.None);
        using JsonDocument previewDocument = JsonDocument.Parse(JsonSerializer.Serialize(preview, Json.Options));
        Assert.Equal("text", previewDocument.RootElement.GetProperty("kind").GetString());

        object hex = await DetailsService.HexPageAsync(_library.Require(dump), "eboot.bin", 0, 256, CancellationToken.None);
        Assert.Contains("7F 45 4C 46", JsonSerializer.Serialize(hex, Json.Options));
    }

    [Fact]
    public async Task Rename_plan_previews_and_applies()
    {
        string dump = SyntheticDump.Create(_libraryRoot, "PPSA10004", "Rename: Me?");
        _library.AddFolder(_libraryRoot);
        await _library.ScanAsync(null, merge: false, CancellationToken.None);
        var organizer = new Organizer(_state, _library, _tasks);

        List<OrganizePlanItem> plan = organizer.PlanRename([_library.Require(dump)], "{TITLE} [{TITLE_ID}]", installOrder: false);
        OrganizePlanItem item = Assert.Single(plan);
        Assert.Equal("rename", item.Status);
        Assert.Equal("Rename_ Me_ [PPSA10004]", item.TargetName);

        organizer.ApplyRename([_library.Require(dump)], "{TITLE} [{TITLE_ID}]", installOrder: false);
        Assert.True(Directory.Exists(item.Target));
        Assert.NotNull(_library.Find(item.Target));
        Assert.Null(_library.Find(dump));
    }

    [Fact]
    public async Task Queued_conversion_runs_to_completion_through_the_task_queue()
    {
        string dump = SyntheticDump.Create(_libraryRoot, "PPSA10005", "Queued Game");
        string output = Path.Combine(_libraryRoot, "queued.exfat");
        var finished = new TaskCompletionSource<Core.Tasks.QueuedPackageTask>();
        _tasks.Enqueue(Core.Tasks.PackageTaskTypes.ImageConvert,
            new TaskPayload().With("source", dump).With("output", output).With("target", "Exfat").With("ampr", true),
            task => finished.TrySetResult(task));
        Core.Tasks.QueuedPackageTask done = await finished.Task.WaitAsync(TimeSpan.FromMinutes(2));
        Assert.Equal(Core.Tasks.PackageTaskStatus.Completed, done.Status);
        TaskSnapshot snapshot = _tasks.Snapshot().Single(task => task.Id == done.Id);
        Assert.Equal(1d, snapshot.TaskPercent);
        Assert.True(snapshot.OutputExists);
        Assert.Equal("dump → exFAT", snapshot.Route);
    }

    [Fact]
    public async Task Rpc_server_answers_requests_and_reports_errors()
    {
        var input = new Pipe();
        var output = new MemoryStream();
        var server = new RpcServer(output);
        server.Register("echo", request => new { value = request.Str("value") });
        Task run = server.RunAsync(input.Reader.AsStream());

        await input.Writer.WriteAsync(Encoding.UTF8.GetBytes(
            "{\"id\":1,\"method\":\"echo\",\"params\":{\"value\":\"hi\"}}\n{\"id\":2,\"method\":\"nope\"}\nnot json\n"));
        await Task.Delay(300);
        await input.Writer.CompleteAsync();
        await run.WaitAsync(TimeSpan.FromSeconds(5));

        string[] lines = Encoding.UTF8.GetString(output.ToArray()).Split('\n', StringSplitOptions.RemoveEmptyEntries);
        Assert.Contains(lines, line => line.Contains("\"id\":1") && line.Contains("\"value\":\"hi\""));
        Assert.Contains(lines, line => line.Contains("\"id\":2") && line.Contains("unknown_method"));
        Assert.Contains(lines, line => line.Contains("parse_error"));
    }
}
