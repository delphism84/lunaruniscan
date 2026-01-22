using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace UniScan.PcAgent;

internal sealed class InputQueueWorker : IDisposable
{
    private readonly AgentConfig _config;
    private readonly WsAgentClient _client;
    private readonly Action<string> _log;
    private readonly Action<int>? _onQueueLengthChanged;
    private readonly Action<InputResultInfo>? _onInputResult;

    private readonly BlockingCollection<DeliverBarcodeItem> _queue = new(new ConcurrentQueue<DeliverBarcodeItem>());
    private readonly CancellationTokenSource _cts = new();

    // idempotency: jobId -> succeeded
    private readonly ConcurrentDictionary<string, DateTime> _successJobs = new();

    public InputQueueWorker(
        AgentConfig config,
        WsAgentClient client,
        Action<string> log,
        Action<int>? onQueueLengthChanged = null,
        Action<InputResultInfo>? onInputResult = null)
    {
        _config = config;
        _client = client;
        _log = log;
        _onQueueLengthChanged = onQueueLengthChanged;
        _onInputResult = onInputResult;
        _ = Task.Run(WorkerLoopAsync, _cts.Token);
    }

    public int QueueLength => _queue.Count;

    public void Enqueue(DeliverBarcodeItem item)
    {
        if (_cts.IsCancellationRequested) return;
        _queue.Add(item);
        _onQueueLengthChanged?.Invoke(_queue.Count);
    }

    public void Dispose()
    {
        _cts.Cancel();
        _queue.CompleteAdding();
        _queue.Dispose();
    }

    private async Task WorkerLoopAsync()
    {
        foreach (var item in _queue.GetConsumingEnumerable(_cts.Token))
        {
            try
            {
                await ProcessOneAsync(item);
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch (Exception ex)
            {
                _log($"Input worker error: {ex.Message}");
            }
        }
    }

    private async Task ProcessOneAsync(DeliverBarcodeItem item)
    {
        if (_successJobs.ContainsKey(item.JobId))
        {
            _log($"Duplicate jobId={item.JobId} -> ACK only (no re-input)");
            await _client.SendDeliverAckAsync(item.JobId, item.ServerAttempt, ok: true, agentAttempt: 0, error: null, inputMethod: "duplicate", durationMs: 0, deliveryId: item.DeliveryId);
            _onInputResult?.Invoke(new InputResultInfo
            {
                JobId = item.JobId,
                Barcode = item.Barcode,
                Ok = true,
                AgentAttempt = 0,
                InputMethod = "duplicate",
                DurationMs = 0,
                Error = "",
                AtUtc = DateTime.UtcNow
            });
            _onQueueLengthChanged?.Invoke(_queue.Count);
            return;
        }

        var sw = Stopwatch.StartNew();
        var result = Win32Input.TryInputWithRetries(
            _config,
            item.Barcode,
            item.SuffixKey,
            out var agentAttempt,
            out var inputMethod,
            out var error);

        sw.Stop();
        var durationMs = (int)sw.ElapsedMilliseconds;

        if (result)
        {
            _successJobs[item.JobId] = DateTime.UtcNow;
            _log($"Input OK jobId={item.JobId} method={inputMethod} attempt={agentAttempt} ({sw.ElapsedMilliseconds}ms)");
            await _client.SendDeliverAckAsync(item.JobId, item.ServerAttempt, ok: true, agentAttempt: agentAttempt, error: null, inputMethod: inputMethod, durationMs: durationMs, deliveryId: item.DeliveryId);
            _onInputResult?.Invoke(new InputResultInfo
            {
                JobId = item.JobId,
                Barcode = item.Barcode,
                Ok = true,
                AgentAttempt = agentAttempt,
                InputMethod = inputMethod,
                DurationMs = durationMs,
                Error = "",
                AtUtc = DateTime.UtcNow
            });
        }
        else
        {
            _log($"Input FAIL jobId={item.JobId} attempt={agentAttempt} err={error}");
            await _client.SendDeliverAckAsync(item.JobId, item.ServerAttempt, ok: false, agentAttempt: agentAttempt, error: error, inputMethod: inputMethod, durationMs: durationMs, deliveryId: item.DeliveryId);
            _onInputResult?.Invoke(new InputResultInfo
            {
                JobId = item.JobId,
                Barcode = item.Barcode,
                Ok = false,
                AgentAttempt = agentAttempt,
                InputMethod = inputMethod,
                DurationMs = durationMs,
                Error = error,
                AtUtc = DateTime.UtcNow
            });
        }

        _onQueueLengthChanged?.Invoke(_queue.Count);

        // small cleanup (prevent unbounded growth)
        if (_successJobs.Count > 2000)
        {
            var cutoff = DateTime.UtcNow.AddHours(-6);
            foreach (var kv in _successJobs)
            {
                if (kv.Value < cutoff) _successJobs.TryRemove(kv.Key, out _);
            }
        }
    }
}

