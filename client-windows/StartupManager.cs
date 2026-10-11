using System;
using System.IO;
using System.Windows.Forms;
using Microsoft.Win32;

namespace GameRoomAgent
{
    public static class StartupManager
    {
        private const string RunRegistryKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string AppName = "GameRoomAgent";

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
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(RunRegistryKey, true);
                if (key == null) return;

                if (enable)
                {
                    string exePath = Environment.ProcessPath ?? Application.ExecutablePath;
                    key.SetValue(AppName, $"\"{exePath}\"");
                    Console.WriteLine("[Startup] Auto-start with Windows enabled in Registry.");
                }
                else
                {
                    key.DeleteValue(AppName, false);
                    Console.WriteLine("[Startup] Auto-start with Windows disabled.");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Startup] Failed to configure Registry auto-start: {ex.Message}");
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
