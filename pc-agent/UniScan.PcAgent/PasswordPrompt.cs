using System;
using System.Drawing;
using System.Windows.Forms;

namespace UniScan.PcAgent;

internal static class PasswordPrompt
{
    public static bool TryUnlock(IWin32Window owner, string title, string message, string expected)
    {
        using var f = new Form
        {
            Text = title,
            StartPosition = FormStartPosition.CenterParent,
            FormBorderStyle = FormBorderStyle.FixedDialog,
            MinimizeBox = false,
            MaximizeBox = false,
            ShowInTaskbar = false,
            ClientSize = new Size(360, 150),
            Font = new Font("Arial", 9f, FontStyle.Regular)
        };

        var lbl = new Label
        {
            AutoSize = false,
            Text = message,
            Location = new Point(12, 12),
            Size = new Size(336, 36)
        };

        var txt = new TextBox
        {
            Location = new Point(12, 56),
            Size = new Size(336, 22),
            UseSystemPasswordChar = true
        };

        var btnOk = new Button
        {
            Text = "OK",
            DialogResult = DialogResult.OK,
            Location = new Point(192, 96),
            Size = new Size(75, 26)
        };

        var btnCancel = new Button
        {
            Text = "Cancel",
            DialogResult = DialogResult.Cancel,
            Location = new Point(273, 96),
            Size = new Size(75, 26)
        };

        f.Controls.Add(lbl);
        f.Controls.Add(txt);
        f.Controls.Add(btnOk);
        f.Controls.Add(btnCancel);
        f.AcceptButton = btnOk;
        f.CancelButton = btnCancel;

        txt.Focus();

        var r = f.ShowDialog(owner);
        if (r != DialogResult.OK) return false;
        return string.Equals((txt.Text ?? "").Trim(), expected, StringComparison.Ordinal);
    }
}

