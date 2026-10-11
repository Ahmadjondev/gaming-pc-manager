using System;
using System.Drawing;
using System.IO;
using System.Net;
using System.Net.WebSockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace GameRoomAgent
{
    public class DirectControlServer
    {
        [DllImport("user32.dll")]
        private static extern bool SetCursorPos(int X, int Y);

        [DllImport("user32.dll")]
        private static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, int dwExtraInfo);

        [DllImport("user32.dll")]
        private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, int dwExtraInfo);

        [DllImport("winmm.dll", EntryPoint = "timeBeginPeriod", SetLastError = true)]
        private static extern uint TimeBeginPeriod(uint uMilliseconds);

        [DllImport("winmm.dll", EntryPoint = "timeEndPeriod", SetLastError = true)]
        private static extern uint TimeEndPeriod(uint uMilliseconds);

        private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
        private const uint MOUSEEVENTF_LEFTUP = 0x0004;
        private const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
        private const uint MOUSEEVENTF_RIGHTUP = 0x0010;
        private const uint MOUSEEVENTF_MIDDLEDOWN = 0x0020;
        private const uint MOUSEEVENTF_MIDDLEUP = 0x0040;
        private const uint MOUSEEVENTF_WHEEL = 0x0800;

        private const uint KEYEVENTF_KEYUP = 0x0002;
        private const uint KEYEVENTF_EXTENDEDKEY = 0x0001;

        private readonly Config _config;
        private HttpListener? _listener;
        private CancellationTokenSource? _cts;

        public DirectControlServer(Config config)
        {
            _config = config;
        }

        public void Start()
        {
            try { TimeBeginPeriod(1); } catch { }
            _cts = new CancellationTokenSource();
            Task.Run(() => ListenLoopAsync(_cts.Token));
        }

        public void Stop()
        {
            _cts?.Cancel();
            try { TimeEndPeriod(1); } catch { }
            try
            {
                _listener?.Stop();
                _listener?.Close();
            }
            catch { }
        }

        private async Task ListenLoopAsync(CancellationToken ct)
        {
            int port = _config.ControlPort > 0 ? _config.ControlPort : 48999;
            string prefix = $"http://*:{port}/";

            try
            {
                _listener = new HttpListener();
                _listener.Prefixes.Add(prefix);
                _listener.Start();
                Console.WriteLine($"[DirectControl] Server listening on port {port} (LAN Direct P2P)");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[DirectControl] Warning: Failed to bind http://*:{port}/ ({ex.Message}). Trying http://+:{port}/...");
                try
                {
                    _listener = new HttpListener();
                    _listener.Prefixes.Add($"http://+:{port}/");
                    _listener.Start();
                    Console.WriteLine($"[DirectControl] Server listening on http://+:{port}/");
                }
                catch (Exception ex2)
                {
                    Console.WriteLine($"[DirectControl] Error starting Direct Control Server: {ex2.Message}");
                    return;
                }
            }

            while (!ct.IsCancellationRequested && _listener != null && _listener.IsListening)
            {
                try
                {
                    var context = await _listener.GetContextAsync();
                    _ = ProcessRequestAsync(context, ct);
                }
                catch (HttpListenerException) when (ct.IsCancellationRequested)
                {
                    break;
                }
                catch (Exception ex)
                {
                    if (!ct.IsCancellationRequested)
                    {
                        Console.WriteLine($"[DirectControl] Accept error: {ex.Message}");
                        await Task.Delay(500, ct);
                    }
                }
            }
        }

        private async Task ProcessRequestAsync(HttpListenerContext context, CancellationToken ct)
        {
            var req = context.Request;
            var res = context.Response;

            res.AddHeader("Access-Control-Allow-Origin", "*");
            res.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
            res.AddHeader("Access-Control-Allow-Headers", "Content-Type");

            if (req.HttpMethod == "OPTIONS")
            {
                res.StatusCode = 204;
                res.Close();
                return;
            }

            string path = req.Url?.AbsolutePath.ToLowerInvariant() ?? "/";

            // WebSocket Upgrade for Direct 60 FPS Stream + Input
            if (context.Request.IsWebSocketRequest && (path == "/control" || path == "/ws"))
            {
                try
                {
                    var wsContext = await context.AcceptWebSocketAsync(null);
                    Console.WriteLine($"[DirectControl] Client connected directly over LAN from {req.RemoteEndPoint}!");
                    await HandleControlWebSocketAsync(wsContext.WebSocket, ct);
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[DirectControl] WebSocket error: {ex.Message}");
                }
                return;
            }

            // Fallback MJPEG Stream
            if (path == "/stream" || path == "/mjpeg")
            {
                await HandleMjpegStreamAsync(res, ct);
                return;
            }

            // Status endpoint
            if (path == "/status" || path == "/health")
            {
                var bounds = Screen.PrimaryScreen?.Bounds ?? Screen.AllScreens[0].Bounds;
                var statusObj = new
                {
                    status = "ok",
                    stationId = _config.StationId,
                    stationName = _config.StationName,
                    screenWidth = bounds.Width,
                    screenHeight = bounds.Height,
                    fpsSupported = 60,
                    port = _config.ControlPort
                };

                byte[] data = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(statusObj));
                res.ContentType = "application/json";
                res.ContentLength64 = data.Length;
                await res.OutputStream.WriteAsync(data, ct);
                res.Close();
                return;
            }

            // ==================== DIRECT LAN FILE SYSTEM API ====================
            // 1. Get Drives
            if (path == "/api/files/drives")
            {
                var drives = RemoteFileManager.GetDrives();
                byte[] data = JsonSerializer.SerializeToUtf8Bytes(drives);
                res.ContentType = "application/json";
                res.ContentLength64 = data.Length;
                await res.OutputStream.WriteAsync(data, ct);
                res.Close();
                return;
            }

            // 2. List Directory
            if (path == "/api/files/list")
            {
                string targetPath = req.QueryString["path"] ?? "";
                var result = RemoteFileManager.ListDirectory(targetPath);
                byte[] data = JsonSerializer.SerializeToUtf8Bytes(result);
                res.ContentType = "application/json";
                res.ContentLength64 = data.Length;
                await res.OutputStream.WriteAsync(data, ct);
                res.Close();
                return;
            }

            // 3. Execute Program / Installer
            if (path == "/api/files/exec" && req.HttpMethod == "POST")
            {
                using var reader = new StreamReader(req.InputStream, req.ContentEncoding);
                string body = await reader.ReadToEndAsync(ct);
                string filePath = "";
                string? args = null;
                try
                {
                    using var doc = JsonDocument.Parse(body);
                    filePath = doc.RootElement.TryGetProperty("filePath", out var fp) ? fp.GetString() ?? "" : "";
                    args = doc.RootElement.TryGetProperty("args", out var ap) ? ap.GetString() : null;
                }
                catch { }

                var (success, msg, pid) = RemoteFileManager.ExecuteFile(filePath, args);
                byte[] data = JsonSerializer.SerializeToUtf8Bytes(new { success, message = msg, pid });
                res.ContentType = "application/json";
                res.ContentLength64 = data.Length;
                await res.OutputStream.WriteAsync(data, ct);
                res.Close();
                return;
            }

            // 4. Direct High-Speed File Upload (Mac -> Windows Laptop)
            if (path == "/api/files/upload" && req.HttpMethod == "POST")
            {
                string folder = req.QueryString["folder"] ?? "";
                string filename = req.QueryString["filename"] ?? $"upload_{DateTime.Now:yyyyMMdd_HHmmss}.bin";
                filename = Path.GetFileName(filename);

                if (string.IsNullOrWhiteSpace(folder) || !Directory.Exists(folder))
                {
                    folder = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
                }

                string destPath = Path.Combine(folder, filename);
                try
                {
                    using (var fs = new FileStream(destPath, FileMode.Create, FileAccess.Write, FileShare.None))
                    {
                        await req.InputStream.CopyToAsync(fs, ct);
                    }
                    var fi = new FileInfo(destPath);
                    byte[] data = JsonSerializer.SerializeToUtf8Bytes(new { 
                        success = true, 
                        message = $"Uploaded {filename} successfully ({RemoteFileManager.FormatFileSize(fi.Length)})", 
                        path = destPath, 
                        size = fi.Length 
                    });
                    res.ContentType = "application/json";
                    res.ContentLength64 = data.Length;
                    await res.OutputStream.WriteAsync(data, ct);
                }
                catch (Exception ex)
                {
                    res.StatusCode = 500;
                    byte[] data = JsonSerializer.SerializeToUtf8Bytes(new { success = false, message = ex.Message });
                    res.ContentType = "application/json";
                    res.ContentLength64 = data.Length;
                    await res.OutputStream.WriteAsync(data, ct);
                }
                res.Close();
                return;
            }

            // 5. Direct High-Speed File Download (Windows Laptop -> Mac)
            if (path == "/api/files/download" && req.HttpMethod == "GET")
            {
                string filePath = req.QueryString["path"] ?? "";
                if (!File.Exists(filePath))
                {
                    res.StatusCode = 404;
                    byte[] err = Encoding.UTF8.GetBytes("File not found");
                    res.ContentLength64 = err.Length;
                    await res.OutputStream.WriteAsync(err, ct);
                    res.Close();
                    return;
                }

                try
                {
                    string fn = Path.GetFileName(filePath);
                    res.ContentType = "application/octet-stream";
                    res.AddHeader("Content-Disposition", $"attachment; filename=\"{fn}\"");
                    var fi = new FileInfo(filePath);
                    res.ContentLength64 = fi.Length;
                    using (var fs = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.Read))
                    {
                        await fs.CopyToAsync(res.OutputStream, ct);
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[DirectControl] Download error: {ex.Message}");
                }
                finally
                {
                    try { res.Close(); } catch { }
                }
                return;
            }

            // 6. Delete File or Folder
            if (path == "/api/files/delete" && req.HttpMethod == "POST")
            {
                using var reader = new StreamReader(req.InputStream, req.ContentEncoding);
                string body = await reader.ReadToEndAsync(ct);
                string targetPath = "";
                try
                {
                    using var doc = JsonDocument.Parse(body);
                    targetPath = doc.RootElement.TryGetProperty("path", out var pp) ? pp.GetString() ?? "" : "";
                }
                catch { }

                var (success, msg) = RemoteFileManager.DeleteItem(targetPath);
                byte[] data = JsonSerializer.SerializeToUtf8Bytes(new { success, message = msg });
                res.ContentType = "application/json";
                res.ContentLength64 = data.Length;
                await res.OutputStream.WriteAsync(data, ct);
                res.Close();
                return;
            }

            // 7. Create Folder
            if (path == "/api/files/mkdir" && req.HttpMethod == "POST")
            {
                using var reader = new StreamReader(req.InputStream, req.ContentEncoding);
                string body = await reader.ReadToEndAsync(ct);
                string parent = "";
                string name = "";
                try
                {
                    using var doc = JsonDocument.Parse(body);
                    parent = doc.RootElement.TryGetProperty("parent", out var pr) ? pr.GetString() ?? "" : "";
                    name = doc.RootElement.TryGetProperty("name", out var nm) ? nm.GetString() ?? "" : "";
                }
                catch { }

                var (success, msg, p) = RemoteFileManager.CreateFolder(parent, name);
                byte[] data = JsonSerializer.SerializeToUtf8Bytes(new { success, message = msg, path = p });
                res.ContentType = "application/json";
                res.ContentLength64 = data.Length;
                await res.OutputStream.WriteAsync(data, ct);
                res.Close();
                return;
            }

            // 8. Download from Web URL
            if (path == "/api/files/download_url" && req.HttpMethod == "POST")
            {
                using var reader = new StreamReader(req.InputStream, req.ContentEncoding);
                string body = await reader.ReadToEndAsync(ct);
                string url = "";
                string destinationFolder = "";
                string? fileName = null;
                try
                {
                    using var doc = JsonDocument.Parse(body);
                    url = doc.RootElement.TryGetProperty("url", out var up) ? up.GetString() ?? "" : "";
                    destinationFolder = doc.RootElement.TryGetProperty("destinationFolder", out var dfp) ? dfp.GetString() ?? "" : "";
                    fileName = doc.RootElement.TryGetProperty("fileName", out var fnp) ? fnp.GetString() : null;
                }
                catch { }

                _ = Task.Run(async () =>
                {
                    await RemoteFileManager.DownloadFileAsync(url, destinationFolder, fileName);
                });

                byte[] data = JsonSerializer.SerializeToUtf8Bytes(new { success = true, message = "Download initiated" });
                res.ContentType = "application/json";
                res.ContentLength64 = data.Length;
                await res.OutputStream.WriteAsync(data, ct);
                res.Close();
                return;
            }

            res.ContentType = "text/html";
            byte[] htmlBytes = Encoding.UTF8.GetBytes($"<h3>Game Room Direct Control Server</h3><p>Station: {_config.StationName}</p><p>Status: Ready</p>");
            res.ContentLength64 = htmlBytes.Length;
            await res.OutputStream.WriteAsync(htmlBytes, ct);
            res.Close();
        }

        private async Task HandleControlWebSocketAsync(WebSocket ws, CancellationToken ct)
        {
            using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            var token = linkedCts.Token;

            int targetFps = 60;
            long quality = 45L; // Ultra-fast JPEG quality: sharp text, tiny payload (~30KB), encodes in 3ms
            int maxWidth = 1280; // 720p HD default for pure 60 FPS performance
            var sendLock = new SemaphoreSlim(1, 1);

            // Task 1: Zero-latency 60 FPS streaming loop to Mac
            var sendTask = Task.Run(async () =>
            {
                var stopwatch = new System.Diagnostics.Stopwatch();

                while (!token.IsCancellationRequested && ws.State == WebSocketState.Open)
                {
                    stopwatch.Restart();

                    // Non-blocking zero-buffer flow control:
                    // If previous frame is still traversing socket/network, skip this tick to keep latency at 0ms
                    if (sendLock.Wait(0))
                    {
                        byte[]? frame = ScreenCapture.CaptureScreenBytesFast(maxWidth, quality);
                        if (frame != null && ws.State == WebSocketState.Open)
                        {
                            _ = Task.Run(async () =>
                            {
                                try
                                {
                                    if (ws.State == WebSocketState.Open)
                                    {
                                        await ws.SendAsync(new ArraySegment<byte>(frame), WebSocketMessageType.Binary, true, token);
                                    }
                                }
                                catch { }
                                finally
                                {
                                    sendLock.Release();
                                }
                            }, token);
                        }
                        else
                        {
                            sendLock.Release();
                        }
                    }

                    stopwatch.Stop();
                    int targetInterval = 1000 / Math.Clamp(targetFps, 15, 60);
                    int delay = Math.Max(1, targetInterval - (int)stopwatch.ElapsedMilliseconds);
                    await Task.Delay(delay, token);
                }
            }, token);

            // Task 2: Input receiving & ACK loop from Mac
            var receiveTask = Task.Run(async () =>
            {
                var buffer = new byte[8192];
                while (!token.IsCancellationRequested && ws.State == WebSocketState.Open)
                {
                    try
                    {
                        var result = await ws.ReceiveAsync(new ArraySegment<byte>(buffer), token);
                        if (result.MessageType == WebSocketMessageType.Close)
                        {
                            await ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "Closing", token);
                            break;
                        }

                        if (result.MessageType == WebSocketMessageType.Text)
                        {
                            string json = Encoding.UTF8.GetString(buffer, 0, result.Count);
                            using var doc = JsonDocument.Parse(json);
                            var root = doc.RootElement;
                            string type = root.GetProperty("type").GetString() ?? "";

                            // Frame ACK from Mac -> unlocks next frame transmission immediately
                            if (type == "ack")
                            {
                                Interlocked.Exchange(ref inFlight, 0);
                                continue;
                            }

                            // Round-trip Ping / Pong measurement (< 1ms LAN response)
                            if (type == "ping")
                            {
                                double t = root.TryGetProperty("t", out var tp) ? tp.GetDouble() : 0;
                                string pongJson = $"{{\"type\":\"pong\",\"t\":{t}}}";
                                byte[] pongBytes = Encoding.UTF8.GetBytes(pongJson);
                                await sendLock.WaitAsync(token);
                                try
                                {
                                    if (ws.State == WebSocketState.Open)
                                    {
                                        await ws.SendAsync(new ArraySegment<byte>(pongBytes), WebSocketMessageType.Text, true, token);
                                    }
                                }
                                finally
                                {
                                    sendLock.Release();
                                }
                                continue;
                            }

                            switch (type)
                            {
                                case "mouse_move":
                                    if (root.TryGetProperty("x", out var xProp) && root.TryGetProperty("y", out var yProp))
                                    {
                                        double rx = xProp.GetDouble();
                                        double ry = yProp.GetDouble();
                                        var bounds = Screen.PrimaryScreen?.Bounds ?? Screen.AllScreens[0].Bounds;
                                        int tx = bounds.Left + (int)Math.Round(rx * bounds.Width);
                                        int ty = bounds.Top + (int)Math.Round(ry * bounds.Height);
                                        SetCursorPos(tx, ty);
                                    }
                                    break;

                                case "mouse_down":
                                    string downBtn = root.GetProperty("button").GetString() ?? "left";
                                    if (downBtn == "left") mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0);
                                    else if (downBtn == "right") mouse_event(MOUSEEVENTF_RIGHTDOWN, 0, 0, 0, 0);
                                    else if (downBtn == "middle") mouse_event(MOUSEEVENTF_MIDDLEDOWN, 0, 0, 0, 0);
                                    break;

                                case "mouse_up":
                                    string upBtn = root.GetProperty("button").GetString() ?? "left";
                                    if (upBtn == "left") mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0);
                                    else if (upBtn == "right") mouse_event(MOUSEEVENTF_RIGHTUP, 0, 0, 0, 0);
                                    else if (upBtn == "middle") mouse_event(MOUSEEVENTF_MIDDLEUP, 0, 0, 0, 0);
                                    break;

                                case "mouse_wheel":
                                    if (root.TryGetProperty("delta", out var deltaProp))
                                    {
                                        int delta = deltaProp.GetInt32();
                                        mouse_event(MOUSEEVENTF_WHEEL, 0, 0, (uint)delta, 0);
                                    }
                                    break;

                                case "key_down":
                                    if (root.TryGetProperty("vk", out var vkDown))
                                    {
                                        keybd_event((byte)vkDown.GetInt32(), 0, 0, 0);
                                    }
                                    break;

                                case "key_up":
                                    if (root.TryGetProperty("vk", out var vkUp))
                                    {
                                        keybd_event((byte)vkUp.GetInt32(), 0, KEYEVENTF_KEYUP, 0);
                                    }
                                    break;

                                case "special_key":
                                    string special = root.GetProperty("key").GetString() ?? "";
                                    if (special == "win")
                                    {
                                        keybd_event(0x5B, 0, 0, 0);
                                        keybd_event(0x5B, 0, KEYEVENTF_KEYUP, 0);
                                    }
                                    else if (special == "desktop")
                                    {
                                        keybd_event(0x5B, 0, 0, 0);
                                        keybd_event(0x44, 0, 0, 0);
                                        keybd_event(0x44, 0, KEYEVENTF_KEYUP, 0);
                                        keybd_event(0x5B, 0, KEYEVENTF_KEYUP, 0);
                                    }
                                    break;

                                case "set_fps":
                                    if (root.TryGetProperty("fps", out var fpsProp))
                                    {
                                        targetFps = Math.Clamp(fpsProp.GetInt32(), 15, 60);
                                    }
                                    break;

                                case "set_quality":
                                    if (root.TryGetProperty("quality", out var qProp))
                                    {
                                        quality = Math.Clamp(qProp.GetInt64(), 25L, 90L);
                                    }
                                    break;

                                case "set_resolution":
                                    if (root.TryGetProperty("maxWidth", out var resProp))
                                    {
                                        maxWidth = resProp.GetInt32();
                                    }
                                    break;
                            }
                        }
                    }
                    catch
                    {
                        break;
                    }
                }
            }, token);

            await Task.WhenAny(sendTask, receiveTask);
            linkedCts.Cancel();
            try { ws.Dispose(); } catch { }
            Console.WriteLine("[DirectControl] Client disconnected from Direct LAN stream.");
        }

        private async Task HandleMjpegStreamAsync(HttpListenerResponse res, CancellationToken ct)
        {
            res.ContentType = "multipart/x-mixed-replace; boundary=--frame";
            res.SendChunked = true;

            using var output = res.OutputStream;
            byte[] boundaryHeader = Encoding.ASCII.GetBytes("\r\n--frame\r\nContent-Type: image/jpeg\r\n\r\n");

            try
            {
                while (!ct.IsCancellationRequested)
                {
                    byte[]? frame = ScreenCapture.CaptureScreenBytesFast(1280, 50L);
                    if (frame != null)
                    {
                        await output.WriteAsync(boundaryHeader, ct);
                        await output.WriteAsync(frame, ct);
                        await output.FlushAsync(ct);
                    }
                    await Task.Delay(33, ct);
                }
            }
            catch { }
            finally
            {
                try { res.Close(); } catch { }
            }
        }
    }
}
