using System.Collections.Concurrent;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using PS5PKGTool.Bridge.Infrastructure;

namespace PS5PKGTool.Bridge.Protocol;

/// <summary>A failure reported to the caller as a structured error instead of a crash.</summary>
public sealed class RpcException(string code, string message, string? detail = null) : Exception(message)
{
    public string Code { get; } = code;
    public string? Detail { get; } = detail;

    public static RpcException BadRequest(string message) => new("bad_request", message);
    public static RpcException NotFound(string message) => new("not_found", message);
}

/// <summary>One decoded request with typed accessors for its parameters.</summary>
public sealed class RpcRequest(long id, string method, JsonElement parameters, CancellationToken token)
{
    public long Id { get; } = id;
    public string Method { get; } = method;
    public JsonElement Params { get; } = parameters;
    public CancellationToken Token { get; } = token;

    private bool TryGet(string name, out JsonElement value)
    {
        value = default;
        return Params.ValueKind == JsonValueKind.Object && Params.TryGetProperty(name, out value) &&
               value.ValueKind is not (JsonValueKind.Null or JsonValueKind.Undefined);
    }

    public bool Has(string name) => TryGet(name, out _);

    public string Str(string name, string fallback = "") =>
        TryGet(name, out JsonElement value)
            ? value.ValueKind == JsonValueKind.String ? value.GetString() ?? fallback : value.GetRawText()
            : fallback;

    public string RequireStr(string name)
    {
        string value = Str(name);
        if (value.Length == 0) throw RpcException.BadRequest($"Missing parameter '{name}'.");
        return value;
    }

    public int Int(string name, int fallback = 0) =>
        TryGet(name, out JsonElement value) && value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out int number)
            ? number
            : TryGet(name, out value) && value.ValueKind == JsonValueKind.String && int.TryParse(value.GetString(), out number)
                ? number
                : fallback;

    public long Long(string name, long fallback = 0) =>
        TryGet(name, out JsonElement value) && value.ValueKind == JsonValueKind.Number && value.TryGetInt64(out long number)
            ? number
            : fallback;

    public bool Bool(string name, bool fallback = false) =>
        TryGet(name, out JsonElement value) ? value.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            JsonValueKind.String => bool.TryParse(value.GetString(), out bool parsed) ? parsed : fallback,
            _ => fallback
        } : fallback;

    public List<string> StrList(string name)
    {
        var result = new List<string>();
        if (!TryGet(name, out JsonElement value)) return result;
        if (value.ValueKind == JsonValueKind.String)
        {
            result.Add(value.GetString() ?? string.Empty);
            return result;
        }
        if (value.ValueKind != JsonValueKind.Array) return result;
        foreach (JsonElement item in value.EnumerateArray())
            if (item.ValueKind == JsonValueKind.String) result.Add(item.GetString() ?? string.Empty);
        return result;
    }

    public JsonElement? Element(string name) => TryGet(name, out JsonElement value) ? value : null;

    public T? Object<T>(string name) where T : class =>
        TryGet(name, out JsonElement value) ? value.Deserialize<T>(Json.Options) : null;
}

public static class Json
{
    public static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        DefaultIgnoreCondition = JsonIgnoreCondition.Never,
        NumberHandling = JsonNumberHandling.AllowNamedFloatingPointLiterals,
        Converters = { new JsonStringEnumConverter() }
    };
}

/// <summary>
/// JSON-lines RPC over stdin/stdout. Every request line is <c>{"id","method","params"}</c> and gets
/// exactly one response line, <c>{"id","result"}</c> or <c>{"id","error"}</c>. Events are pushed as
/// <c>{"event","data"}</c> lines at any time. Requests run concurrently; a long-running call can be
/// cancelled with <c>call.cancel {"id": n}</c>. Nothing else may write to stdout, so the process
/// redirects <see cref="Console.Out"/> to stderr before the server starts.
/// </summary>
public sealed class RpcServer
{
    private readonly Dictionary<string, Func<RpcRequest, Task<object?>>> _methods = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<long, CancellationTokenSource> _calls = new();
    private readonly Stream _output;
    private readonly object _writeGate = new();
    private readonly TaskCompletionSource _shutdown = new(TaskCreationOptions.RunContinuationsAsynchronously);

