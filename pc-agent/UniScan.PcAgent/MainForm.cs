using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using Gsemac.Forms.Styles.Applicators;
using Gsemac.Forms.Styles.StyleSheets;

namespace UniScan.PcAgent;

internal sealed class MainForm : Form
{
    private readonly string _configPath;
    private readonly string _themePath;
    private SynchronizationContext _ui;

    // Device tab (mobile-like)
    private readonly PictureBox _picQr = new() { SizeMode = PictureBoxSizeMode.Zoom };
    private readonly Label _lblConnValue = new() { AutoSize = true, Text = "-" };
    private readonly Label _lblQueueValue = new() { AutoSize = true, Text = "0" };
    private readonly Label _lblLastBarcodeValue = new() { AutoSize = true, Text = "-" };
    private readonly Label _lblLastInputValue = new() { AutoSize = true, Text = "-" };
    private readonly DataGridView _gridHistory = new() { Dock = DockStyle.Fill };
    private readonly PictureBox _picCode = new() { SizeMode = PictureBoxSizeMode.Zoom };
    private readonly Label _lblPairingBig = new() { AutoSize = true, Text = "------" };

    // Device tab overlay (shown when not connected)
    private readonly Panel _deviceConnOverlay = new() { Dock = DockStyle.Fill, Visible = true };
    private readonly PictureBox _picOverlayConnecting = new() { Dock = DockStyle.Fill, SizeMode = PictureBoxSizeMode.Zoom };
    private readonly Label _lblOverlayTitle = new() { AutoSize = true, Text = "Connecting......." };

