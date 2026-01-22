using System;
using System.Collections.Generic;
using System.Threading;

namespace UniScan.PcAgent;

internal static class Win32Input
{
    private static readonly int[] AgentRetryBackoffMs = { 100, 200, 400, 800, 1600 };

    public static bool TryInputWithRetries(
        AgentConfig config,
        string barcode,
        string suffixKey,
        out int agentAttempt,
        out string inputMethod,
        out string error)
    {
        inputMethod = "scanCode";
        error = "UNKNOWN";
        agentAttempt = 0;

        for (int i = 0; i < 5; i++)
        {
            agentAttempt = i + 1;
            if (TryInputOnce(config, barcode, suffixKey, out inputMethod, out error))
                return true;

            Thread.Sleep(AgentRetryBackoffMs[i]);
        }

        return false;
    }

    private static bool TryInputOnce(AgentConfig config, string barcode, string suffixKey, out string inputMethod, out string error)
    {
        inputMethod = "scanCode";
        error = "";

        // 1) target window focus (optional)
        var hwnd = WindowFinder.FindTargetWindow(config.TargetWindow);
        if (hwnd != IntPtr.Zero)
        {
            if (!FocusWindow(hwnd))
            {
                error = "FOCUS_FAIL";
                return false;
            }
        }
        else
        {
            // if user configured a target but not found, treat as retryable fail
            if (!string.IsNullOrWhiteSpace(config.TargetWindow.ProcessName) || !string.IsNullOrWhiteSpace(config.TargetWindow.WindowTitleContains))
            {
                error = "TARGET_NOT_FOUND";
                return false;
            }
        }

        // 2) send barcode via scancode (layout-aware). fallback to unicode per char
        if (!SendTextByScanCode(barcode))
        {
            inputMethod = "unicode";
            if (!SendTextByUnicode(barcode))
            {
                error = "SENDINPUT_FAIL";
                return false;
            }
        }

        // 3) suffix key
        var keyOk = suffixKey?.Trim().Equals("Tab", StringComparison.OrdinalIgnoreCase) == true
            ? SendVirtualKey(Win32.VK_TAB)
            : SendVirtualKey(Win32.VK_RETURN);
        if (!keyOk)
        {
            error = "SUFFIX_FAIL";
            return false;
        }

        return true;
    }

    private static bool FocusWindow(IntPtr hwnd)
    {
        try
        {
            Win32.ShowWindow(hwnd, Win32.SW_RESTORE);

            // try direct
            if (Win32.SetForegroundWindow(hwnd))
            {
                Win32.SetFocus(hwnd);
                return true;
            }

            // stabilize: attach input threads (foreground + current) to target thread
            var fg = Win32.GetForegroundWindow();
            var curTid = Win32.GetCurrentThreadId();
            var fgTid = Win32.GetWindowThreadProcessId(fg, out _);
            var targetTid = Win32.GetWindowThreadProcessId(hwnd, out _);

            Win32.AttachThreadInput(curTid, targetTid, true);
            Win32.AttachThreadInput(fgTid, targetTid, true);
            try
            {
                Win32.ShowWindow(hwnd, Win32.SW_RESTORE);
                Win32.SetForegroundWindow(hwnd);
                Win32.SetFocus(hwnd);
            }
            finally
            {
                Win32.AttachThreadInput(curTid, targetTid, false);
                Win32.AttachThreadInput(fgTid, targetTid, false);
            }

            return Win32.GetForegroundWindow() == hwnd;
        }
        catch
        {
            return false;
        }
    }

    private static bool SendTextByUnicode(string text)
    {
        foreach (var ch in text)
        {
            var down = new Win32.INPUT
            {
                type = Win32.INPUT_KEYBOARD,
                U = new Win32.InputUnion
                {
                    ki = new Win32.KEYBDINPUT
                    {
                        wVk = 0,
                        wScan = ch,
                        dwFlags = Win32.KEYEVENTF_UNICODE
                    }
                }
            };
            var up = down;
            up.U.ki.dwFlags = Win32.KEYEVENTF_UNICODE | Win32.KEYEVENTF_KEYUP;

            if (Win32.SendInput(2, new[] { down, up }, System.Runtime.InteropServices.Marshal.SizeOf(typeof(Win32.INPUT))) != 2)
                return false;
        }
        return true;
    }