    public RpcServer(Stream output)
    {
        _output = output;
        Register("call.cancel", request =>
        {
            long id = request.Long("id");
            if (_calls.TryGetValue(id, out CancellationTokenSource? source)) source.Cancel();
            return Task.FromResult<object?>(new { cancelled = source is not null });
        });
        Register("app.shutdown", _ =>
        {
            _shutdown.TrySetResult();
            return Task.FromResult<object?>(new { ok = true });
        });
    }

    /// <summary>Completes when the client asks the bridge to exit or closes stdin.</summary>
    public Task Shutdown => _shutdown.Task;

    public void Register(string method, Func<RpcRequest, Task<object?>> handler) => _methods[method] = handler;

    public void Register(string method, Func<RpcRequest, object?> handler) =>
        _methods[method] = request => Task.FromResult(handler(request));

    public IEnumerable<string> Methods => _methods.Keys.Order(StringComparer.Ordinal);

    /// <summary>Pushes an unsolicited event to the client.</summary>
    public void Emit(string name, object? data) => Write(new { @event = name, data });

    public async Task RunAsync(Stream input)
    {
        using var reader = new StreamReader(input, new UTF8Encoding(false));
        while (true)
        {
            string? line;
            try
            {
                line = await reader.ReadLineAsync().ConfigureAwait(false);
            }
            catch (IOException)
            {
                break;
            }
            if (line is null) break;
            if (string.IsNullOrWhiteSpace(line)) continue;
            Dispatch(line);
        }
        _shutdown.TrySetResult();
    }

    private void Dispatch(string line)
    {
        long id = 0;
        string method;
        JsonElement parameters;
        try
        {
            using JsonDocument document = JsonDocument.Parse(line);
            JsonElement root = document.RootElement;
            id = root.TryGetProperty("id", out JsonElement idElement) && idElement.TryGetInt64(out long parsed) ? parsed : 0;
            method = root.TryGetProperty("method", out JsonElement methodElement) ? methodElement.GetString() ?? string.Empty : string.Empty;
            parameters = root.TryGetProperty("params", out JsonElement paramsElement) ? paramsElement.Clone() : default;
        }
        catch (JsonException ex)
        {
            WriteError(id, new RpcException("parse_error", "The request is not valid JSON: " + ex.Message));
            return;
        }

        if (!_methods.TryGetValue(method, out Func<RpcRequest, Task<object?>>? handler))
        {
            WriteError(id, new RpcException("unknown_method", $"Unknown method '{method}'."));
            return;
        }

        var cancellation = new CancellationTokenSource();
        if (id != 0) _calls[id] = cancellation;
        _ = Task.Run(async () =>
        {
            try
            {
                object? result = await handler(new RpcRequest(id, method, parameters, cancellation.Token)).ConfigureAwait(false);
                Write(new { id, result });
            }
            catch (OperationCanceledException)
            {
                WriteError(id, new RpcException("cancelled", "The operation was cancelled."));
            }
            catch (RpcException ex)
            {
                WriteError(id, ex);
            }
            catch (Exception ex)
            {
                Logger.Exception($"Bridge call '{method}' failed", ex);
                WriteError(id, new RpcException("failed", ex.Message, ex.GetType().Name));
            }
            finally
            {
                _calls.TryRemove(id, out _);
                cancellation.Dispose();
            }
        });
    }

    private void WriteError(long id, RpcException error) =>
        Write(new { id, error = new { code = error.Code, message = error.Message, detail = error.Detail } });

    private void Write(object envelope)
    {
        byte[] bytes;
        try
        {
            bytes = JsonSerializer.SerializeToUtf8Bytes(envelope, Json.Options);
        }
        catch (Exception ex) when (ex is NotSupportedException or InvalidOperationException or JsonException)
        {
            Logger.Exception("Bridge could not serialize a message", ex);
            return;
        }
        lock (_writeGate)
        {
            try
            {
                _output.Write(bytes);
                _output.WriteByte((byte)'\n');
                _output.Flush();
            }
            catch (IOException)
            {
                _shutdown.TrySetResult();
            }
        }
    }
}
