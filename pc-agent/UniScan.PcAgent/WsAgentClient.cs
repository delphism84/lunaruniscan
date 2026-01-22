using System;
using System.Collections.Generic;
using System.Net.WebSockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace UniScan.PcAgent;

internal sealed class WsAgentClient : IDisposable
{
    private readonly AgentConfig _config;
    private readonly Action<string> _log;
    private readonly Action<string> _setStatus;
    private readonly Action<string> _setPcId;
    private readonly Action<string> _setPairingCode;
    private readonly Action<int> _setRegisteredScanners;

    private readonly JavaScriptSerializer _json = new();
    private readonly CancellationTokenSource _cts = new();

    private ClientWebSocket? _ws;
    private string _pcId = "";

    public event Action<DeliverBarcodeItem>? OnDeliverBarcode;

    public WsAgentClient(
        AgentConfig config,
        Action<string> log,
        Action<string> setStatus,
        Action<string> setPcId,
        Action<string> setPairingCode,
        Action<int> setRegisteredScanners)
    {
        _config = config;
        _log = log;
        _setStatus = setStatus;
        _setPcId = setPcId;
        _setPairingCode = setPairingCode;
        _setRegisteredScanners = setRegisteredScanners;
    }

    public async Task StartAsync()
    {
        await Task.Yield();
        _ = Task.Run(RunAsync, _cts.Token);
    }

    public async Task SendDeliverAckAsync(string jobId, int serverAttempt, bool ok, int agentAttempt, string? error, string? inputMethod, int? durationMs, string? deliveryId = null)
    {
        var ws = _ws;
        if (ws == null || ws.State != WebSocketState.Open) return;

        Dictionary<string, object?> data = new()
        {
            ["jobId"] = jobId,
            ["pcId"] = _pcId,
            ["attempt"] = serverAttempt,
            ["agentAttempt"] = agentAttempt,
            ["ok"] = ok,
            ["error"] = ok ? null : (error ?? "AGENT_FAIL"),
            ["inputMethod"] = inputMethod,
            ["durationMs"] = durationMs
        };
        if (!string.IsNullOrWhiteSpace(deliveryId))
            data["deliveryId"] = deliveryId;

        var msg = new Dictionary<string, object?>
        {
            ["type"] = "deliverAck",
            ["requestId"] = Guid.NewGuid().ToString("n"),
            ["clientType"] = "pcAgent",
            ["timestamp"] = DateTime.UtcNow.ToString("o"),
            ["data"] = data
        };

        await SendAsync(msg);
    }

    public void Dispose()
    {
        _cts.Cancel();
        try { _ws?.Dispose(); } catch { }
    }

    private async Task RunAsync()
    {
        var backoff = new[] { 500, 1000, 2000, 5000, 8000 };
        int idx = 0;

        while (!_cts.IsCancellationRequested)
        {
            try
            {
                _setStatus("Status: connecting...");
                _ws?.Dispose();
                _ws = new ClientWebSocket();
                await _ws.ConnectAsync(new Uri(_config.ServerUrl), _cts.Token);

                idx = 0;
                _setStatus("Status: connected");
                _log($"Connected: {_config.ServerUrl}");

                await SendHelloAsync();
                await ReceiveLoopAsync(_ws, _cts.Token);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                _setStatus("Status: disconnected");
                _log($"Connection error: {ex.Message}");
            }

            var delay = backoff[Math.Min(idx, backoff.Length - 1)];
            idx++;
            try { await Task.Delay(delay, _cts.Token); } catch { }
        }
    }

    private async Task SendHelloAsync()
    {
        var msg = new Dictionary<string, object?>
        {
            ["type"] = "pcAgentHello",
            ["requestId"] = Guid.NewGuid().ToString("n"),
            ["clientType"] = "pcAgent",
            ["timestamp"] = DateTime.UtcNow.ToString("o"),
            ["data"] = new Dictionary<string, object?>
            {
                ["group"] = _config.Group,
                ["deviceName"] = _config.DeviceName,
                ["machineId"] = _config.MachineId,
                ["version"] = "0.1.0"
            }
        };
        await SendAsync(msg);
    }

