using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace GameRoomAgent
{
    public static class ScreenCapture
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct POINT { public int x; public int y; }

        [StructLayout(LayoutKind.Sequential)]
        private struct CURSORINFO
        {
            public int cbSize;
            public int flags;
            public IntPtr hCursor;
            public POINT ptScreenPos;
        }

        [DllImport("user32.dll")]
        private static extern bool GetCursorInfo(out CURSORINFO pci);

        [DllImport("user32.dll")]
        private static extern bool DrawIcon(IntPtr hDC, int X, int Y, IntPtr hIcon);

        private const int CURSOR_SHOWING = 0x00000001;

        // Zero-allocation reusable capture cache
        private static Bitmap? _reusableBitmap;
        private static Graphics? _reusableGraphics;
        private static int _cachedWidth;
        private static int _cachedHeight;
        private static readonly object _syncLock = new object();
        private static readonly ImageCodecInfo? _jpegEncoder = GetEncoder(ImageFormat.Jpeg);
        private static readonly MemoryStream _reusableStream = new MemoryStream(256 * 1024);

        public static byte[]? CaptureScreenBytesFast(int maxWidth = 1920, long quality = 50L)
        {
            lock (_syncLock)
            {
                try
                {
                    Rectangle bounds = Screen.PrimaryScreen?.Bounds ?? Screen.AllScreens[0].Bounds;

                    // Only allocate Bitmap once; reuse across frames
                    if (_reusableBitmap == null || _cachedWidth != bounds.Width || _cachedHeight != bounds.Height)
                    {
                        _reusableGraphics?.Dispose();
                        _reusableBitmap?.Dispose();

                        _cachedWidth = bounds.Width;
                        _cachedHeight = bounds.Height;
                        _reusableBitmap = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format24bppRgb);
                        _reusableGraphics = Graphics.FromImage(_reusableBitmap);
                    }

                    // Direct blit from primary screen
                    _reusableGraphics.CopyFromScreen(bounds.Left, bounds.Top, 0, 0, bounds.Size, CopyPixelOperation.SourceCopy);

                    // Draw cursor
                    try
                    {
                        var ci = new CURSORINFO { cbSize = Marshal.SizeOf(typeof(CURSORINFO)) };
                        if (GetCursorInfo(out ci) && ci.flags == CURSOR_SHOWING)
                        {
                            IntPtr hdc = _reusableGraphics.GetHdc();
                            try
                            {
                                DrawIcon(hdc, ci.ptScreenPos.x - bounds.Left, ci.ptScreenPos.y - bounds.Top, ci.hCursor);
                            }
                            finally
                            {
                                _reusableGraphics.ReleaseHdc(hdc);
                            }
                        }
                    }
                    catch { }

                    _reusableStream.SetLength(0);
                    _reusableStream.Position = 0;

                    if (_jpegEncoder != null)
                    {
                        using var encoderParameters = new EncoderParameters(1);
                        encoderParameters.Param[0] = new EncoderParameter(Encoder.Quality, quality);
                        _reusableBitmap.Save(_reusableStream, _jpegEncoder, encoderParameters);
                    }
                    else
                    {
                        _reusableBitmap.Save(_reusableStream, ImageFormat.Jpeg);
                    }

                    return _reusableStream.ToArray();
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[ScreenCapture] Error: {ex.Message}");
                    return null;
                }
            }
        }

        public static byte[]? CaptureScreenBytes(int maxWidth = 1920, long quality = 50L, bool drawCursor = true)
        {
            return CaptureScreenBytesFast(maxWidth, quality);
        }

        public static string? CaptureScreenBase64(int maxWidth = 1280, long quality = 50L)
        {
            byte[]? bytes = CaptureScreenBytesFast(maxWidth, quality);
            return bytes != null ? Convert.ToBase64String(bytes) : null;
        }

        private static ImageCodecInfo? GetEncoder(ImageFormat format)
        {
            ImageCodecInfo[] codecs = ImageCodecInfo.GetImageDecoders();
            foreach (ImageCodecInfo codec in codecs)
            {
                if (codec.FormatID == format.Guid)
                {
                    return codec;
                }
            }
            return null;
        }
    }
}
