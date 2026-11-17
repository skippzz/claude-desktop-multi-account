<#
.SYNOPSIS
    Gives a profile's Claude windows their own taskbar button, icon and coloured frame.

.DESCRIPTION
    Started by a profile's launcher (made by setup.ps1); you don't normally run it yourself.

    Every Claude window is "Claude" with the same icon, and Windows stacks them all on one taskbar
    button. This script waits for the profile's windows and labels each one from the outside:
    its own taskbar group, the profile's coloured icon (taskbar, Alt+Tab, title bar), the profile
    name as the button label and, with -Frame, a thin coloured border around the window with the
    profile name on a small tab at the top. It changes nothing inside the app, and exits when the
    profile is closed.

.PARAMETER DataDir
    The profile's app data folder (claude-desktop-<name>). Used to find its windows.

.PARAMETER Label
    Text for the taskbar button, e.g. "Claude C".

.PARAMETER Icon
    The profile's .ico file.

.PARAMETER Launcher
    What a pinned taskbar button should start: the profile's launcher.

.PARAMETER Color
    Frame colour as #RRGGBB.

.PARAMETER Frame
    Frame thickness in pixels (at 100% display scaling). 0 = no frame.

.PARAMETER Tab
    Text for the tab on the frame, e.g. "C". Empty = no tab.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DataDir,
    [Parameter(Mandatory)][string]$Label,
    [string]$Icon,
    [string]$Launcher,
    [ValidatePattern('^#[0-9A-Fa-f]{6}$')][string]$Color = '#808080',
    [ValidateRange(0, 12)][int]$Frame = 0,
    [string]$Tab,
    [int]$WaitSeconds = 90
)

$ErrorActionPreference = 'Stop'
$appId = 'ClaudeProfile.' + (Split-Path $DataDir -Leaf)