    // Settings tab
    private readonly ComboBox _cmbSuffixKey = new() { Width = 160, DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly Button _btnSave = new() { Text = "Save", Width = 80, Height = 30 };
    private readonly Button _btnAdvanced = new() { Text = "Advanced", Width = 100, Height = 30 };

    private readonly Panel _advancedPanel = new() { Dock = DockStyle.Fill, Visible = false };

    private readonly TextBox _txtServerUrl = new() { Width = 360 };
    private readonly TextBox _txtGroup = new() { Width = 360 };
    private readonly TextBox _txtDeviceName = new() { Width = 360 };
    private readonly TextBox _txtPcId = new() { Width = 360, ReadOnly = true };
    private readonly TextBox _txtMachineId = new() { Width = 360, ReadOnly = true };
    private readonly TextBox _txtTargetProcess = new() { Width = 360 };
    private readonly TextBox _txtTargetTitle = new() { Width = 360 };
    private readonly ListBox _lstLog = new() { Dock = DockStyle.Fill };

    private readonly BindingList<string> _log = new();

    private AgentConfig _config = new();
    private WsAgentClient? _client;
    private InputQueueWorker? _worker;

    private string _pcId = "";
    private string _pairingCode = "";

    private bool _advancedUnlocked = false;

    private static readonly Font BaseFont = new Font("Arial", 9f, FontStyle.Regular);

    private const int MaxHistoryRows = 100;

    private sealed class HistoryEntry
    {
        public string JobId { get; set; } = "";
        public string Barcode { get; set; } = "";
        public int ServerAttempt { get; set; } = 1;
        public DateTime ReceivedAtUtc { get; set; } = DateTime.UtcNow;

        public bool HasResult { get; set; } = false;
        public bool Ok { get; set; } = false;
        public string InputMethod { get; set; } = "";
        public int AgentAttempt { get; set; } = 0;
        public int DurationMs { get; set; } = 0;
        public string Error { get; set; } = "";
    }

    private readonly List<HistoryEntry> _history = new();
    private readonly Dictionary<string, int> _historyIndexByJobId = new();

    public MainForm(string configPath, string themePath)
    {
        _configPath = configPath;
        _themePath = themePath;
        // Initialize later (after message loop starts) to avoid cross-thread/Invoke issues.
        _ui = new SynchronizationContext();

        Text = "UniScan PC Agent";
        Width = 520;
        Height = 640;
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Color.White;
        ForeColor = Color.FromArgb(17, 17, 17);
        Font = BaseFont;

        _lstLog.DataSource = _log;

        _cmbSuffixKey.Items.AddRange(new object[] { "Enter", "Tab", "None" });
        _cmbSuffixKey.SelectedIndex = 0;

        Controls.Add(BuildTabs());

        _btnSave.Click += (_, __) => SaveSettings();
        _btnAdvanced.Click += (_, __) => ToggleAdvanced();

        TryApplyTheme();
        ApplyArialRecursively(this, BaseFont);
        ApplySpecialFonts();
        UpdateDeviceConnectionOverlay("connecting...");
    }

    private Control BuildTabs()
    {
        var tabs = new TabControl
        {
            Dock = DockStyle.Fill,
            Alignment = TabAlignment.Bottom,
            SizeMode = TabSizeMode.Fixed,
            ItemSize = new Size(120, 42)
        };

        var deviceTab = new TabPage("Device") { BackColor = Color.White };
        var settingsTab = new TabPage("Settings") { BackColor = Color.White };

        deviceTab.Controls.Add(BuildDeviceTab());
        settingsTab.Controls.Add(BuildSettingsTab());

        tabs.TabPages.Add(deviceTab);
        tabs.TabPages.Add(settingsTab);
        return tabs;
    }

    private Control BuildDeviceTab()
    {
        var container = new Panel { Dock = DockStyle.Fill, BackColor = Color.White };

        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            BackColor = Color.White,
            Padding = new Padding(16),
            ColumnCount = 1,
            RowCount = 4
        };

        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 60));   // top header (fixed)
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 220));  // QR
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));       // status card
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));   // history grid

        var header = BuildPairingHeader();

        var qrWrap = new Panel { Dock = DockStyle.Fill, BackColor = Color.White, Padding = new Padding(0, 8, 0, 8) };
        _picQr.Dock = DockStyle.Fill;
        _picQr.Margin = new Padding(0);
        qrWrap.Controls.Add(_picQr);

        var statusCard = BuildStatusCard();

        var historyWrap = new Panel { Dock = DockStyle.Fill, BackColor = Color.White, Padding = new Padding(0, 10, 0, 0) };
        historyWrap.Controls.Add(_gridHistory);

        root.Controls.Add(header, 0, 0);
        root.Controls.Add(qrWrap, 0, 1);
        root.Controls.Add(statusCard, 0, 2);
        root.Controls.Add(historyWrap, 0, 3);

        ConfigureHistoryGrid();
        ConfigureDeviceConnectionOverlay();

        container.Controls.Add(root);
        container.Controls.Add(_deviceConnOverlay);
        _deviceConnOverlay.BringToFront();
        return container;
    }

    private Control BuildSettingsTab()
    {
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            BackColor = Color.White,
            Padding = new Padding(16),
            ColumnCount = 1,
            RowCount = 2
        };
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        // Basic settings: only emulation key
        var basic = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            BackColor = Color.White,
            ColumnCount = 2,
            RowCount = 1
        };
        basic.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 160));
        basic.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

        AddRow(basic, 0, "Emulation key", _cmbSuffixKey);

        var footer = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            FlowDirection = FlowDirection.LeftToRight,
            Padding = new Padding(0, 10, 0, 10)
        };
        footer.Controls.Add(_btnSave);
        footer.Controls.Add(_btnAdvanced);

        var upper = new Panel { Dock = DockStyle.Top, AutoSize = true, BackColor = Color.White };
        upper.Controls.Add(footer);
        upper.Controls.Add(basic);

        root.Controls.Add(upper, 0, 0);

        // Advanced panel (hidden by default)
        _advancedPanel.Controls.Clear();

        var advRoot = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            BackColor = Color.White,
            ColumnCount = 1,
            RowCount = 2
        };
        advRoot.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        advRoot.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        var advForm = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            BackColor = Color.White,
            ColumnCount = 2,
            RowCount = 6
        };
        advForm.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 160));
        advForm.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        AddRow(advForm, 0, "Device ID", _txtPcId);
        AddRow(advForm, 1, "Server URL", _txtServerUrl);
        AddRow(advForm, 2, "Group", _txtGroup);
        AddRow(advForm, 3, "Device name", _txtDeviceName);
        AddRow(advForm, 4, "Machine ID", _txtMachineId);
        AddRow(advForm, 5, "Target process", _txtTargetProcess);

        var advForm2 = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            BackColor = Color.White,
            ColumnCount = 2,
            RowCount = 1
        };
        advForm2.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 160));
        advForm2.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        AddRow(advForm2, 0, "Target title", _txtTargetTitle);

        var logsTitle = new Label
        {
            AutoSize = true,
            Text = "Logs",
            Font = new Font("Arial", 9f, FontStyle.Bold),
            ForeColor = Color.FromArgb(51, 51, 51),
            Padding = new Padding(0, 10, 0, 6)
        };

        var logPanel = new Panel { Dock = DockStyle.Fill, BackColor = Color.White };
        logPanel.Controls.Add(_lstLog);

        var advTop = new Panel { Dock = DockStyle.Top, AutoSize = true, BackColor = Color.White };
        advTop.Controls.Add(advForm2);
        advTop.Controls.Add(advForm);

        var advBottom = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 2,
            BackColor = Color.White
        };
        advBottom.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        advBottom.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        advBottom.Controls.Add(logsTitle, 0, 0);
        advBottom.Controls.Add(logPanel, 0, 1);

        advRoot.Controls.Add(advTop, 0, 0);
        advRoot.Controls.Add(advBottom, 0, 1);

        _advancedPanel.Controls.Add(advRoot);

        root.Controls.Add(_advancedPanel, 0, 1);
        return root;
    }

    private static void AddRow(TableLayoutPanel panel, int row, string label, Control value)
    {
        var lbl = new Label
        {
            AutoSize = true,
            Text = label,
            ForeColor = Color.FromArgb(102, 102, 102),
            Padding = new Padding(0, 6, 0, 6)
        };
        value.Margin = new Padding(0, 2, 0, 8);
        panel.Controls.Add(lbl, 0, row);
        panel.Controls.Add(value, 1, row);
    }

    public void InitializeAgentAsync()
    {
        // Must be called from UI thread (Application.Idle) to capture WinForms sync context.
        _ui = SynchronizationContext.Current ?? _ui;

        _ = Task.Run(async () =>
        {
            try
            {
                _config = AgentConfig.LoadOrCreate(_configPath);
            }
            catch (Exception ex)
            {
                AgentLog.Error("Config load/create failed.", ex);
                _config = new AgentConfig();
            }

            _ui.Post(_ =>
            {
                _txtServerUrl.Text = _config.ServerUrl;
                _txtGroup.Text = _config.Group;
                _txtDeviceName.Text = _config.DeviceName;
                _txtMachineId.Text = _config.MachineId;
                _txtTargetProcess.Text = _config.TargetWindow.ProcessName;
                _txtTargetTitle.Text = _config.TargetWindow.WindowTitleContains;
                if (string.Equals(_config.BarcodeSuffixKey, "Tab", StringComparison.OrdinalIgnoreCase))
                    _cmbSuffixKey.SelectedItem = "Tab";
                else if (string.Equals(_config.BarcodeSuffixKey, "None", StringComparison.OrdinalIgnoreCase))
                    _cmbSuffixKey.SelectedItem = "None";
                else
                    _cmbSuffixKey.SelectedItem = "Enter";
            }, null);

            _client = new WsAgentClient(_config, AppendLog, SetConnStatus, SetPcId, SetPairingCode);
            _worker = new InputQueueWorker(
                _config,
                _client,
                AppendLog,
                onQueueLengthChanged: SetQueueLength,
                onInputResult: SetLastInputResult);

            _client.OnDeliverBarcode += item =>
            {
                SetLastBarcode(item.Barcode);
                AddHistoryReceived(item);
                _worker.Enqueue(item);
            };

            await _client.StartAsync();
        });
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        base.OnFormClosing(e);
        _worker?.Dispose();
        _client?.Dispose();

        var img = _picQr.Image;
        _picQr.Image = null;
        img?.Dispose();

        var imgCode = _picCode.Image;
        _picCode.Image = null;
        imgCode?.Dispose();

        var img2 = _picOverlayConnecting.Image;
        _picOverlayConnecting.Image = null;
        img2?.Dispose();
    }

    private void TryApplyTheme()
    {
        if (!File.Exists(_themePath))
        {
            AgentLog.Info($"Theme file not found: {_themePath}");
            return;
        }

        try
        {
            IStyleSheet styleSheet = StyleSheet.FromFile(_themePath);
            IStyleApplicator applicator = new PropertyStyleApplicator(styleSheet);
            applicator.ApplyStyles(this);
            AgentLog.Info($"Theme applied: {_themePath}");
        }
        catch (Exception ex)
        {
            AgentLog.Error($"Theme apply failed: {_themePath}", ex);
        }
    }

    private void AppendLog(string message)
    {
        var line = $"[{DateTime.Now:HH:mm:ss}] {message}";
        _ui.Post(_ =>
        {
            _log.Add(line);
            if (_log.Count > 300)
            {
                // keep it small
                while (_log.Count > 250) _log.RemoveAt(0);
            }
            _lstLog.TopIndex = _log.Count - 1;
        }, null);
    }

    private void SetConnStatus(string status)
    {
        _ui.Post(_ =>
        {
            var s = status.Replace("Status:", "").Trim();
            _lblConnValue.Text = s;
            UpdateDeviceConnectionOverlay(s);
        }, null);
    }

    private void SetPcId(string pcId)
    {
        _pcId = pcId ?? "";
        _ui.Post(_ =>
        {
            _txtPcId.Text = _pcId;
            UpdateQr();
        }, null);
    }

    private void SetPairingCode(string code)
    {
        _pairingCode = code ?? "";
        _ui.Post(_ =>
        {
            _lblPairingBig.Text = string.IsNullOrWhiteSpace(_pairingCode) ? "------" : _pairingCode;
            UpdateQr();
        }, null);
    }

    private void SetQueueLength(int n)
    {
        _ui.Post(_ => _lblQueueValue.Text = n.ToString(), null);
    }

    private void SetLastBarcode(string barcode)
    {
        _ui.Post(_ => _lblLastBarcodeValue.Text = barcode ?? "-", null);
    }

    private void SetLastInputResult(InputResultInfo info)
    {
        var text = info.Ok
            ? $"OK ({info.InputMethod}, {info.AgentAttempt}/5, {info.DurationMs}ms)"
            : $"FAIL ({info.Error}, {info.InputMethod}, {info.AgentAttempt}/5)";
        _ui.Post(_ =>
        {
            _lblLastInputValue.Text = text;
            UpdateHistoryResult(info);
        }, null);
    }

    private void UpdateQr()
    {
        if (string.IsNullOrWhiteSpace(_pairingCode))
        {
            SetQrImage(null);
            return;
        }

        var payload = _pairingCode.Trim();
        var bmp = QrCodeUtil.Render(payload, pixelsPerModule: 8);
        SetQrImage(bmp);
    }

    private void SetQrImage(System.Drawing.Image? img)
    {
        var old = _picQr.Image;
        _picQr.Image = img;
        old?.Dispose();
    }

    private void SaveSettings()
    {
        _config.BarcodeSuffixKey = (_cmbSuffixKey.SelectedItem?.ToString() ?? "Enter").Trim();

        if (_advancedUnlocked)
        {
            _config.ServerUrl = _txtServerUrl.Text.Trim();
            _config.Group = _txtGroup.Text.Trim();
            _config.DeviceName = _txtDeviceName.Text.Trim();
            _config.TargetWindow.ProcessName = _txtTargetProcess.Text.Trim();
            _config.TargetWindow.WindowTitleContains = _txtTargetTitle.Text.Trim();
        }

        _config.Save(_configPath);
        AppendLog("Settings saved. Restart the app to apply connection changes.");
    }

    private static void ApplyArialRecursively(Control root, Font font)
    {
        root.Font = font;
        foreach (Control c in root.Controls)
            ApplyArialRecursively(c, font);
    }

    private void ToggleAdvanced()
    {
        if (!_advancedUnlocked)
        {
            var ok = PasswordPrompt.TryUnlock(this, "Advanced", "Enter password", "8206");
            if (!ok)
            {
                AppendLog("Advanced unlock failed.");
                return;
            }

            _advancedUnlocked = true;
            _advancedPanel.Visible = true;
            AppendLog("Advanced panel unlocked.");
            return;
        }

        _advancedPanel.Visible = !_advancedPanel.Visible;
        AppendLog(_advancedPanel.Visible ? "Advanced panel shown." : "Advanced panel hidden.");
    }

    private void ConfigureDeviceConnectionOverlay()
    {
        _deviceConnOverlay.BackColor = Color.White;
        _deviceConnOverlay.Padding = new Padding(0);

        _picOverlayConnecting.BackColor = Color.White;
        _picOverlayConnecting.Margin = new Padding(0);
        _picOverlayConnecting.TabStop = false;

        try
        {
            var baseDir = Path.GetDirectoryName(_configPath) ?? AppDomain.CurrentDomain.BaseDirectory;
            var imgPath = Path.Combine(baseDir, "assets", "connecting.png");
            if (File.Exists(imgPath))
                _picOverlayConnecting.Image = System.Drawing.Image.FromFile(imgPath);
        }
        catch
        {
            // ignore image load failure
        }

        _lblOverlayTitle.Font = new Font("Arial", 11f, FontStyle.Bold);
        _lblOverlayTitle.ForeColor = Color.FromArgb(17, 17, 17);
        _lblOverlayTitle.Padding = new Padding(0, 8, 0, 0);

        var wrap = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            BackColor = Color.White,
            ColumnCount = 1,
            RowCount = 2,
            Padding = new Padding(0),
            Margin = new Padding(0)
        };
        wrap.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        wrap.RowStyles.Add(new RowStyle(SizeType.Absolute, 220)); // image area
        wrap.RowStyles.Add(new RowStyle(SizeType.AutoSize));     // text

        wrap.Controls.Add(_picOverlayConnecting, 0, 0);
        wrap.Controls.Add(_lblOverlayTitle, 0, 1);

        _deviceConnOverlay.Controls.Clear();
        _deviceConnOverlay.Controls.Add(wrap);
    }

    private void UpdateDeviceConnectionOverlay(string statusText)
    {
        var s = (statusText ?? "").Trim().ToLowerInvariant();
        var connected = string.Equals(s, "connected", StringComparison.OrdinalIgnoreCase);

        _deviceConnOverlay.Visible = !connected;

        if (connected)
            return;

        // Minimal overlay text (requested).
        _lblOverlayTitle.Text = "Connecting.......";

        _deviceConnOverlay.BringToFront();
    }

    private void ConfigureHistoryGrid()
    {
        _gridHistory.SuspendLayout();
        _gridHistory.Columns.Clear();

        _gridHistory.VirtualMode = true;
        _gridHistory.ReadOnly = true;
        _gridHistory.AllowUserToAddRows = false;
        _gridHistory.AllowUserToDeleteRows = false;
        _gridHistory.AllowUserToResizeRows = false;
        _gridHistory.RowHeadersVisible = false;
        _gridHistory.MultiSelect = false;
        _gridHistory.SelectionMode = DataGridViewSelectionMode.FullRowSelect;
        _gridHistory.AutoGenerateColumns = false;
        _gridHistory.AutoSizeRowsMode = DataGridViewAutoSizeRowsMode.None;
        _gridHistory.RowTemplate.Height = 16;
        _gridHistory.ColumnHeadersHeight = 26;
        _gridHistory.ColumnHeadersHeightSizeMode = DataGridViewColumnHeadersHeightSizeMode.DisableResizing;
        _gridHistory.ScrollBars = ScrollBars.Vertical;
        _gridHistory.BackgroundColor = Color.White;
        _gridHistory.BorderStyle = System.Windows.Forms.BorderStyle.FixedSingle;
        _gridHistory.GridColor = Color.FromArgb(230, 230, 230);
        _gridHistory.CellBorderStyle = DataGridViewCellBorderStyle.SingleHorizontal;
        _gridHistory.ColumnHeadersBorderStyle = DataGridViewHeaderBorderStyle.Single;
        _gridHistory.EnableHeadersVisualStyles = false;

        _gridHistory.DefaultCellStyle = new DataGridViewCellStyle
        {
            BackColor = Color.White,
            ForeColor = Color.FromArgb(17, 17, 17),
            SelectionBackColor = Color.FromArgb(240, 240, 240),
            SelectionForeColor = Color.FromArgb(17, 17, 17),
            Font = BaseFont
        };

        _gridHistory.ColumnHeadersDefaultCellStyle = new DataGridViewCellStyle
        {
            BackColor = Color.White,
            ForeColor = Color.FromArgb(17, 17, 17),
            Font = new Font("Arial", 9f, FontStyle.Bold),
            Alignment = DataGridViewContentAlignment.MiddleLeft,
            Padding = new Padding(2, 0, 2, 0)
        };

        var colTime = new DataGridViewTextBoxColumn
        {
            Name = "Time",
            HeaderText = "Time",
            Width = 70,
            AutoSizeMode = DataGridViewAutoSizeColumnMode.None
        };
        var colBarcode = new DataGridViewTextBoxColumn
        {
            Name = "Barcode",
            HeaderText = "Barcode",
            MinimumWidth = 120,
            AutoSizeMode = DataGridViewAutoSizeColumnMode.Fill
        };
        var colResult = new DataGridViewTextBoxColumn
        {
            Name = "Result",
            HeaderText = "Result",
            Width = 58,
            AutoSizeMode = DataGridViewAutoSizeColumnMode.None
        };
        var colMethod = new DataGridViewTextBoxColumn
        {
            Name = "Method",
            HeaderText = "Method",
            Width = 78,
            AutoSizeMode = DataGridViewAutoSizeColumnMode.None
        };
        var colTry = new DataGridViewTextBoxColumn
        {
            Name = "Try",
            HeaderText = "Try",
            Width = 44,
            AutoSizeMode = DataGridViewAutoSizeColumnMode.None
        };
        var colMs = new DataGridViewTextBoxColumn
        {
            Name = "Ms",
            HeaderText = "ms",
            Width = 44,
            AutoSizeMode = DataGridViewAutoSizeColumnMode.None
        };

        _gridHistory.Columns.AddRange(colTime, colBarcode, colResult, colMethod, colTry, colMs);

        _gridHistory.CellValueNeeded -= GridHistory_CellValueNeeded;
        _gridHistory.CellValueNeeded += GridHistory_CellValueNeeded;

        _gridHistory.Paint -= GridHistory_Paint;
        _gridHistory.Paint += GridHistory_Paint;

        RefreshHistoryGrid(scrollToLatest: false);
        _gridHistory.ResumeLayout();
    }

    private void ApplySpecialFonts()
    {
        // Pairing code (large)
        _lblPairingBig.Font = new Font("Arial", 26f, FontStyle.Bold);
        _lblPairingBig.ForeColor = Color.FromArgb(17, 17, 17);

        // Status values (larger, mobile-like)
        _lblConnValue.Font = new Font("Arial", 12f, FontStyle.Bold);
        _lblQueueValue.Font = new Font("Arial", 12f, FontStyle.Bold);
        _lblLastInputValue.Font = new Font("Arial", 12f, FontStyle.Bold);
        _lblLastBarcodeValue.Font = new Font("Arial", 12f, FontStyle.Bold);

        // Overlay
        _lblOverlayTitle.Font = new Font("Arial", 11f, FontStyle.Bold);
    }

    private Control BuildPairingHeader()
    {
        ConfigurePairingHeaderAssets();

        var header = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            BackColor = Color.White,
            ColumnCount = 2,
            RowCount = 1,
            Padding = new Padding(0),
            Margin = new Padding(0, 0, 0, 0)
        };
        header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        header.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));

        var right = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            AutoSize = true,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            BackColor = Color.White,
            Margin = new Padding(0),
            Padding = new Padding(0)
        };

        _picCode.Width = 44;
        _picCode.Height = 44;
        right.Controls.Add(_picCode);
        right.Controls.Add(_lblPairingBig);

        header.Controls.Add(new Panel { Dock = DockStyle.Fill, BackColor = Color.White }, 0, 0);
        header.Controls.Add(right, 1, 0);
        return header;
    }

    private void ConfigurePairingHeaderAssets()
    {
        _picCode.BackColor = Color.White;
        _picCode.Margin = new Padding(0);
        _picCode.TabStop = false;

        try
        {
            var baseDir = Path.GetDirectoryName(_configPath) ?? AppDomain.CurrentDomain.BaseDirectory;
            var imgPath = Path.Combine(baseDir, "assets", "code.png");
            if (File.Exists(imgPath) && _picCode.Image == null)
                _picCode.Image = System.Drawing.Image.FromFile(imgPath);
        }
        catch
        {
            // ignore image load failure
        }

        _lblPairingBig.Margin = new Padding(6, 0, 0, 0);
        _lblPairingBig.Text = string.IsNullOrWhiteSpace(_pairingCode) ? "------" : _pairingCode;
    }

    private Control BuildStatusCard()
    {
        var card = new Panel
        {
            Dock = DockStyle.Top,
            BackColor = Color.White,
            Padding = new Padding(12),
            Margin = new Padding(0, 0, 0, 0),
            Height = 104
        };
        card.Paint += (_, e) =>
        {
            var rect = card.ClientRectangle;
            rect.Width -= 1;
            rect.Height -= 1;
            using var pen = new Pen(Color.FromArgb(230, 230, 230), 1);
            e.Graphics.DrawRectangle(pen, rect);
        };

        var table = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            BackColor = Color.White,
            ColumnCount = 2,
            RowCount = 2,
            Margin = new Padding(0),
            Padding = new Padding(0)
        };
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        table.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        table.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        table.Controls.Add(BuildStatusCell("Connection", _lblConnValue), 0, 0);
        table.Controls.Add(BuildStatusCell("Queue", _lblQueueValue), 1, 0);
        table.Controls.Add(BuildStatusCell("Last input", _lblLastInputValue), 0, 1);
        table.Controls.Add(BuildStatusCell("Last barcode", _lblLastBarcodeValue), 1, 1);

        card.Controls.Add(table);
        return card;
    }

    private static Control BuildStatusCell(string label, Label value)
    {
        var wrap = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            AutoSize = true,
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            BackColor = Color.White,
            Margin = new Padding(0),
            Padding = new Padding(0)
        };

        var lbl = new Label
        {
            AutoSize = true,
            Text = label,
            ForeColor = Color.FromArgb(102, 102, 102),
            Font = BaseFont,
            Margin = new Padding(0, 0, 0, 2)
        };

        value.AutoSize = true;
        value.ForeColor = Color.FromArgb(17, 17, 17);
        value.Margin = new Padding(0);

        wrap.Controls.Add(lbl);
        wrap.Controls.Add(value);
        return wrap;
    }

    private void GridHistory_Paint(object? sender, PaintEventArgs e)
    {
        var rect = _gridHistory.ClientRectangle;
        rect.Width -= 1;
        rect.Height -= 1;
        using var pen = new Pen(Color.FromArgb(17, 17, 17), 1);
        e.Graphics.DrawRectangle(pen, rect);
    }

    private void GridHistory_CellValueNeeded(object? sender, DataGridViewCellValueEventArgs e)
    {
        if (e.RowIndex < 0 || e.RowIndex >= _history.Count) return;
        var row = _history[e.RowIndex];

        var colName = _gridHistory.Columns[e.ColumnIndex].Name;
        switch (colName)
        {
            case "Time":
                e.Value = row.ReceivedAtUtc.ToLocalTime().ToString("HH:mm:ss");
                return;
            case "Barcode":
                e.Value = row.Barcode;
                return;
            case "Result":
                e.Value = row.HasResult ? (row.Ok ? "OK" : "FAIL") : "PENDING";
                return;
            case "Method":
                e.Value = row.HasResult ? row.InputMethod : "";
                return;
            case "Try":
                e.Value = row.HasResult ? $"{row.AgentAttempt}/5" : "";
                return;
            case "Ms":
                e.Value = row.HasResult ? row.DurationMs.ToString() : "";
                return;
        }
    }

    private void AddHistoryReceived(DeliverBarcodeItem item)
    {
        _ui.Post(_ =>
        {
            var entry = new HistoryEntry
            {
                JobId = item.JobId,
                Barcode = item.Barcode,
                ServerAttempt = item.ServerAttempt,
                ReceivedAtUtc = item.ReceivedAtUtc,
                HasResult = false
            };

            _history.Add(entry);
            TrimHistoryIfNeeded();
            RebuildHistoryIndex();
            RefreshHistoryGrid(scrollToLatest: true);
        }, null);
    }

    private void UpdateHistoryResult(InputResultInfo info)
    {
        if (string.IsNullOrWhiteSpace(info.JobId))
            return;

        if (_historyIndexByJobId.TryGetValue(info.JobId, out var idx) && idx >= 0 && idx < _history.Count)
        {
            var entry = _history[idx];
            entry.HasResult = true;
            entry.Ok = info.Ok;
            entry.InputMethod = info.InputMethod;
            entry.AgentAttempt = info.AgentAttempt;
            entry.DurationMs = info.DurationMs;
            entry.Error = info.Error;

            _gridHistory.InvalidateRow(idx);
            return;
        }

        // If we missed the receive event (rare), still record the result as a row.
        var fallback = new HistoryEntry
        {
            JobId = info.JobId,
            Barcode = info.Barcode,
            ReceivedAtUtc = info.AtUtc,
            HasResult = true,
            Ok = info.Ok,
            InputMethod = info.InputMethod,
            AgentAttempt = info.AgentAttempt,
            DurationMs = info.DurationMs,
            Error = info.Error
        };

        _history.Add(fallback);
        TrimHistoryIfNeeded();
        RebuildHistoryIndex();
        RefreshHistoryGrid(scrollToLatest: true);
    }

    private void TrimHistoryIfNeeded()
    {
        while (_history.Count > MaxHistoryRows)
            _history.RemoveAt(0);
    }

    private void RebuildHistoryIndex()
    {
        _historyIndexByJobId.Clear();
        for (int i = 0; i < _history.Count; i++)
        {
            var jobId = _history[i].JobId;
            if (!string.IsNullOrWhiteSpace(jobId))
                _historyIndexByJobId[jobId] = i;
        }
    }

    private void RefreshHistoryGrid(bool scrollToLatest)
    {
        _gridHistory.RowCount = _history.Count;
        _gridHistory.Invalidate();

        if (!scrollToLatest) return;
        if (_history.Count <= 0) return;

        try
        {
            _gridHistory.FirstDisplayedScrollingRowIndex = _history.Count - 1;
        }
        catch
        {
            // ignore scrolling issues during layout/handle creation
        }
    }
}

