using System;
using System.Drawing;
using System.Windows.Forms;

namespace UniScan.PcAgent;

internal sealed class AgentApplicationContext : ApplicationContext
{
    private readonly NotifyIcon _tray;
    private readonly MainForm _form;
    private readonly Icon? _appIcon;
    private bool _initialized;

    public AgentApplicationContext(string configPath, string themePath, string iconPath)
    {
        _form = new MainForm(configPath, themePath);
        _form.FormClosed += (_, __) => ExitThread();

        _appIcon = TryLoadIcon(iconPath);
        if (_appIcon != null)
        {
            _form.Icon = _appIcon;
        }

        var menu = new ContextMenuStrip();
        menu.Items.Add("Open", null, (_, __) => ShowForm());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Exit", null, (_, __) => ExitThread());

        _tray = new NotifyIcon
        {
            Text = "UniScan PC Agent",
            Icon = _appIcon ?? SystemIcons.Application,
            Visible = true,
            ContextMenuStrip = menu
        };
        _tray.DoubleClick += (_, __) => ShowForm();

        // start visible (show main form on launch)
        ShowForm();

        // initialize after message loop starts (avoid Invoke/SyncContext issues)
        Application.Idle += OnFirstIdle;
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _tray.Visible = false;
            _tray.Dispose();
            _form.Dispose();
            _appIcon?.Dispose();
        }
        base.Dispose(disposing);
    }

    private void OnFirstIdle(object? sender, EventArgs e)
    {
        if (_initialized) return;
        _initialized = true;
        Application.Idle -= OnFirstIdle;

        try
        {
            // Ensure handles exist so UI marshaling is safe even while hidden.
            _form.CreateControl();
            _ = _form.Handle;
        }
        catch
        {
            // ignore
        }

        _form.InitializeAgentAsync();
    }

    private void ShowForm()
    {
        if (_form.IsDisposed) return;
        _form.ShowInTaskbar = true;
        _form.Show();
        _form.WindowState = FormWindowState.Normal;
        _form.Activate();
    }

    private void HideForm()
    {
        if (_form.IsDisposed) return;
        _form.ShowInTaskbar = false;
        _form.Hide();
    }

    private static Icon? TryLoadIcon(string path)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(path) || !System.IO.File.Exists(path)) return null;
            return new Icon(path);
        }
        catch
        {
            return null;
        }
    }
}

