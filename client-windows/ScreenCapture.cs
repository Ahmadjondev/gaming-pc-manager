using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Windows.Forms;

namespace GameRoomAgent
{
    public static class ScreenCapture
    {
        public static string? CaptureScreenBase64(int maxWidth = 1280, long quality = 65L)
        {
            try
            {
                Rectangle bounds = Screen.PrimaryScreen?.Bounds ?? Screen.AllScreens[0].Bounds;

                using var fullBmp = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format24bppRgb);
                using (var g = Graphics.FromImage(fullBmp))
                {
                    g.CopyFromScreen(bounds.Left, bounds.Top, 0, 0, bounds.Size, CopyPixelOperation.SourceCopy);
                }

                // Scale down if larger than maxWidth
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

                    byte[] bytes = ms.ToArray();
                    return Convert.ToBase64String(bytes);
                }
                finally
                {
                    if (needsDispose) finalBmp.Dispose();
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[ScreenCapture] Error capturing screen: {ex.Message}");
                return null;
            }
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
