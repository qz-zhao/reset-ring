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
            Process.Start(new ProcessStartInfo(settings[1],
                "-NoProfile -STA -WindowStyle Hidden -File \"" + settings[2] + "\"")
            {
                UseShellExecute = false,
                CreateNoWindow = true
            });
        }
        catch (Exception error)
        {
            File.WriteAllText(Path.Combine(directory, "overlay-launch-error.log"), error.Message);
        }
    }
}
