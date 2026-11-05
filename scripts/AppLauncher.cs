using System;
using System.Diagnostics;
using System.IO;

internal static class AppLauncher
{
    [STAThread]
    private static void Main()
    {
        string directory = AppDomain.CurrentDomain.BaseDirectory;
        string[] settings = File.ReadAllLines(Path.Combine(directory, "shortcut.txt"));
        try
        {
            // Launch the desktop app before creating any overlay process.
            Process.Start(new ProcessStartInfo(settings[0]) { UseShellExecute = true });
        }
        catch (Exception error)
        {
            File.WriteAllText(Path.Combine(directory, "app-launch-error.log"), error.Message);
            return;
        }
        try
        {
            var overlay = new ProcessStartInfo(settings[1],
                "-NoProfile -STA -WindowStyle Hidden -File \"" + settings[2] + "\"")
            {
                UseShellExecute = false,
                CreateNoWindow = true
            };
            if (settings.Length > 3) overlay.EnvironmentVariables["RESET_RING_CODEX_EXE"] = settings[3];
            Process.Start(overlay);
        }
        catch (Exception error)
        {
            File.WriteAllText(Path.Combine(directory, "overlay-launch-error.log"), error.Message);
        }
    }
}
