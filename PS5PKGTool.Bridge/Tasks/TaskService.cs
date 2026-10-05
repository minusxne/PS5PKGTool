using System.Collections.Concurrent;
using System.Text;
using PS5PKGTool.Bridge.Infrastructure;
using PS5PKGTool.Bridge.Library;
using PS5PKGTool.Bridge.Protocol;
using PS5PKGTool.Core.Backends;
using PS5PKGTool.Core.Services;
using PS5PKGTool.Core.Tasks;

namespace PS5PKGTool.Bridge.Tasks;

/// <summary>A task as the UI renders it.</summary>
public sealed record TaskSnapshot(
    string Id,
    string Type,
    string Title,
    string Operation,
    string Route,
    string SourcePath,
    string SourceName,
    string OutputPath,
    string OutputName,
    string Status,
    string Stage,
    string StepText,
    double StepPercent,
    double TaskPercent,
    string Message,
    string CurrentFile,
    string Counts,
    string Elapsed,
    string Eta,
    string Result,
    int Attempts,
    int QueuePosition,
    DateTime CreatedUtc,
    DateTime? StartedUtc,
    DateTime? CompletedUtc,
    bool CanCancel,
    bool CanRetry,
    bool CanRemove,
    bool OutputExists,
    string Builder,
    bool Restorable);

/// <summary>
/// The sequential task queue (one long operation at a time), persisted to <c>tasks.json</c> and
/// restored on start. State changes are pushed as throttled <c>tasks.changed</c> snapshots and a
/// <c>task.finished</c> event per finished task.
/// </summary>
public sealed class TaskService : IAsyncDisposable
{
    private readonly BridgeState _state;
    private readonly PackageTaskQueue _queue = new();
    private readonly TaskCatalog _catalog;
    private readonly ConcurrentDictionary<string, Action<QueuedPackageTask>> _finishers = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, PackageTaskStatus> _lastStatus = new(StringComparer.Ordinal);
    private readonly Timer _pump;
    private int _dirty;

    public TaskService(BridgeState state, Func<string, Core.Models.Ps5GameInfo?> findGame)
    {
        _state = state;
        _catalog = new TaskCatalog(findGame);
        _queue.TasksChanged += (_, _) => MarkDirty();
        _pump = new Timer(_ => Flush(), null, TimeSpan.FromMilliseconds(250), TimeSpan.FromMilliseconds(250));
    }

    public bool AutoStart
    {
        get => _queue.AutoStart;
        set
        {
            _queue.AutoStart = value;
            MarkDirty();
        }
    }

    public void Restore()
    {
        int restored = _queue.RestoreFromDisk(entry =>
        {
            TaskPayload fields = TaskPayload.Parse(entry.Payload);
            TaskCatalog.Descriptor? descriptor = _catalog.Create(entry.Type, fields);
            var task = new QueuedPackageTask
            {
                Id = entry.Id,
                Type = entry.Type,
                DisplayName = entry.DisplayName,
                SourcePath = entry.SourcePath,
                OutputPath = entry.OutputPath,
                PersistencePayload = entry.Payload,
                Operation = entry.Operation,
                SourceFormat = entry.SourceFormat,
                TargetFormat = entry.TargetFormat,
                TargetQualifier = entry.TargetQualifier,
                StagePlan = descriptor?.Plan ?? [],
                Execute = descriptor?.Execute,
                CreatedUtc = entry.CreatedUtc == default ? DateTime.UtcNow : entry.CreatedUtc
            };
            Watch(task);
            return task;
        });
        _queue.EnablePersistence(AppPaths.TaskQueuePath);
        if (restored > 0) Logger.Info($"Restored {restored:N0} task(s) from the previous session.");
    }

