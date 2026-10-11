using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace GameBooster
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

        [DllImport("user32.dll")]
        private static extern IntPtr GetDesktopWindow();

        [DllImport("user32.dll")]
        private static extern IntPtr GetWindowDC(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

        [DllImport("gdi32.dll")]
        private static extern bool StretchBlt(
            IntPtr hdcDest, int nXOriginDest, int nYOriginDest, int nWidthDest, int nHeightDest,
            IntPtr hdcSrc, int nXOriginSrc, int nYOriginSrc, int nWidthSrc, int nHeightSrc, uint dwRop);

        [DllImport("gdi32.dll")]
        private static extern int SetStretchBltMode(IntPtr hdc, int nStretchMode);

        private const int COLORONCOLOR = 3;
        private const uint SRCCOPY = 0x00CC0020;
        private const int CURSOR_SHOWING = 0x00000001;

        // Zero-allocation reusable capture cache
        private static Bitmap? _reusableBitmap;
        private static Graphics? _reusableGraphics;
        private static int _cachedWidth;
        private static int _cachedHeight;
        private static readonly object _syncLock = new object();
        private static readonly ImageCodecInfo? _jpegEncoder = GetEncoder(ImageFormat.Jpeg);
        private static readonly MemoryStream _reusableStream = new MemoryStream(256 * 1024);

        public static byte[]? CaptureScreenBytesFast(int maxWidth = 1280, long quality = 45L)
        {
            lock (_syncLock)
            {
                try
                {
                    Rectangle bounds = Screen.PrimaryScreen?.Bounds ?? Screen.AllScreens[0].Bounds;

                    int targetWidth = bounds.Width;
                    int targetHeight = bounds.Height;

                    if (maxWidth > 0 && targetWidth > maxWidth)
                    {
                        targetHeight = (int)Math.Round((double)bounds.Height * maxWidth / bounds.Width);
                        targetWidth = maxWidth;
                    }

                    // Only allocate Bitmap when target resolution changes
                    if (_reusableBitmap == null || _cachedWidth != targetWidth || _cachedHeight != targetHeight)
                    {
                        _reusableGraphics?.Dispose();
                        _reusableBitmap?.Dispose();

                        _cachedWidth = targetWidth;
                        _cachedHeight = targetHeight;
                        _reusableBitmap = new Bitmap(targetWidth, targetHeight, PixelFormat.Format24bppRgb);
                        _reusableGraphics = Graphics.FromImage(_reusableBitmap);
                        _reusableGraphics.InterpolationMode = InterpolationMode.NearestNeighbor;
                        _reusableGraphics.CompositingQuality = CompositingQuality.HighSpeed;
                        _reusableGraphics.SmoothingMode = SmoothingMode.None;
                    }

                    // Fast hardware-assisted GDI capture
                    if (targetWidth == bounds.Width && targetHeight == bounds.Height)
                    {
                        _reusableGraphics!.CopyFromScreen(bounds.Left, bounds.Top, 0, 0, bounds.Size, CopyPixelOperation.SourceCopy);
                    }
                    else
                    {
                        IntPtr desktopWnd = GetDesktopWindow();
                        IntPtr hdcSrc = GetWindowDC(desktopWnd);
                        IntPtr hdcDest = _reusableGraphics!.GetHdc();
                        try
                        {
                            SetStretchBltMode(hdcDest, COLORONCOLOR);
                            StretchBlt(hdcDest, 0, 0, targetWidth, targetHeight,
                                       hdcSrc, bounds.Left, bounds.Top, bounds.Width, bounds.Height, SRCCOPY);
                        }
                        finally
                        {
                            _reusableGraphics.ReleaseHdc(hdcDest);
                            ReleaseDC(desktopWnd, hdcSrc);
                        }
                    }

                    // Draw cursor scaled to target resolution
                    try
                    {
                        var ci = new CURSORINFO { cbSize = Marshal.SizeOf(typeof(CURSORINFO)) };
                        if (GetCursorInfo(out ci) && ci.flags == CURSOR_SHOWING)
                        {
                            int curX = ci.ptScreenPos.x - bounds.Left;
                            int curY = ci.ptScreenPos.y - bounds.Top;
                            if (targetWidth != bounds.Width)
                            {
                                curX = (int)Math.Round((double)curX * targetWidth / bounds.Width);
                                curY = (int)Math.Round((double)curY * targetHeight / bounds.Height);
                            }

                            IntPtr hdc = _reusableGraphics!.GetHdc();
                            try
                            {
                                DrawIcon(hdc, curX, curY, ci.hCursor);
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

        public static byte[]? CaptureScreenBytes(int maxWidth = 1280, long quality = 45L, bool drawCursor = true)
        {
            return CaptureScreenBytesFast(maxWidth, quality);
        }

        public static string? CaptureScreenBase64(int maxWidth = 1280, long quality = 45L)
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
