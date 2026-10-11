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
        private struct POINT
        {
            public int x;
            public int y;
        }

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

        public static byte[]? CaptureScreenBytes(int maxWidth = 1920, long quality = 65L, bool drawCursor = true)
        {
            try
            {
                Rectangle bounds = Screen.PrimaryScreen?.Bounds ?? Screen.AllScreens[0].Bounds;

                using var fullBmp = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format24bppRgb);
                using (var g = Graphics.FromImage(fullBmp))
                {
                    g.CopyFromScreen(bounds.Left, bounds.Top, 0, 0, bounds.Size, CopyPixelOperation.SourceCopy);

                    if (drawCursor)
                    {
                        try
                        {
                            var ci = new CURSORINFO { cbSize = Marshal.SizeOf(typeof(CURSORINFO)) };
                            if (GetCursorInfo(out ci) && ci.flags == CURSOR_SHOWING)
                            {
                                IntPtr hdc = g.GetHdc();
                                try
                                {
                                    DrawIcon(hdc, ci.ptScreenPos.x - bounds.Left, ci.ptScreenPos.y - bounds.Top, ci.hCursor);
                                }
                                finally
                                {
                                    g.ReleaseHdc(hdc);
                                }
                            }
                        }
                        catch { }
                    }
                }

                Bitmap finalBmp = fullBmp;
                bool needsDispose = false;

                if (bounds.Width > maxWidth)
                {
                    int targetHeight = (int)((double)bounds.Height * maxWidth / bounds.Width);
                    var scaledBmp = new Bitmap(maxWidth, targetHeight, PixelFormat.Format24bppRgb);
                    using (var g = Graphics.FromImage(scaledBmp))
                    {
                        g.InterpolationMode = InterpolationMode.Bilinear;
                        g.DrawImage(fullBmp, 0, 0, maxWidth, targetHeight);
                    }
                    finalBmp = scaledBmp;
                    needsDispose = true;
                }

                try
                {
                    using var ms = new MemoryStream();
                    var encoder = GetEncoder(ImageFormat.Jpeg);
                    if (encoder != null)
                    {
                        using var encoderParameters = new EncoderParameters(1);
                        encoderParameters.Param[0] = new EncoderParameter(Encoder.Quality, quality);
                        finalBmp.Save(ms, encoder, encoderParameters);
                    }
                    else
                    {
                        finalBmp.Save(ms, ImageFormat.Jpeg);
                    }

                    return ms.ToArray();
                }
                finally
                {
                    if (needsDispose) finalBmp.Dispose();
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[ScreenCapture] Error: {ex.Message}");
                return null;
            }
        }

        public static string? CaptureScreenBase64(int maxWidth = 1280, long quality = 65L)
        {
            byte[]? bytes = CaptureScreenBytes(maxWidth, quality, drawCursor: true);
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
