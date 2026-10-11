using System;
using System.IO;
using System.Windows.Forms;
using Microsoft.Win32;

namespace GameBooster
{
    public static class StartupManager
    {
        private const string RunRegistryKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string AppName = "GameBooster";
        private const string LegacyAppName = "GameRoomAgent";

        public static bool IsAutoStartEnabled()
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(RunRegistryKey, false);
                return key?.GetValue(AppName) != null;
            }
            catch
            {
                return false;
            }
        }

        public static void SetAutoStart(bool enable)
        {
            string exePath = Environment.ProcessPath ?? Application.ExecutablePath;

            try
            {
                // 1. Current User Registry Run
                using var keyCurrentUser = Registry.CurrentUser.OpenSubKey(RunRegistryKey, true);
                if (keyCurrentUser != null)
                {
                    keyCurrentUser.DeleteValue(LegacyAppName, false);
                    if (enable) keyCurrentUser.SetValue(AppName, $"\"{exePath}\"");
                    else keyCurrentUser.DeleteValue(AppName, false);
                }

                // 2. Local Machine Registry Run (All users fallback)
                try
                {
                    using var keyLocalMachine = Registry.LocalMachine.OpenSubKey(RunRegistryKey, true);
                    if (keyLocalMachine != null)
                    {
                        keyLocalMachine.DeleteValue(LegacyAppName, false);
                        if (enable) keyLocalMachine.SetValue(AppName, $"\"{exePath}\"");
                        else keyLocalMachine.DeleteValue(AppName, false);
                    }
                }
                catch { }

                // Clean legacy scheduled task
                try
                {
                    System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
                    {
                        FileName = "schtasks.exe",
                        Arguments = $"/delete /tn \"{LegacyAppName}\" /f",
                        CreateNoWindow = true,
                        UseShellExecute = false
                    })?.WaitForExit(2000);
                }
                catch { }

                // 3. Windows Task Scheduler (Runs with Highest Privileges on every boot / power-on)
                if (enable)
                {
                    System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
                    {
                        FileName = "schtasks.exe",
                        Arguments = $"/create /tn \"{AppName}\" /tr \"\\\"{exePath}\\\"\" /sc onlogon /rl highest /f",
                        CreateNoWindow = true,
                        UseShellExecute = false
                    })?.WaitForExit(3000);
                }
                else
                {
                    System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
                    {
                        FileName = "schtasks.exe",
                        Arguments = $"/delete /tn \"{AppName}\" /f",
                        CreateNoWindow = true,
                        UseShellExecute = false
                    })?.WaitForExit(3000);
                }

                Console.WriteLine($"[Startup] Auto-start for Game Booster configured (Enabled: {enable}).");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Startup] Failed to configure auto-start: {ex.Message}");
            }
        }

        public static void RegisterCrashRecovery()
        {
            // Windows Forms UI thread exception handler
            Application.ThreadException += (sender, args) =>
            {
                LogCrash("UI Thread Exception", args.Exception);
            };

            // Non-UI background thread exception handler
            AppDomain.CurrentDomain.UnhandledException += (sender, args) =>
            {
                if (args.ExceptionObject is Exception ex)
                {
                    LogCrash("Unhandled Domain Exception", ex);
                }
            };

            // Catch unobserved task exceptions
            System.Threading.Tasks.TaskScheduler.UnobservedTaskException += (sender, args) =>
            {
                LogCrash("Unobserved Task Exception", args.Exception);
                args.SetObserved();
            };
        }

        private static void LogCrash(string context, Exception ex)
        {
            try
            {
                string logPath = Path.Combine(AppContext.BaseDirectory, "agent_crash.log");
                string entry = $"[{DateTime.UtcNow:yyyy-MM-dd HH:mm:ss UTC}] {context}: {ex.Message}\nStack: {ex.StackTrace}\n\n";
                File.AppendAllText(logPath, entry);
                Console.WriteLine($"[Crash Recovery] Handled {context}: {ex.Message}");
            }
            catch { }
        }
    }
}