    private async Task SendAsync(Dictionary<string, object?> msg)
    {
        var ws = _ws;
        if (ws == null || ws.State != WebSocketState.Open) return;

        var json = _json.Serialize(msg);
        var bytes = Encoding.UTF8.GetBytes(json);
        await ws.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, _cts.Token);
    }

    private async Task ReceiveLoopAsync(ClientWebSocket ws, CancellationToken ct)
    {
        var buffer = new byte[128 * 1024];

        while (ws.State == WebSocketState.Open && !ct.IsCancellationRequested)
        {
            var sb = new StringBuilder();
            WebSocketReceiveResult? result;
            do
            {
                result = await ws.ReceiveAsync(new ArraySegment<byte>(buffer), ct);
                if (result.MessageType == WebSocketMessageType.Close)
                {
                    try { await ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "bye", ct); } catch { }
                    return;
                }
                sb.Append(Encoding.UTF8.GetString(buffer, 0, result.Count));
            } while (!result.EndOfMessage);

            var text = sb.ToString();
            HandleIncoming(text);
        }
    }

    private void HandleIncoming(string text)
    {
        Dictionary<string, object?>? msg;
        try
        {
            msg = _json.Deserialize<Dictionary<string, object?>>(text);
        }
        catch
        {
            return;
        }
        if (msg == null) return;

        var type = GetString(msg, "type");
        if (!string.Equals(type, "event", StringComparison.OrdinalIgnoreCase))
            return;

        var ev = GetString(msg, "event");
        var data = GetDict(msg, "data");

        if (string.Equals(ev, "pairingCode", StringComparison.OrdinalIgnoreCase))
        {
            var code = GetString(data, "code");
            var pin = GetString(data, "pin");
            var pcId = GetString(data, "pcId");
            if (!string.IsNullOrWhiteSpace(pcId))
            {
                _pcId = pcId;
                _setPcId(pcId);
            }
            if (!string.IsNullOrWhiteSpace(code))
            {
                // Show "code-pin" so user can type both; QR payload uses same string.
                var shown = string.IsNullOrWhiteSpace(pin) ? code : $"{code}-{pin}";
                _setPairingCode(shown);
                _log($"Pairing code received: {shown}");
            }
            return;
        }

        if (string.Equals(ev, "registeredScanners", StringComparison.OrdinalIgnoreCase))
        {
            var n = GetInt(data, "count");
            _setRegisteredScanners(n);
            return;
        }

        if (string.Equals(ev, "deliverBarcode", StringComparison.OrdinalIgnoreCase))
        {
            var jobId = GetString(data, "jobId");
            var deliveryId = GetString(data, "deliveryId");
            var attempt = GetInt(data, "attempt");
            var barcode = GetString(data, "barcode");
            var suffixKey = GetString(data, "suffixKey");
            if (string.IsNullOrWhiteSpace(jobId) || string.IsNullOrWhiteSpace(barcode)) return;

            OnDeliverBarcode?.Invoke(new DeliverBarcodeItem
            {
                JobId = jobId,
                DeliveryId = deliveryId,
                ServerAttempt = attempt <= 0 ? 1 : attempt,
                Barcode = barcode,
                SuffixKey = string.IsNullOrWhiteSpace(suffixKey) ? _config.BarcodeSuffixKey : suffixKey,
                ReceivedAtUtc = DateTime.UtcNow
            });
            return;
        }
    }

    private static string GetString(Dictionary<string, object?>? d, string key)
    {
        if (d == null) return "";
        if (!d.TryGetValue(key, out var v) || v == null) return "";
        return v.ToString() ?? "";
    }

    private static int GetInt(Dictionary<string, object?>? d, string key)
    {
        var s = GetString(d, key);
        return int.TryParse(s, out var n) ? n : 0;
    }

    private static Dictionary<string, object?>? GetDict(Dictionary<string, object?> d, string key)
    {
        if (!d.TryGetValue(key, out var v) || v == null) return null;
        return v as Dictionary<string, object?>;
    }
}

