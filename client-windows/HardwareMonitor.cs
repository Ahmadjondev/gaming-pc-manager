using System;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace GameRoomAgent
{
    public class HardwareMonitor
    {
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetSystemTimes(out FILETIME lpIdleTime, out FILETIME lpKernelTime, out FILETIME lpUserTime);

        [StructLayout(LayoutKind.Sequential)]
        private struct FILETIME
        {
            public uint dwLowDateTime;
            public uint dwHighDateTime;

            public ulong ToUInt64() => ((ulong)dwHighDateTime << 32) | dwLowDateTime;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
        private struct MEMORYSTATUSEX
        {
            public uint dwLength;
            public uint dwMemoryLoad;
            public ulong ullTotalPhys;
            public ulong ullAvailPhys;
            public ulong ullTotalPageFile;
            public ulong ullAvailPageFile;
            public ulong ullTotalVirtual;
            public ulong ullAvailVirtual;
            public ulong ullAvailExtendedVirtual;

            public static MEMORYSTATUSEX Create()
            {
                var mem = new MEMORYSTATUSEX();
                mem.dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
                return mem;
            }
        }

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

        private ulong _prevIdleTime;
        private ulong _prevKernelTime;
        private ulong _prevUserTime;
        private bool _isFirstCpuSample = true;

        public HardwareMonitor()
        {
            InitializeCpuBaseline();
        }

        private void InitializeCpuBaseline()
        {
            if (GetSystemTimes(out var idle, out var kernel, out var user))
            {
                _prevIdleTime = idle.ToUInt64();
                _prevKernelTime = kernel.ToUInt64();
                _prevUserTime = user.ToUInt64();
                _isFirstCpuSample = false;
            }
        }

        public int GetCpuUsagePercent()
        {
            if (!GetSystemTimes(out var idle, out var kernel, out var user))
            {
                return 0;
            }

            ulong currentIdle = idle.ToUInt64();
            ulong currentKernel = kernel.ToUInt64();
            ulong currentUser = user.ToUInt64();

            if (_isFirstCpuSample)
            {
                _prevIdleTime = currentIdle;
                _prevKernelTime = currentKernel;
                _prevUserTime = currentUser;
                _isFirstCpuSample = false;
                return 0;
            }

            ulong deltaIdle = currentIdle - _prevIdleTime;
            ulong deltaKernel = currentKernel - _prevKernelTime;
            ulong deltaUser = currentUser - _prevUserTime;

            _prevIdleTime = currentIdle;
            _prevKernelTime = currentKernel;
            _prevUserTime = currentUser;

            ulong totalSysTime = deltaKernel + deltaUser;
            if (totalSysTime == 0) return 0;

            // Kernel time includes idle time in Windows NT
            ulong activeSysTime = totalSysTime >= deltaIdle ? totalSysTime - deltaIdle : 0;
            double percent = (activeSysTime * 100.0) / totalSysTime;
            return (int)Math.Clamp(Math.Round(percent), 0, 100);
        }

        public (int loadPercent, double totalGb, double usedGb) GetRamMetrics()
        {
            var mem = MEMORYSTATUSEX.Create();
            if (GlobalMemoryStatusEx(ref mem))
            {
                double total = mem.ullTotalPhys / (1024.0 * 1024.0 * 1024.0);
                double avail = mem.ullAvailPhys / (1024.0 * 1024.0 * 1024.0);
                double used = Math.Max(0, total - avail);
                return ((int)mem.dwMemoryLoad, Math.Round(total, 1), Math.Round(used, 1));
            }
            return (0, 0, 0);
        }

        public (int batteryPercent, bool isCharging, string batteryStatus) GetPowerMetrics()
        {
            try
            {
                PowerStatus status = SystemInformation.PowerStatus;
                int batteryPercent = (int)Math.Round(status.BatteryLifePercent * 100);
                bool isCharging = status.PowerLineStatus == PowerLineStatus.Online;
                string statusDesc = isCharging ? "Plugged in / Charging" : "On Battery";

                if (batteryPercent > 100 || batteryPercent < 0)
                {
                    batteryPercent = 100;
                    statusDesc = "Desktop AC Power";
                }

                return (batteryPercent, isCharging, statusDesc);
            }
            catch
            {
                return (100, true, "AC Power");
            }
        }

        public string GetActiveWindowTitle()
        {
            try
            {
                IntPtr handle = GetForegroundWindow();
                if (handle == IntPtr.Zero) return "Desktop";

                StringBuilder sb = new StringBuilder(256);
                int length = GetWindowText(handle, sb, sb.Capacity);
                if (length > 0)
                {
                    string title = sb.ToString().Trim();
                    return string.IsNullOrEmpty(title) ? "Desktop" : title;
                }
            }
            catch { }
            return "Desktop";
        }

        public static string GetLocalIpAddress()
        {
            try
            {
                using var socket = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, 0);
                socket.Connect("8.8.8.8", 65530);
                if (socket.LocalEndPoint is IPEndPoint endPoint)
                {
                    return endPoint.Address.ToString();
                }
            }
            catch
            {
                try
                {
                    var host = Dns.GetHostEntry(Dns.GetHostName());
                    foreach (var ip in host.AddressList)
                    {
                        if (ip.AddressFamily == AddressFamily.InterNetwork)
                        {
                            return ip.ToString();
                        }
                    }
                }
                catch { }
            }
            return "127.0.0.1";
        }
    }
}
