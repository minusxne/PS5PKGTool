using PS5PKGTool.Bridge.Infrastructure;
using PS5PKGTool.Bridge.Protocol;

namespace PS5PKGTool.Bridge;

/// <summary>Process-wide state shared by the services: persisted settings and the event channel.</summary>
public sealed class BridgeState
{
    private readonly object _gate = new();

    public BridgeState(RpcServer server)
    {
        Server = server;
        Store = new AppStateStore();
        SettingsLoadResult loaded = Store.LoadSettingsWithDiagnostics();
        Settings = loaded.Settings;
        StartupWarning = loaded.Warning;
    }

    public RpcServer Server { get; }
    public AppStateStore Store { get; }
    public AppSettings Settings { get; private set; }
    public string? StartupWarning { get; }

    /// <summary>Applies a change to the settings under the state lock and persists it.</summary>
    public void UpdateSettings(Action<AppSettings> change)
    {
        lock (_gate)
        {
            change(Settings);
            Settings = AppSettingsNormalizer.Normalize(Settings);
            TrySave();
        }
        Server.Emit("settings.changed", Settings);
    }

    public void ReplaceSettings(AppSettings settings)
    {
        lock (_gate)
        {
            Settings = AppSettingsNormalizer.Normalize(settings);
            TrySave();
        }
        Server.Emit("settings.changed", Settings);
    }

    /// <summary>The passcode a new job should use: the saved default or the all-zero default.</summary>
    public string DefaultPasscode => string.IsNullOrEmpty(Settings.DebugPasscode)
        ? Core.Builders.SonyDebugPackageCredentials.DefaultPasscode
        : Settings.DebugPasscode;

    private void TrySave()
    {
        try
        {
            Store.SaveSettings(Settings);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Logger.Error("Settings could not be saved: " + ex.Message);
            throw new RpcException("io_error", "Settings could not be saved: " + ex.Message);
        }
    }
}
