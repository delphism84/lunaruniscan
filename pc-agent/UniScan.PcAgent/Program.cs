using System;
using System.IO;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace UniScan.PcAgent;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
        Application.ThreadException += (_, e) => AgentLog.Error("UI ThreadException", e.Exception);
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
            AgentLog.Error("AppDomain.UnhandledException", e.ExceptionObject as Exception);
        TaskScheduler.UnobservedTaskException += (_, e) =>
        {
            AgentLog.Error("TaskScheduler.UnobservedTaskException", e.Exception);
            e.SetObserved();
        };

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        var baseDir = AppDomain.CurrentDomain.BaseDirectory;
        var configPath = ResolveConfigPath(baseDir);
        var themePath = Path.Combine(baseDir, "Themes", "WhiteUI.css");
        var iconPath = Path.Combine(baseDir, "uniscan.ico");

        AgentLog.Info($"Start. baseDir={baseDir}");
        AgentLog.Info($"configPath={configPath}");
        AgentLog.Info($"themePath={themePath}");
        AgentLog.Info($"logPath={AgentLog.LogPath}");

        using var app = new AgentApplicationContext(configPath, themePath, iconPath);
        Application.Run(app);
    }

    private static string ResolveConfigPath(string baseDir)
    {
        var basePath = Path.Combine(baseDir, "config.json");
        var fallbackDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "UniScan",
            "PcAgent");
        var fallbackPath = Path.Combine(fallbackDir, "config.json");

        try
        {
            // Prefer config next to exe if it exists.
            if (File.Exists(basePath))
                return basePath;

            // If exe config is missing but fallback exists, try to restore to exe dir (if writable).
            if (File.Exists(fallbackPath))
            {
                if (CanCreateTempFile(baseDir))
                {
                    try
                    {
                        File.Copy(fallbackPath, basePath, overwrite: true);
                        return basePath;
                    }
                    catch
                    {
                        // ignore and use fallback
                    }
                }

                return fallbackPath;
            }

            // No config anywhere yet: choose exe dir if writable, otherwise fallback.
            if (CanCreateTempFile(baseDir))
                return basePath;

            Directory.CreateDirectory(fallbackDir);
            return fallbackPath;
        }
        catch (Exception ex)
        {
            AgentLog.Error("ResolveConfigPath failed; using exe dir.", ex);
            return basePath;
        }
    }

    private static bool CanCreateTempFile(string dir)
    {
        try
        {
            var tmp = Path.Combine(dir, $".__uniscan_write_test_{Guid.NewGuid():n}.tmp");
            File.WriteAllText(tmp, "x");
            File.Delete(tmp);
            return true;
        }
        catch
        {
            return false;
        }
    }
}