    /// <summary>Queues a restorable task described by its payload.</summary>
    public QueuedPackageTask Enqueue(string type, TaskPayload payload, Action<QueuedPackageTask>? onFinished = null)
    {
        TaskCatalog.Descriptor descriptor = _catalog.Create(type, payload)
            ?? throw RpcException.BadRequest("That task could not be created from the given options.");
        if (descriptor.Execute is null) throw RpcException.BadRequest("That task has nothing to run.");
        var task = new QueuedPackageTask
        {
            Id = Guid.NewGuid().ToString("N"),
            Type = descriptor.Type,
            DisplayName = descriptor.DisplayName,
            SourcePath = descriptor.SourcePath,
            OutputPath = descriptor.OutputPath,
            PersistencePayload = payload.Serialize(),
            Operation = descriptor.Operation,
            SourceFormat = descriptor.SourceFormat,
            TargetFormat = descriptor.TargetFormat,
            TargetQualifier = descriptor.TargetQualifier,
            StagePlan = descriptor.Plan,
            Execute = descriptor.Execute
        };
        return Add(task, onFinished);
    }

    /// <summary>Queues a one-off task that cannot be restored after a restart (for example a move).</summary>
    public QueuedPackageTask EnqueueTransient(string type, string displayName,
        Func<IProgress<PackageTaskProgress>, CancellationToken, Task> execute, string outputPath, string operation,
        string sourceFormat, string targetFormat, Action<QueuedPackageTask>? onFinished = null)
    {
        var task = new QueuedPackageTask
        {
            Id = Guid.NewGuid().ToString("N"),
            Type = type,
            DisplayName = displayName,
            OutputPath = outputPath,
            Operation = operation,
            SourceFormat = sourceFormat,
            TargetFormat = targetFormat,
            StagePlan = PackageTaskPlans.Single,
            Execute = execute
        };
        return Add(task, onFinished);
    }

    private QueuedPackageTask Add(QueuedPackageTask task, Action<QueuedPackageTask>? onFinished)
    {
        if (onFinished is not null) _finishers[task.Id] = onFinished;
        Watch(task);
        _queue.Enqueue(task);
        Logger.Info($"Queued task: {task.DisplayName}");
        _state.Server.Emit("task.queued", new { id = task.Id, title = task.DisplayName });
        MarkDirty();
        return task;
    }

    private void Watch(QueuedPackageTask task)
    {
        _lastStatus[task.Id] = task.Status;
        task.Changed += (_, _) =>
        {
            MarkDirty();
            PackageTaskStatus previous = _lastStatus.GetValueOrDefault(task.Id, PackageTaskStatus.Queued);
            if (previous == task.Status) return;
            _lastStatus[task.Id] = task.Status;
            OnStatusChanged(task);
        };
    }

    private void OnStatusChanged(QueuedPackageTask task)
    {
        switch (task.Status)
        {
            case PackageTaskStatus.Running:
                Logger.Info($"Task started: {task.DisplayName}");
                break;
            case PackageTaskStatus.Completed:
                Logger.Info($"Task completed: {task.DisplayName}");
                break;
            case PackageTaskStatus.Failed:
                Logger.Error($"Task failed: {task.DisplayName}: {task.Message}");
                if (task.Failure is not null) Logger.Error(task.Failure.ToString());
                break;
            case PackageTaskStatus.Cancelled:
                Logger.Warn($"Task cancelled: {task.DisplayName}");
                break;
        }
        if (!task.IsTerminal) return;
        if (_finishers.TryRemove(task.Id, out Action<QueuedPackageTask>? finisher))
        {
            try { finisher(task); }
            catch (Exception ex) { Logger.Exception("Task completion handler failed", ex); }
        }
        Flush();
        _state.Server.Emit("task.finished", new
        {
            id = task.Id,
            title = task.DisplayName,
            status = task.Status.ToString(),
            message = FriendlyMessage(task),
            outputPath = task.OutputPath,
            diskSpace = task.Failure is not null && Ps5DiskSpace.IsInsufficient(task.Failure),
            openOutput = task.Status == PackageTaskStatus.Completed && _state.Settings.OpenOutputAfterTask
        });
    }

