param([string]$A, [string]$B, [string]$Out)
Add-Type -AssemblyName System.Drawing
$references = @([System.Drawing.Bitmap].Assembly.Location, [System.Drawing.Rectangle].Assembly.Location) + @([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -in @('System.Private.Windows.GdiPlus', 'System.Private.Windows.Core', 'System.Runtime.InteropServices') } | ForEach-Object Location)
Add-Type -ReferencedAssemblies $references -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class DiffImg
{
    public static void Make(string a, string b, string output)
    {
        using (var x = new Bitmap(a))
        using (var y = new Bitmap(b))
        {
            int w = x.Width, h = x.Height;
            var o = new Bitmap(w, h, PixelFormat.Format24bppRgb);
            var r = new Rectangle(0, 0, w, h);
            var dx = x.LockBits(r, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
            var dy = y.LockBits(r, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
            var dout = o.LockBits(r, ImageLockMode.WriteOnly, PixelFormat.Format24bppRgb);
            var px = new byte[dx.Stride * h]; var py = new byte[dy.Stride * h]; var po = new byte[dout.Stride * h];
            Marshal.Copy(dx.Scan0, px, 0, px.Length); Marshal.Copy(dy.Scan0, py, 0, py.Length);
            for (int i = 0; i < px.Length; i += 3)
            {
                int d = Math.Abs(px[i] - py[i]) + Math.Abs(px[i + 1] - py[i + 1]) + Math.Abs(px[i + 2] - py[i + 2]);
                byte v = d > 60 ? (byte)255 : (byte)(px[i] / 4);
                po[i] = v; po[i + 1] = v; po[i + 2] = v;
            }
            Marshal.Copy(po, 0, dout.Scan0, po.Length);
            x.UnlockBits(dx); y.UnlockBits(dy); o.UnlockBits(dout);
            using (var small = new Bitmap(o, w / 2, h / 2)) { small.Save(output, ImageFormat.Jpeg); }
            o.Dispose();
        }
    }
}
'@
[DiffImg]::Make($A, $B, $Out)
