using System;

namespace UniScan.PcAgent;

internal sealed class InputResultInfo
{
    public string JobId { get; set; } = "";
    public string Barcode { get; set; } = "";
    public bool Ok { get; set; }
    public int AgentAttempt { get; set; }
    public string InputMethod { get; set; } = "";
    public int DurationMs { get; set; }
    public string Error { get; set; } = "";
    public DateTime AtUtc { get; set; } = DateTime.UtcNow;
}

