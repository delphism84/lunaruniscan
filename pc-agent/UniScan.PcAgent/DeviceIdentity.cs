using System;
using Microsoft.Win32;

namespace UniScan.PcAgent;

internal static class DeviceIdentity
{
    // Stable across app reinstall; may change on OS reinstall.
    public static string GetStableMachineId()
    {
        const string keyPath = @"SOFTWARE\Microsoft\Cryptography";
        const string valueName = "MachineGuid";

        try
        {
            using var key = Registry.LocalMachine.OpenSubKey(keyPath, writable: false);
            var v = key == null ? null : (key.GetValue(valueName) as string);
            if (v != null)
            {
                v = v.Trim();
                if (v.Length > 0) return v;
            }
        }
        catch
        {
            // ignore
        }

        return Environment.MachineName;
    }
}