# one tagger per profile
$created = $false
$mutex = New-Object System.Threading.Mutex($true, "Local\$appId", [ref]$created)
if (-not $created) { exit 0 }

Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace ClaudeProfiles {
    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    public struct PropertyKey { public Guid fmtid; public uint pid; }

    [StructLayout(LayoutKind.Explicit)]
    public struct PropVariant {
        [FieldOffset(0)] public ushort vt;
        [FieldOffset(8)] public IntPtr ptr;
        [FieldOffset(16)] public IntPtr pad;
    }

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IPropertyStore {
        [PreserveSig] int GetCount(out uint count);
        [PreserveSig] int GetAt(uint index, out PropertyKey key);
        [PreserveSig] int GetValue(ref PropertyKey key, out PropVariant value);
        [PreserveSig] int SetValue(ref PropertyKey key, ref PropVariant value);
        [PreserveSig] int Commit();
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int L, T, R, B; }

    [StructLayout(LayoutKind.Sequential)]
    public struct MONITORINFO { public int cb; public RECT rcMonitor; public RECT rcWork; public uint flags; }

    static class Native {
        public delegate bool EnumProc(IntPtr hwnd, IntPtr lParam);
        public delegate void WinEventProc(IntPtr hook, uint ev, IntPtr hwnd, int idObject, int idChild, uint thread, uint time);
        [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
        [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
        [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hwnd);
        [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
        [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);
        [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr hwnd);
        [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hwnd, uint cmd);
        [DllImport("user32.dll", EntryPoint = "GetWindowLongW")] public static extern int GetWindowLong(IntPtr hwnd, int index);
        [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] public static extern IntPtr SetWindowLongPtr(IntPtr hwnd, int index, IntPtr value);
        [DllImport("user32.dll", EntryPoint = "SetWindowLongW")] public static extern int SetWindowLong(IntPtr hwnd, int index, int value);
        [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT r);
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int cmd);
        [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int w, int h, uint flags);
        [DllImport("user32.dll")] public static extern bool SetLayeredWindowAttributes(IntPtr hwnd, uint key, byte alpha, uint flags);
        [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);
        [DllImport("user32.dll")] public static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);
        [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hwnd);
        [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
        [DllImport("user32.dll")] public static extern IntPtr SetWinEventHook(uint min, uint max, IntPtr mod, WinEventProc proc, uint pid, uint thread, uint flags);
        [DllImport("user32.dll")] public static extern bool UnhookWinEvent(IntPtr hook);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint msg, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr LoadImage(IntPtr inst, string name, uint type, int cx, int cy, uint load);
        [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
        [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out RECT value, int size);
        [DllImport("shell32.dll")] public static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid iid, out IPropertyStore store);
        [DllImport("ole32.dll")] public static extern int PropVariantClear(ref PropVariant pv);
    }

    // A border drawn around one Claude window. It is a separate window that Windows keeps directly
    // above the one it frames (it is "owned" by it), is hollow in the middle and lets every click
    // through, so the app underneath behaves exactly as before.
    class FrameWindow : Form {
        public readonly IntPtr Target;
        readonly int thickness;
        readonly string tab;
        Rectangle tabRect;
        Size shapedFor;
        Point placedAt = new Point(int.MinValue, 0);
        bool showing;

        public FrameWindow(IntPtr target, Color color, int thickness, string tab) {
            Target = target; this.thickness = thickness; this.tab = tab;
            // ShowInTaskbar stays on: turning it off makes WinForms give the form a hidden owner of its
            // own. The tool-window style below keeps it off the taskbar instead.
            FormBorderStyle = FormBorderStyle.None; StartPosition = FormStartPosition.Manual;
            BackColor = color;
            ForeColor = color.GetBrightness() > 0.62 ? Color.FromArgb(24, 24, 27) : Color.White;
            SetStyle(ControlStyles.ResizeRedraw | ControlStyles.OptimizedDoubleBuffer, true);
        }

        protected override bool ShowWithoutActivation { get { return true; } }

        protected override CreateParams CreateParams {
            get {
                CreateParams cp = base.CreateParams;
                cp.Style = unchecked((int)0x80000000);                 // WS_POPUP
                cp.ExStyle |= 0x80000 | 0x20 | 0x08000000 | 0x80;      // LAYERED, TRANSPARENT (click-through), NOACTIVATE, TOOLWINDOW
                cp.ExStyle &= ~0x40000;                                // not APPWINDOW
                cp.Parent = Target;                                    // owner: stay just above the framed window
                return cp;
            }
        }

        protected override void OnHandleCreated(EventArgs e) {
            base.OnHandleCreated(e);
            Native.SetLayeredWindowAttributes(Handle, 0, 255, 2);
        }

        // Makes the framed window this one's owner, so Windows keeps the frame directly above it
        // and nowhere else. WinForms clears the owner while it creates the form, so this is set
        // (and re-checked) afterwards.
        void Attach() {
            if (Native.GetWindow(Handle, 4) == Target) return;
            if (IntPtr.Size == 8) Native.SetWindowLongPtr(Handle, -8, Target); else Native.SetWindowLong(Handle, -8, Target.ToInt32());
            showing = false;   // place it again, now above its owner
        }

        void Hide2() { if (showing) { Native.ShowWindow(Handle, 0); showing = false; } }

        // Moves the frame onto the window it belongs to. False once that window is gone.
        public bool Sync() {
            if (IsDisposed || !Native.IsWindow(Target)) return false;
            Attach();
            if (!Native.IsWindowVisible(Target) || Native.IsIconic(Target)) { Hide2(); return true; }
            RECT r;
            // the visible bounds: GetWindowRect also counts the invisible resize margin
            if (Native.DwmGetWindowAttribute(Target, 9, out r, 16) != 0) Native.GetWindowRect(Target, out r);
            if (Native.IsZoomed(Target)) {
                // a maximized window hangs a few pixels over the screen edge
                var mi = new MONITORINFO(); mi.cb = Marshal.SizeOf(typeof(MONITORINFO));
                if (Native.GetMonitorInfo(Native.MonitorFromWindow(Target, 2), ref mi)) {
                    r.L = Math.Max(r.L, mi.rcWork.L); r.T = Math.Max(r.T, mi.rcWork.T);
                    r.R = Math.Min(r.R, mi.rcWork.R); r.B = Math.Min(r.B, mi.rcWork.B);
                }
            }
            int w = r.R - r.L, h = r.B - r.T;
            if (w < 50 || h < 50) { Hide2(); return true; }

            var size = new Size(w, h);
            bool resized = size != shapedFor;
            if (resized) { Shape(size); shapedFor = size; }
            if (!showing || resized || placedAt != new Point(r.L, r.T)) {
                // NOACTIVATE | NOZORDER | NOOWNERZORDER | SHOWWINDOW
                Native.SetWindowPos(Handle, IntPtr.Zero, r.L, r.T, w, h, 0x10 | 0x4 | 0x200 | 0x40);
                placedAt = new Point(r.L, r.T); showing = true;
            }
            // Keep the frame directly above its window in the stacking order, so it never shows
            // through another window that covers this one.
            IntPtr above = Native.GetWindow(Target, 3);   // GW_HWNDPREV
            if (above != Handle) {
                // NOMOVE | NOSIZE | NOACTIVATE | NOOWNERZORDER
                Native.SetWindowPos(Handle, above == IntPtr.Zero ? IntPtr.Zero : above, 0, 0, 0, 0, 0x2 | 0x1 | 0x10 | 0x200);
            }
            return true;
        }

        void Shape(Size size) {
            double scale = 1;
            try { uint dpi = Native.GetDpiForWindow(Target); if (dpi > 0) scale = dpi / 96.0; } catch (EntryPointNotFoundException) { }
            int t = Math.Max(1, (int)Math.Round(thickness * scale));
            var region = new Region(new Rectangle(0, 0, size.Width, size.Height));
            region.Exclude(new Rectangle(t, t, size.Width - 2 * t, size.Height - 2 * t));
            tabRect = Rectangle.Empty;
            if (!string.IsNullOrEmpty(tab)) {
                int th = (int)Math.Round(15 * scale);
                using (Font f = TabFont(th))
                using (Graphics g = CreateGraphics()) {
                    int tw = (int)Math.Ceiling(g.MeasureString(tab, f).Width) + (int)Math.Round(10 * scale);
                    tabRect = new Rectangle((size.Width - tw) / 2, t, tw, th);
                }
                region.Union(tabRect);
            }
            Region = region;
            Invalidate();
        }

        static Font TabFont(int tabHeight) {
            return new Font("Segoe UI", tabHeight * 0.74f, FontStyle.Bold, GraphicsUnit.Pixel);
        }

        protected override void OnPaint(PaintEventArgs e) {
            if (tabRect.IsEmpty) return;
            e.Graphics.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAlias;
            using (Font f = TabFont(tabRect.Height))
            using (var brush = new SolidBrush(ForeColor))
            using (var fmt = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center }) {
                var box = new RectangleF(tabRect.X, tabRect.Y - tabRect.Height * 0.08f, tabRect.Width, tabRect.Height);
                e.Graphics.DrawString(tab, f, brush, box, fmt);
            }
        }
    }

    public static class Tagger {
        static readonly Guid AppUserModel = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");
        static readonly Dictionary<IntPtr, FrameWindow> frames = new Dictionary<IntPtr, FrameWindow>();
        static readonly HashSet<IntPtr> tagged = new HashSet<IntPtr>();
        static Native.WinEventProc onEvent;   // kept in a field so it isn't collected while hooked

        // visible, unowned top-level windows of one process
        static List<IntPtr> Windows(uint pid) {
            var found = new List<IntPtr>();
            Native.EnumWindows(delegate(IntPtr h, IntPtr l) {
                uint p; Native.GetWindowThreadProcessId(h, out p);
                if (p == pid && Native.IsWindowVisible(h) && Native.GetWindow(h, 4) == IntPtr.Zero) found.Add(h);
                return true;
            }, IntPtr.Zero);
            return found;
        }

        static int Set(IPropertyStore store, uint id, string value) {
            var key = new PropertyKey { fmtid = AppUserModel, pid = id };
            var pv = new PropVariant();
            if (value != null) { pv.vt = 31; pv.ptr = Marshal.StringToCoTaskMemUni(value); }   // VT_LPWSTR
            int hr = store.SetValue(ref key, ref pv);
            Native.PropVariantClear(ref pv);
            return hr;
        }

        // Taskbar identity: own button, label and icon, and what a pinned button starts.
        static void SetIdentity(IntPtr hwnd, string appId, string relaunchCommand, string label, string icon) {
            Guid iid = typeof(IPropertyStore).GUID;
            IPropertyStore store;
            if (Native.SHGetPropertyStoreForWindow(hwnd, ref iid, out store) != 0) return;
            try {
                // the relaunch values only count while the window has its own id, and are read when it is set
                Set(store, 2, relaunchCommand);                        // RelaunchCommand
                Set(store, 4, relaunchCommand == null ? null : label); // RelaunchDisplayNameResource
                Set(store, 3, icon);                                   // RelaunchIconResource
                Set(store, 5, appId);                                  // ID
            } finally { Marshal.ReleaseComObject(store); }
        }

        static IntPtr LoadIcon(string path, bool small) {
            int size = Native.GetSystemMetrics(small ? 49 : 11);   // SM_CXSMICON / SM_CXICON
            return Native.LoadImage(IntPtr.Zero, path, 1, size, size, 0x10);   // IMAGE_ICON, LR_LOADFROMFILE
        }

        // Only the app's real windows get a frame: resizable and of a normal size. Small helper
        // windows (quick entry, popups) are left alone.
        static bool Frameable(IntPtr hwnd) {
            if ((Native.GetWindowLong(hwnd, -16) & 0x40000) == 0) return false;   // WS_THICKFRAME
            RECT r; Native.GetWindowRect(hwnd, out r);
            return Native.IsIconic(hwnd) || (r.R - r.L >= 400 && r.B - r.T >= 300);
        }

        // Tags the process's windows and keeps doing so until it exits. Blocks.
        public static void Run(int pid, string appId, string relaunchCommand, string label, string iconPath, Color color, int frame, string tab) {
            // work in real pixels on every monitor, whatever its scaling
            try { Native.SetThreadDpiAwarenessContext(new IntPtr(-4)); } catch (EntryPointNotFoundException) { }
            Process process;
            try { process = Process.GetProcessById(pid); } catch (ArgumentException) { return; }

            IntPtr small = IntPtr.Zero, big = IntPtr.Zero;
            if (iconPath != null) { small = LoadIcon(iconPath, true); big = LoadIcon(iconPath, false); }
            string iconRes = iconPath == null ? null : iconPath + ",0";

            EventHandler scan = delegate {
                if (process.HasExited) { Application.ExitThread(); return; }
                foreach (IntPtr h in Windows((uint)pid)) {
                    if (tagged.Add(h)) {
                        SetIdentity(h, appId, relaunchCommand, label, iconRes);
                        if (iconPath != null) {
                            IntPtr r;
                            Native.SendMessageTimeout(h, 0x80, IntPtr.Zero, small, 2, 1000, out r);   // WM_SETICON, ICON_SMALL
                            Native.SendMessageTimeout(h, 0x80, new IntPtr(1), big, 2, 1000, out r);   // ICON_BIG
                        }
                    }
                    if (frame > 0 && !frames.ContainsKey(h) && Frameable(h)) {
                        var f = new FrameWindow(h, color, frame, tab);
                        IntPtr unused = f.Handle;   // creates the window without showing it
                        frames[h] = f;
                    }
                }
                foreach (IntPtr h in new List<IntPtr>(frames.Keys)) {
                    if (!frames[h].Sync()) { frames[h].Dispose(); frames.Remove(h); tagged.Remove(h); }
                }
            };

            // follow moves, resizes, show and hide as they happen; the timer catches everything else
            onEvent = delegate(IntPtr hook, uint ev, IntPtr hwnd, int idObject, int idChild, uint thread, uint time) {
                FrameWindow f;
                if (idObject == 0 && frames.TryGetValue(hwnd, out f)) f.Sync();
            };
            IntPtr moved = Native.SetWinEventHook(0x800B, 0x800B, IntPtr.Zero, onEvent, (uint)pid, 0, 0);   // LOCATIONCHANGE
            IntPtr shown = Native.SetWinEventHook(0x8002, 0x8003, IntPtr.Zero, onEvent, (uint)pid, 0, 0);   // SHOW, HIDE

            var timer = new Timer { Interval = 500 };
            timer.Tick += scan;
            timer.Start();
            scan(null, EventArgs.Empty);
            // The frames share their input queue with the Claude window they belong to, so this
            // thread has to keep pumping messages: do no slow work in here.
            Application.Run();

            timer.Dispose();
            Native.UnhookWinEvent(moved); Native.UnhookWinEvent(shown);
            foreach (FrameWindow f in frames.Values) f.Dispose();
            frames.Clear();
        }
    }
}
'@

function Get-ProfileProcessId {
    # the app's main process is the one without a --type= argument
    $p = Get-CimInstance Win32_Process -Filter "Name='Claude.exe'" |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains($DataDir) -and $_.CommandLine -notmatch '--type=' } |
        Select-Object -First 1
    if ($p) { [int]$p.ProcessId }
}

$deadline = (Get-Date).AddSeconds($WaitSeconds)
$procId = $null
while (-not $procId -and (Get-Date) -lt $deadline) {
    $procId = Get-ProfileProcessId
    if (-not $procId) { Start-Sleep -Milliseconds 500 }
}
if (-not $procId) { exit 1 }

$iconPath = if ($Icon -and (Test-Path $Icon)) { $Icon }
$relaunch = if ($Launcher -and (Test-Path $Launcher)) { "explorer.exe `"$Launcher`"" }
$rgb      = [System.Drawing.ColorTranslator]::FromHtml($Color)

# returns when the profile is closed
[ClaudeProfiles.Tagger]::Run($procId, $appId, $relaunch, $Label, $iconPath, $rgb, $Frame, $Tab)
$mutex.ReleaseMutex()