    public QueuedPackageTask Require(string id) =>
        _queue.Find(id) ?? throw RpcException.NotFound("That task no longer exists.");

    public bool Cancel(string id) => _queue.Cancel(id);
    public bool Retry(string id) => _queue.Retry(id);
    public bool Remove(string id) => _queue.Remove(id);
    public int ClearCompleted() => _queue.ClearCompleted();
    public void StartNext() => _queue.StartNext();

    public int CancelAll()
    {
        int count = 0;
        foreach (QueuedPackageTask task in _queue.Tasks)
            if (task.Status is PackageTaskStatus.Running or PackageTaskStatus.Queued && _queue.Cancel(task.Id))
                count++;
        return count;
    }

    /// <summary>True when a queued or running task reads from or writes to the path (or under it).</summary>
    public bool IsPathBusy(string path)
    {
        foreach (QueuedPackageTask task in _queue.Tasks)
        {
            if (task.Status is not (PackageTaskStatus.Queued or PackageTaskStatus.Running or PackageTaskStatus.Cancelling))
                continue;
            if (PathTouches(path, task.SourcePath) || PathTouches(path, task.OutputPath)) return true;
        }
        return false;
    }

    private static bool PathTouches(string left, string right)
    {
        if (string.IsNullOrWhiteSpace(left) || string.IsNullOrWhiteSpace(right)) return false;
        string a = Path.GetFullPath(left).TrimEnd(Path.DirectorySeparatorChar);
        string b = Path.GetFullPath(right).TrimEnd(Path.DirectorySeparatorChar);
        return a.Equals(b, StringComparison.Ordinal) ||
               a.StartsWith(b + Path.DirectorySeparatorChar, StringComparison.Ordinal) ||
               b.StartsWith(a + Path.DirectorySeparatorChar, StringComparison.Ordinal);
    }

    public IReadOnlyList<TaskSnapshot> Snapshot()
    {
        IReadOnlyList<QueuedPackageTask> tasks = _queue.Tasks;
        var positions = new Dictionary<string, int>(StringComparer.Ordinal);
        int position = 0;
        foreach (QueuedPackageTask task in tasks)
            if (task.Status == PackageTaskStatus.Queued) positions[task.Id] = ++position;
        return tasks.Select(task => ToSnapshot(task, positions.GetValueOrDefault(task.Id))).ToList();
    }

    public object Summary()
    {
        IReadOnlyList<QueuedPackageTask> tasks = _queue.Tasks;
        QueuedPackageTask? running = tasks.FirstOrDefault(task => task.Status is PackageTaskStatus.Running or PackageTaskStatus.Cancelling);
        return new
        {
            running = tasks.Count(task => task.Status is PackageTaskStatus.Running or PackageTaskStatus.Cancelling),
            waiting = tasks.Count(task => task.Status == PackageTaskStatus.Queued),
            attention = tasks.Count(task => task.Status is PackageTaskStatus.Failed or PackageTaskStatus.Interrupted),
            finished = tasks.Count(task => task.Status == PackageTaskStatus.Completed),
            total = tasks.Count,
            autoStart = _queue.AutoStart,
            activeTitle = running?.DisplayName ?? string.Empty,
            activePercent = running is null ? 0d : running.Progress.TaskPercent
        };
    }

