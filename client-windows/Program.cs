using System;
using System.Drawing;
using System.Threading;
using System.Windows.Forms;

namespace GameBooster
{
    internal static class Program
    {
        [STAThread]
        static void Main()
        {
            ApplicationConfiguration.Initialize();

            StartupManager.RegisterCrashRecovery();

            var config = Config.Load();
            if (config.AutoStartWithWindows)
            {
                StartupManager.SetAutoStart(true);
            }

            var hardware = new HardwareMonitor();
            var syncContext = SynchronizationContext.Current ?? new WindowsFormsSynchronizationContext();
            SynchronizationContext.SetSynchronizationContext(syncContext);

            var wsManager = new WebSocketManager(config, hardware, syncContext);
            wsManager.Start();

            DirectControlServer? directServer = null;
            if (config.EnableDirectControl)
            {
                directServer = new DirectControlServer(config);
                directServer.Start();
                _ = Task.Run(() => HardwareMonitor.TrySetupUpnpPortMapping(config.ControlPort > 0 ? config.ControlPort : 48999));
            }

            // Run with system tray context
            using var trayIcon = new NotifyIcon
            {
                Icon = SystemIcons.Shield,
                Text = $"Game Booster - {config.StationName}",
                Visible = true
            };

            var contextMenu = new ContextMenuStrip();
            var infoItem = new ToolStripMenuItem($"Game Booster: {config.StationName} ({config.StationId})") { Enabled = false };
            var lockItem = new ToolStripMenuItem("🔒 Test Lock", null, (s, e) => LockForm.LockAllScreens(config.StationName));
            var unlockItem = new ToolStripMenuItem("🔓 Test Unlock", null, (s, e) => LockForm.UnlockAllScreens());
            var exitItem = new ToolStripMenuItem("Exit Game Booster", null, (s, e) =>
            {
                LockForm.UnlockAllScreens();
                wsManager.Stop();
                directServer?.Stop();
                Application.Exit();
            });

            contextMenu.Items.AddRange(new ToolStripItem[] { infoItem, new ToolStripSeparator(), lockItem, unlockItem, new ToolStripSeparator(), exitItem });
            trayIcon.ContextMenuStrip = contextMenu;

            Application.ApplicationExit += (s, e) =>
            {
                trayIcon.Visible = false;
                LockForm.UnlockAllScreens();
                wsManager.Stop();
                directServer?.Stop();
            };

            Application.Run();
        }
    }
}
