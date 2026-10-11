using System;
using System.Diagnostics;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace GameRoomAgent
{
    public class WebSocketManager
    {
        private readonly Config _config;
        private readonly HardwareMonitor _hardwareMonitor;
        private ClientWebSocket? _webSocket;
        private CancellationTokenSource? _cts;
        private readonly SynchronizationContext _syncContext;
        private readonly SemaphoreSlim _sendLock = new SemaphoreSlim(1, 1);

        public WebSocketManager(Config config, HardwareMonitor hardwareMonitor, SynchronizationContext syncContext)
        {
            _config = config;
            _hardwareMonitor = hardwareMonitor;
            _syncContext = syncContext;
        }

        public void Start()
        {
            _cts = new CancellationTokenSource();
            Task.Run(() => ConnectionLoop(_cts.Token));
        }

        public void Stop()
        {
            _cts?.Cancel();
            try
            {
                _webSocket?.Dispose();
            }
            catch { }
        }

        private async Task ConnectionLoop(CancellationToken ct)
        {
            while (!ct.IsCancellationRequested)
            {
                try
                {
                    _webSocket = new ClientWebSocket();
                    _webSocket.Options.KeepAliveInterval = TimeSpan.FromSeconds(15);
                    Console.WriteLine($"[Agent] Connecting to {_config.ServerUrl}...");

                    using var connectCts = new CancellationTokenSource(TimeSpan.FromSeconds(8));
                    using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(ct, connectCts.Token);

                    await _webSocket.ConnectAsync(new Uri(_config.ServerUrl), linkedCts.Token);
                    Console.WriteLine("[Agent] Connected to Mac Server!");

                    // Send registration
                    await SendRegistrationAsync(ct);

                    // Run receive and telemetry loops concurrently
                    var receiveTask = ReceiveLoopAsync(ct);
                    var telemetryTask = TelemetryLoopAsync(ct);

                    await Task.WhenAny(receiveTask, telemetryTask);
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[Agent] Connection error: {ex.Message}");
                    if (_config.AutoLockOnDisconnect)
                    {
                        _syncContext.Post(_ => LockForm.LockAllScreens(_config.StationName, "Lost connection to Admin Server"), null);
                    }
                }
                finally
                {
                    try { _webSocket?.Dispose(); } catch { }
                    _webSocket = null;
                }

                if (!ct.IsCancellationRequested)
                {
                    Console.WriteLine("[Agent] Reconnecting in 4 seconds...");
                    await Task.Delay(4000, ct);
                }
            }
        }

        private async Task SendRegistrationAsync(CancellationToken ct)
        {
            var reg = new
            {
                type = "register",
                stationId = _config.StationId,
                stationName = _config.StationName,
                authToken = _config.AuthToken,
                hostname = Environment.MachineName,
                os = Environment.OSVersion.ToString(),
                ip = HardwareMonitor.GetLocalIpAddress(),
                controlPort = _config.ControlPort
            };

            await SendJsonAsync(reg, ct);
        }

        private async Task TelemetryLoopAsync(CancellationToken ct)
        {
            while (!ct.IsCancellationRequested && _webSocket?.State == WebSocketState.Open)
            {
                try
                {
                    var (ramLoad, ramTotal, ramUsed) = _hardwareMonitor.GetRamMetrics();
                    var (battery, isCharging, batteryStatus) = _hardwareMonitor.GetPowerMetrics();

                    var telemetry = new
                    {
                        type = "telemetry",
                        stationId = _config.StationId,
                        cpu = _hardwareMonitor.GetCpuUsagePercent(),
                        ram = ramLoad,
                        ramTotalGb = ramTotal,
                        ramUsedGb = ramUsed,
                        battery = battery,
                        isCharging = isCharging,
                        batteryStatus = batteryStatus,
                        activeWindow = _hardwareMonitor.GetActiveWindowTitle(),
                        isLocked = LockForm.IsLocked
                    };

                    await SendJsonAsync(telemetry, ct);
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[Agent] Telemetry error: {ex.Message}");
                    break;
                }

                await Task.Delay(TimeSpan.FromSeconds(Math.Max(1, _config.TelemetryIntervalSeconds)), ct);
            }
        }

        private async Task ReceiveLoopAsync(CancellationToken ct)
        {
            var buffer = new byte[8192];
            while (!ct.IsCancellationRequested && _webSocket?.State == WebSocketState.Open)
            {
                try
                {
                    var result = await _webSocket.ReceiveAsync(new ArraySegment<byte>(buffer), ct);
                    if (result.MessageType == WebSocketMessageType.Close)
                    {
                        Console.WriteLine("[Agent] Server closed WebSocket.");
                        break;
                    }

                    string json = Encoding.UTF8.GetString(buffer, 0, result.Count);
                    HandleServerCommand(json);
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[Agent] Receive error: {ex.Message}");
                    break;
                }
            }
        }

        private void HandleServerCommand(string json)
        {
            try
            {
                using var doc = JsonDocument.Parse(json);
                var root = doc.RootElement;
                if (!root.TryGetProperty("action", out var actionProp)) return;

                string action = actionProp.GetString() ?? string.Empty;
                Console.WriteLine($"[Agent] Received action: {action}");

                switch (action.ToLowerInvariant())
                {
                    case "lock":
                        string lockMsg = root.TryGetProperty("message", out var lm) 
                            ? lm.GetString() ?? "Station Locked by Administrator"
                            : "Station Locked by Administrator";
                        _syncContext.Post(_ => LockForm.LockAllScreens(_config.StationName, lockMsg), null);
                        break;

                    case "unlock":
                        _syncContext.Post(_ => LockForm.UnlockAllScreens(), null);
                        break;

                    case "alert":
                        string alertTitle = root.TryGetProperty("title", out var at) ? at.GetString() ?? "Notice" : "Notice";
                        string alertMsg = root.TryGetProperty("message", out var am) ? am.GetString() ?? "" : "";
                        _syncContext.Post(_ =>
                        {
                            MessageBox.Show(alertMsg, alertTitle, MessageBoxButtons.OK, MessageBoxIcon.Information, MessageBoxDefaultButton.Button1, MessageBoxOptions.DefaultDesktopOnly);
                        }, null);
                        break;

                    case "restart":
                        Process.Start(new ProcessStartInfo
                        {
                            FileName = "shutdown",
                            Arguments = "/r /t 5 /c \"Restart initiated from Admin Dashboard\"",
                            CreateNoWindow = true,
                            UseShellExecute = false
                        });
                        break;

                    case "shutdown":
                        Process.Start(new ProcessStartInfo
                        {
                            FileName = "shutdown",
                            Arguments = "/s /t 5 /c \"Shutdown initiated from Admin Dashboard\"",
                            CreateNoWindow = true,
                            UseShellExecute = false
                        });
                        break;

                    case "get_screen":
                        Task.Run(async () =>
                        {
                            string? screenB64 = ScreenCapture.CaptureScreenBase64(1280, 65);
                            if (!string.IsNullOrEmpty(screenB64))
                            {
                                await SendJsonAsync(new
                                {
                                    type = "screen_frame",
                                    stationId = _config.StationId,
                                    image = screenB64,
                                    timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
                                }, CancellationToken.None);
                            }
                        });
                        break;

                    case "get_drives":
                        Task.Run(async () =>
                        {
                            var drives = RemoteFileManager.GetDrives();
                            await SendJsonAsync(new
                            {
                                type = "drives_listing",
                                stationId = _config.StationId,
                                drives = drives
                            }, CancellationToken.None);
                        });
                        break;

                    case "browse_dir":
                        Task.Run(async () =>
                        {
                            string? path = root.TryGetProperty("path", out var pp) ? pp.GetString() : null;
                            var result = RemoteFileManager.ListDirectory(path);
                            await SendJsonAsync(new
                            {
                                type = "dir_listing",
                                stationId = _config.StationId,
                                result = result
                            }, CancellationToken.None);
                        });
                        break;

                    case "exec_file":
                        Task.Run(async () =>
                        {
                            string filePath = root.TryGetProperty("filePath", out var fp) ? fp.GetString() ?? "" : "";
                            string? args = root.TryGetProperty("arguments", out var ap) ? ap.GetString() : null;
                            var (success, msg, pid) = RemoteFileManager.ExecuteFile(filePath, args);
                            await SendJsonAsync(new
                            {
                                type = "exec_result",
                                stationId = _config.StationId,
                                filePath = filePath,
                                success = success,
                                message = msg,
                                pid = pid
                            }, CancellationToken.None);
                        });
                        break;

                    case "download_file":
                        Task.Run(async () =>
                        {
                            string url = root.TryGetProperty("url", out var up) ? up.GetString() ?? "" : "";
                            string dest = root.TryGetProperty("destinationFolder", out var dp) ? dp.GetString() ?? @"C:\Games" : @"C:\Games";
                            string? fileName = root.TryGetProperty("fileName", out var fnp) ? fnp.GetString() : null;

                            await SendJsonAsync(new
                            {
                                type = "download_status",
                                stationId = _config.StationId,
                                status = "started",
                                message = $"Starting download from {url}..."
                            }, CancellationToken.None);

                            var (success, msg) = await RemoteFileManager.DownloadFileAsync(url, dest, fileName, async (progress) =>
                            {
                                await SendJsonAsync(new
                                {
                                    type = "download_progress",
                                    stationId = _config.StationId,
                                    percent = progress
                                }, CancellationToken.None);
                            });

                            await SendJsonAsync(new
                            {
                                type = "download_status",
                                stationId = _config.StationId,
                                status = success ? "completed" : "failed",
                                message = msg
                            }, CancellationToken.None);
                        });
                        break;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Agent] Failed to handle command: {ex.Message}");
            }
        }

        private async Task SendJsonAsync(object data, CancellationToken ct)
        {
            if (_webSocket?.State != WebSocketState.Open) return;

            try
            {
                await _sendLock.WaitAsync(ct);
                if (_webSocket?.State != WebSocketState.Open) return;

                string json = JsonSerializer.Serialize(data);
                byte[] bytes = Encoding.UTF8.GetBytes(json);
                await _webSocket.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, ct);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Agent] Send error: {ex.Message}");
            }
            finally
            {
                try { _sendLock.Release(); } catch { }
            }
        }
    }
}
