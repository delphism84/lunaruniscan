using System.Drawing;
using QRCoder;

namespace UniScan.PcAgent;

internal static class QrCodeUtil
{
    public static Bitmap Render(string payload, int pixelsPerModule = 8)
    {
        using var gen = new QRCodeGenerator();
        using var data = gen.CreateQrCode(payload, QRCodeGenerator.ECCLevel.Q);
        using var qr = new QRCode(data);
        return qr.GetGraphic(pixelsPerModule, Color.Black, Color.White, drawQuietZones: true);
    }
}

