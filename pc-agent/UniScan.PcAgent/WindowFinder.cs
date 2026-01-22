using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace UniScan.PcAgent;

internal static class WindowFinder
{
    public static IntPtr FindTargetWindow(TargetWindowConfig cfg)
    {
        var procName = (cfg.ProcessName ?? "").Trim();
        var titleContains = (cfg.WindowTitleContains ?? "").Trim();

        if (string.IsNullOrWhiteSpace(procName) && string.IsNullOrWhiteSpace(titleContains))
            return IntPtr.Zero;

        IntPtr found = IntPtr.Zero;

        Win32.EnumWindows((hWnd, _) =>
        {
            if (!Win32.IsWindowVisible(hWnd)) return true;

            var title = Win32.GetWindowTextSafe(hWnd);
            if (!string.IsNullOrWhiteSpace(titleContains) &&
                (title == null || title.IndexOf(titleContains, StringComparison.OrdinalIgnoreCase) < 0))
            {
                return true;
            }

            if (!string.IsNullOrWhiteSpace(procName))
            {
                Win32.GetWindowThreadProcessId(hWnd, out var pid);
                try
                {
                    var p = Process.GetProcessById((int)pid);
                    var name = p.ProcessName ?? "";
                    if (!string.Equals(name, procName, StringComparison.OrdinalIgnoreCase))
                        return true;
                }
                catch
                {
                    return true;
                }
            }

            found = hWnd;
            return false;
        }, IntPtr.Zero);

        return found;
    }
}