    private TaskSnapshot ToSnapshot(QueuedPackageTask task, int queuePosition)
    {
        PackageTaskProgress progress = task.Progress;
        bool busy = task.Status is PackageTaskStatus.Running or PackageTaskStatus.Cancelling;
        string stepText = progress.TotalSteps > 0
            ? $"Step {Math.Min(progress.Step + 1, progress.TotalSteps)} of {progress.TotalSteps}"
            : string.Empty;
        string output = task.OutputPath;
        bool outputExists = output.Length > 0 && (File.Exists(output) || Directory.Exists(output));
        TaskPayload payload = TaskPayload.Parse(task.PersistencePayload);
        string builder = payload.Get("backend") is { Length: > 0 } backend
            ? task.TargetQualifier.Length > 0 ? task.TargetQualifier : BackendRegistry.Get(backend).DisplayName
            : string.Empty;
        return new TaskSnapshot(
            task.Id,
            task.Type,
            task.DisplayName,
            task.Operation.Length > 0 ? task.Operation : task.Type,
            task.FormatRoute,
            task.SourcePath,
            Path.GetFileName(task.SourcePath.TrimEnd('/')),
            output,
            Path.GetFileName(output.TrimEnd('/')),
            task.Status.ToString(),
            string.IsNullOrWhiteSpace(progress.Stage) ? string.Empty : progress.Stage,
            stepText,
            task.Status == PackageTaskStatus.Completed ? 1d : Math.Clamp(progress.OperationPercent, 0d, 1d),
            task.Status == PackageTaskStatus.Completed ? 1d : Math.Clamp(progress.TaskPercent, 0d, 1d),
            FriendlyMessage(task),
            progress.CurrentFile,
            CountsText(progress),
            ElapsedText(task),
            EtaText(task) ?? string.Empty,
            ResultText(task, outputExists),
            task.Attempts,
            queuePosition,
            task.CreatedUtc,
            task.StartedUtc,
            task.CompletedUtc,
            task.Status is PackageTaskStatus.Queued or PackageTaskStatus.Running,
            task.Execute is not null &&
            task.Status is PackageTaskStatus.Failed or PackageTaskStatus.Cancelled or PackageTaskStatus.Interrupted,
            !busy,
            outputExists,
            builder,
            task.Execute is not null);
    }

    /// <summary>The failure message without the exception type prefix the queue adds.</summary>
    private static string FriendlyMessage(QueuedPackageTask task)
    {
        if (task.Status == PackageTaskStatus.Failed && task.Failure is { } failure)
            return Ps5DiskSpace.IsInsufficient(failure) ? Ps5DiskSpace.Describe(failure) : failure.Message;
        return task.Message;
    }

    private static string ResultText(QueuedPackageTask task, bool outputExists)
    {
        string stage = string.IsNullOrWhiteSpace(task.Progress.Stage) ? string.Empty : $" at {task.Progress.Stage}";
        return task.Status switch
        {
            PackageTaskStatus.Completed => outputExists ? "Completed. Output: " + task.OutputPath : "Completed.",
            PackageTaskStatus.Failed => $"Failed{stage}: {FriendlyMessage(task)}",
            PackageTaskStatus.Cancelled => "Cancelled" + stage + (outputExists ? ". Partial output may remain." : "."),
            PackageTaskStatus.Interrupted => "Interrupted by a previous shutdown. Retry to run it again.",
            PackageTaskStatus.Cancelling => "Cancelling, waiting for the operation to stop.",
            PackageTaskStatus.Running => "In progress.",
            _ => "Waiting in the queue."
        };
    }

    private static string CountsText(PackageTaskProgress progress)
    {
        var parts = new List<string>();
        if (progress.CurrentItem > 0 || progress.TotalItems > 0)
            parts.Add(progress.TotalItems > 0 ? $"{progress.CurrentItem:N0} / {progress.TotalItems:N0}" : $"{progress.CurrentItem:N0}");
        if (progress.TotalBytes > 0)
            parts.Add($"{GameClassifier.FormatBytes(progress.CurrentBytes)} / {GameClassifier.FormatBytes(progress.TotalBytes)}");
        return string.Join("  ·  ", parts);
    }

    private static string ElapsedText(QueuedPackageTask task)
    {
        DateTime? start = task.StartedUtc;
        if (start is null) return string.Empty;
        return FormatDuration((task.CompletedUtc ?? DateTime.UtcNow) - start.Value);
    }

