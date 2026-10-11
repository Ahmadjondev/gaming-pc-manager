using System;
using System.Drawing;
using System.Threading;
using System.Windows.Forms;

namespace GameRoomAgent
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
            }

            // Run with system tray context
            using var trayIcon = new NotifyIcon
            {
                Icon = SystemIcons.Shield,
                Text = $"Game Room Agent - {config.StationName}",
                Visible = true
            };

            var contextMenu = new ContextMenuStrip();
            var infoItem = new ToolStripMenuItem($"Station: {config.StationName} ({config.StationId})") { Enabled = false };
            var lockItem = new ToolStripMenuItem("🔒 Test Lock", null, (s, e) => LockForm.LockAllScreens(config.StationName));
            var unlockItem = new ToolStripMenuItem("🔓 Test Unlock", null, (s, e) => LockForm.UnlockAllScreens());
            var exitItem = new ToolStripMenuItem("Exit Agent", null, (s, e) =>
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