    private static bool SendTextByScanCode(string text)
    {
        var layout = Win32.GetKeyboardLayout(0);

        foreach (var ch in text)
        {
            short vkAndShift = Win32.VkKeyScanEx(ch, layout);
            if (vkAndShift == -1)
            {
                // not mappable in current layout -> let caller fall back
                return false;
            }

            int vk = vkAndShift & 0xff;
            int shiftState = (vkAndShift >> 8) & 0xff; // 1=shift,2=ctrl,4=alt

            var inputs = new List<Win32.INPUT>(8);

            // modifiers down
            if ((shiftState & 1) != 0) inputs.AddRange(KeyDownUp(Win32.VK_SHIFT, down: true));
            if ((shiftState & 2) != 0) inputs.AddRange(KeyDownUp(Win32.VK_CONTROL, down: true));
            if ((shiftState & 4) != 0) inputs.AddRange(KeyDownUp(Win32.VK_MENU, down: true));

            // main key down/up by scancode
            var scan = (ushort)Win32.MapVirtualKey((uint)vk, Win32.MAPVK_VK_TO_VSC);
            inputs.Add(new Win32.INPUT
            {
                type = Win32.INPUT_KEYBOARD,
                U = new Win32.InputUnion
                {
                    ki = new Win32.KEYBDINPUT
                    {
                        wVk = 0,
                        wScan = scan,
                        dwFlags = Win32.KEYEVENTF_SCANCODE
                    }
                }
            });
            inputs.Add(new Win32.INPUT
            {
                type = Win32.INPUT_KEYBOARD,
                U = new Win32.InputUnion
                {
                    ki = new Win32.KEYBDINPUT
                    {
                        wVk = 0,
                        wScan = scan,
                        dwFlags = Win32.KEYEVENTF_SCANCODE | Win32.KEYEVENTF_KEYUP
                    }
                }
            });

            // modifiers up (reverse)
            if ((shiftState & 4) != 0) inputs.AddRange(KeyDownUp(Win32.VK_MENU, down: false));
            if ((shiftState & 2) != 0) inputs.AddRange(KeyDownUp(Win32.VK_CONTROL, down: false));
            if ((shiftState & 1) != 0) inputs.AddRange(KeyDownUp(Win32.VK_SHIFT, down: false));

            if (!SendInputs(inputs))
                return false;
        }

        return true;
    }

    private static bool SendVirtualKey(ushort vk)
    {
        // use scancode
        var scan = (ushort)Win32.MapVirtualKey(vk, Win32.MAPVK_VK_TO_VSC);
        var down = new Win32.INPUT
        {
            type = Win32.INPUT_KEYBOARD,
            U = new Win32.InputUnion
            {
                ki = new Win32.KEYBDINPUT
                {
                    wVk = 0,
                    wScan = scan,
                    dwFlags = Win32.KEYEVENTF_SCANCODE
                }
            }
        };
        var up = down;
        up.U.ki.dwFlags = Win32.KEYEVENTF_SCANCODE | Win32.KEYEVENTF_KEYUP;
        return Win32.SendInput(2, new[] { down, up }, System.Runtime.InteropServices.Marshal.SizeOf(typeof(Win32.INPUT))) == 2;
    }

    private static bool SendInputs(List<Win32.INPUT> inputs)
    {
        if (inputs.Count == 0) return true;
        var arr = inputs.ToArray();
        return Win32.SendInput((uint)arr.Length, arr, System.Runtime.InteropServices.Marshal.SizeOf(typeof(Win32.INPUT))) == (uint)arr.Length;
    }

    private static IEnumerable<Win32.INPUT> KeyDownUp(ushort vk, bool down)
    {
        var scan = (ushort)Win32.MapVirtualKey(vk, Win32.MAPVK_VK_TO_VSC);
        yield return new Win32.INPUT
        {
            type = Win32.INPUT_KEYBOARD,
            U = new Win32.InputUnion
            {
                ki = new Win32.KEYBDINPUT
                {
                    wVk = 0,
                    wScan = scan,
                    dwFlags = down ? Win32.KEYEVENTF_SCANCODE : (Win32.KEYEVENTF_SCANCODE | Win32.KEYEVENTF_KEYUP)
                }
            }
        };
    }
}

