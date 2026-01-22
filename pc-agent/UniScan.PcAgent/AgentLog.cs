using System;
using System.IO;
using System.Text;

namespace UniScan.PcAgent;

internal static class AgentLog
{
    private static readonly object LockObj = new object();

    public static string LogPath { get; } = InitLogPath();

    private static string InitLogPath()
    {
        var dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "UniScan",
            "PcAgent");
        Directory.CreateDirectory(dir);
        return Path.Combine(dir, "agent.log");
    }

    public static void Info(string message) => Write("INFO", message, null);

    public static void Error(string message, Exception? ex) => Write("ERROR", message, ex);

    private static void Write(string level, string message, Exception? ex)
    {
        var line = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}] {level} {message}";
        var sb = new StringBuilder();
        sb.AppendLine(line);
        if (ex != null) sb.AppendLine(ex.ToString());

        lock (LockObj)
        {
            File.AppendAllText(LogPath, sb.ToString(), Encoding.UTF8);
        }
    }
}

