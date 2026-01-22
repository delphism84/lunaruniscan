using System;

namespace UniScan.PcAgent;

internal sealed class DeliverBarcodeItem
{
    public string JobId { get; set; } = "";
    public int ServerAttempt { get; set; }
    public string Barcode { get; set; } = "";
    public string SuffixKey { get; set; } = "Enter";
    public DateTime ReceivedAtUtc { get; set; } = DateTime.UtcNow;
}

