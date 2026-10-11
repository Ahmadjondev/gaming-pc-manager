using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace GameBooster
{
    public class LockForm : Form
    {
        private static readonly List<LockForm> ActiveLockScreens = new();
        private static IntPtr _hookId = IntPtr.Zero;
        private static LowLevelKeyboardProc? _proc;

        private readonly System.Windows.Forms.Timer _clockTimer;
        private readonly System.Windows.Forms.Timer _keepOnTopTimer;
        private readonly Label _timeLabel;
        private readonly Label _stationLabel;
        private readonly Label _messageLabel;
        private readonly Panel _cardPanel;

        private bool _allowClose = false;

        public LockForm(Screen screen, string stationName, string message = "Contact Administrator to start session")
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer, true);

            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual;
            Location = screen.Bounds.Location;
            Size = screen.Bounds.Size;
            TopMost = true;
            ShowInTaskbar = false;
            BackColor = Color.FromArgb(10, 14, 23);
            ForeColor = Color.White;

            // Card Panel container
            _cardPanel = new Panel
            {
                Size = new Size(650, 420),
                BackColor = Color.FromArgb(17, 24, 39),
            };
            _cardPanel.Paint += OnCardPaint;
            Controls.Add(_cardPanel);

            // Station Name Header
            _stationLabel = new Label
            {
                Text = stationName.ToUpper(),
                Font = new Font("Segoe UI", 16, FontStyle.Bold),
                ForeColor = Color.FromArgb(0, 240, 255),
                TextAlign = ContentAlignment.MiddleCenter,
                Dock = DockStyle.Top,
                Height = 60
            };
            _cardPanel.Controls.Add(_stationLabel);

            // Clock Label
            _timeLabel = new Label
            {
                Text = DateTime.Now.ToString("HH:mm:ss"),
                Font = new Font("Segoe UI", 48, FontStyle.Bold),
                ForeColor = Color.White,
                TextAlign = ContentAlignment.MiddleCenter,
                Dock = DockStyle.Top,
                Height = 110
            };
            _cardPanel.Controls.Add(_timeLabel);

            // Lock Icon / Status
            var statusLabel = new Label
            {
                Text = "🔒 SYSTEM LOCKED",
                Font = new Font("Segoe UI", 14, FontStyle.Bold),
                ForeColor = Color.FromArgb(239, 68, 68),
                TextAlign = ContentAlignment.MiddleCenter,
                Dock = DockStyle.Top,
                Height = 45
            };
            _cardPanel.Controls.Add(statusLabel);

            // Subtitle / instructions
            _messageLabel = new Label
            {
                Text = message,
                Font = new Font("Segoe UI", 13, FontStyle.Regular),
                ForeColor = Color.FromArgb(156, 163, 175),
                TextAlign = ContentAlignment.MiddleCenter,
                Dock = DockStyle.Fill
            };
            _cardPanel.Controls.Add(_messageLabel);

            // Center card on resize
            Resize += (s, e) => CenterCard();
            CenterCard();

            // Clock update timer
            _clockTimer = new System.Windows.Forms.Timer { Interval = 1000 };
            _clockTimer.Tick += (s, e) => _timeLabel.Text = DateTime.Now.ToString("HH:mm:ss");
            _clockTimer.Start();

            // Enforce TopMost periodically
            _keepOnTopTimer = new System.Windows.Forms.Timer { Interval = 2000 };
            _keepOnTopTimer.Tick += (s, e) =>
            {
                if (Visible)
                {
                    TopMost = true;
                    BringToFront();
                }
            };
            _keepOnTopTimer.Start();
        }

        private void CenterCard()
        {
            _cardPanel.Location = new Point(
                (ClientSize.Width - _cardPanel.Width) / 2,
                (ClientSize.Height - _cardPanel.Height) / 2
            );
        }

        private void OnCardPaint(object? sender, PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using var pen = new Pen(Color.FromArgb(55, 65, 81), 2);
            var rect = new Rectangle(1, 1, _cardPanel.Width - 3, _cardPanel.Height - 3);
            e.Graphics.DrawRectangle(pen, rect);
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (!_allowClose && e.CloseReason == CloseReason.UserClosing)
            {
                e.Cancel = true;
                return;
            }
            base.OnFormClosing(e);
        }

        public void SafeClose()
        {
            _allowClose = true;
            _clockTimer.Stop();
            _keepOnTopTimer.Stop();
            Close();
            Dispose();
        }

        public void UpdateMessage(string msg)
        {
            if (InvokeRequired)
            {
                Invoke(new Action(() => UpdateMessage(msg)));
                return;
            }
            _messageLabel.Text = msg;
        }

        // ==================== STATIC LOCK / UNLOCK CONTROLS ====================

        public static void LockAllScreens(string stationName, string message = "Contact Administrator to start session")
        {
            UnlockAllScreens();

            foreach (var screen in Screen.AllScreens)
            {
                var lockForm = new LockForm(screen, stationName, message);
                ActiveLockScreens.Add(lockForm);
                lockForm.Show();
            }

            InstallKeyboardHook();
        }

        public static void UnlockAllScreens()
        {
            UninstallKeyboardHook();

            foreach (var form in ActiveLockScreens)
            {
                try
                {
                    form.SafeClose();
                }
                catch { }
            }
            ActiveLockScreens.Clear();
        }

        public static bool IsLocked => ActiveLockScreens.Count > 0;

        // ==================== LOW-LEVEL KEYBOARD HOOK ====================

        private const int WH_KEYBOARD_LL = 13;
        private const int WM_KEYDOWN = 0x0100;
        private const int WM_SYSKEYDOWN = 0x0104;

        private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool UnhookWindowsHookEx(IntPtr hhk);

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern IntPtr GetModuleHandle(string lpModuleName);

        private static void InstallKeyboardHook()
        {
            if (_hookId == IntPtr.Zero)
            {
                _proc = HookCallback;
                using var curProcess = System.Diagnostics.Process.GetCurrentProcess();
                using var curModule = curProcess.MainModule;
                _hookId = SetWindowsHookEx(WH_KEYBOARD_LL, _proc, GetModuleHandle(curModule?.ModuleName ?? string.Empty), 0);
            }
        }

        private static void UninstallKeyboardHook()
        {
            if (_hookId != IntPtr.Zero)
            {
                UnhookWindowsHookEx(_hookId);
                _hookId = IntPtr.Zero;
            }
        }

        private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
        {
            if (nCode >= 0 && (wParam == (IntPtr)WM_KEYDOWN || wParam == (IntPtr)WM_SYSKEYDOWN))
            {
                int vkCode = Marshal.ReadInt32(lParam);
                Keys key = (Keys)vkCode;

                bool alt = (Control.ModifierKeys & Keys.Alt) != 0;
                bool ctrl = (Control.ModifierKeys & Keys.Control) != 0;

                // Intercept Windows Keys, Alt+Tab, Alt+Esc, Ctrl+Esc, Alt+F4
                if (key == Keys.LWin || key == Keys.RWin) return (IntPtr)1;
                if (alt && key == Keys.Tab) return (IntPtr)1;
                if (alt && key == Keys.Escape) return (IntPtr)1;
                if (ctrl && key == Keys.Escape) return (IntPtr)1;
                if (alt && key == Keys.F4) return (IntPtr)1;
            }
            return CallNextHookEx(_hookId, nCode, wParam, lParam);
        }
    }
}