    private static string? EtaText(QueuedPackageTask task)
    {
        if (task.Status != PackageTaskStatus.Running || task.StartedUtc is null) return null;
        double percent = task.Progress.TaskPercent;
        if (percent is <= 0.03d or >= 0.999d) return null;
        TimeSpan elapsed = DateTime.UtcNow - task.StartedUtc.Value;
        double totalSeconds = elapsed.TotalSeconds / percent;
        return FormatDuration(TimeSpan.FromSeconds(Math.Max(0d, totalSeconds - elapsed.TotalSeconds))) + " left";
    }

    private static string FormatDuration(TimeSpan value)
    {
        if (value < TimeSpan.Zero) value = TimeSpan.Zero;
        return value.TotalHours >= 1d
            ? $"{(int)value.TotalHours}:{value.Minutes:00}:{value.Seconds:00}"
            : value.TotalMinutes >= 1d
                ? $"{value.Minutes}:{value.Seconds:00}"
                : $"{value.Seconds}s";
    }

    /// <summary>A self-contained diagnostic report with secrets masked.</summary>
    public string Report(string id)
    {
        QueuedPackageTask task = Require(id);
        var report = new StringBuilder();
        report.AppendLine("PS5 PKG Tool (Linux) - task report");
        report.AppendLine("Generated: " + DateTime.Now.ToString("u"));
        report.AppendLine("Platform: " + System.Runtime.InteropServices.RuntimeInformation.OSDescription);
        report.AppendLine();
        report.AppendLine("Task: " + task.DisplayName);
        report.AppendLine("Task id: " + task.Id);
        report.AppendLine("Operation: " + (task.Operation.Length > 0 ? task.Operation : task.Type));
        report.AppendLine("State: " + task.Status);
        if (task.Message.Length > 0) report.AppendLine("Message: " + task.Message);
        if (!string.IsNullOrWhiteSpace(task.Progress.Stage)) report.AppendLine("Last stage: " + task.Progress.Stage);
        if (task.Attempts > 0) report.AppendLine("Attempts: " + task.Attempts);
        report.AppendLine("Created: " + task.CreatedUtc.ToLocalTime().ToString("u"));
        if (task.StartedUtc is { } started) report.AppendLine("Started: " + started.ToLocalTime().ToString("u"));
        if (task.CompletedUtc is { } completed) report.AppendLine("Ended: " + completed.ToLocalTime().ToString("u"));
        if (task.FormatRoute.Length > 0) report.AppendLine("Route: " + task.FormatRoute);
        report.AppendLine("Source: " + task.SourcePath);
        if (task.OutputPath.Length > 0) report.AppendLine("Output: " + task.OutputPath);

        TaskPayload fields = TaskPayload.Parse(task.PersistencePayload);
        if (fields.Count > 0)
        {
            report.AppendLine();
            report.AppendLine("Configuration (secrets masked):");
            foreach ((string key, string value) in fields.OrderBy(pair => pair.Key, StringComparer.OrdinalIgnoreCase))
                report.AppendLine($"  {key} = {MaskSecret(key, value)}");
        }
        if (task.Failure is { } failure)
        {
            report.AppendLine();
            report.AppendLine("Failure:");
            report.AppendLine(failure.ToString());
        }
        return report.ToString();
    }

    private static string MaskSecret(string key, string value) =>
        key.Contains("passcode", StringComparison.OrdinalIgnoreCase) || key.Contains("key", StringComparison.OrdinalIgnoreCase)
            ? new string('*', Math.Min(value.Length, 8))
            : value;

    private void MarkDirty() => Interlocked.Exchange(ref _dirty, 1);

    private void Flush()
    {
        if (Interlocked.Exchange(ref _dirty, 0) == 0) return;
        try
        {
            _state.Server.Emit("tasks.changed", new { tasks = Snapshot(), summary = Summary() });
        }
        catch (Exception ex)
        {
            Logger.Exception("Task snapshot failed", ex);
        }
    }

    public async ValueTask DisposeAsync()
    {
        await _pump.DisposeAsync().ConfigureAwait(false);
        await _queue.DisposeAsync().ConfigureAwait(false);
    }
}
