$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$sourcePs1 = Join-Path $PSScriptRoot 'WinSukkiri_v1.1.ps1'
$iconPath  = Join-Path $PSScriptRoot 'WinSukkiri.ico'
$outExe    = Join-Path $PSScriptRoot 'WinSukkiri.exe'
$csPath    = Join-Path $PSScriptRoot 'WinSukkiri_Launcher.cs'

if (!(Test-Path $sourcePs1)) { throw 'WinSukkiri_v1.1.ps1 がありません。' }
if (!(Test-Path $iconPath))  { throw 'WinSukkiri.ico がありません。' }

$psBytes  = [IO.File]::ReadAllBytes($sourcePs1)
$icoBytes = [IO.File]::ReadAllBytes($iconPath)
$ps64     = [Convert]::ToBase64String($psBytes)
$ico64    = [Convert]::ToBase64String($icoBytes)

$code = @"
using System;
using System.IO;
using System.Diagnostics;
using System.Threading;
using System.Windows.Forms;
using System.Reflection;
[assembly: AssemblyTitle("Winすっきり")]
[assembly: AssemblyDescription("Windows 11の初期設定や日常設定を整理するユーティリティ")]
[assembly: AssemblyProduct("Winすっきり")]
[assembly: AssemblyCompany("morhirc")]
[assembly: AssemblyCopyright("Copyright © 2026 morhirc")]
[assembly: AssemblyVersion("1.1.0.0")]
[assembly: AssemblyFileVersion("1.1.0.0")]

internal static class Program
{
    private const string ScriptBase64 = "$ps64";
    private const string IconBase64 = "$ico64";

    [STAThread]
    private static void Main()
    {
        bool createdNew;
        using (Mutex mutex = new Mutex(true, @"Local\morhirc.WinSukkiri.Launcher", out createdNew))
        {
            if (!createdNew)
            {
                MessageBox.Show("Winすっきりは既に起動しています。", "Winすっきり",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            string dir = Path.Combine(Path.GetTempPath(), "WinSukkiri");
            Directory.CreateDirectory(dir);
            string ps1 = Path.Combine(dir, "WinSukkiri_v1.1.ps1");
            string ico = Path.Combine(dir, "WinSukkiri.ico");

            try
            {
                File.WriteAllBytes(ps1, Convert.FromBase64String(ScriptBase64));
                File.WriteAllBytes(ico, Convert.FromBase64String(IconBase64));

                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "powershell.exe";
                psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -File \"" + ps1 + "\"";
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.WindowStyle = ProcessWindowStyle.Hidden;

                using (Process p = Process.Start(psi))
                {
                    if (p != null) p.WaitForExit();
                }
            }
            finally
            {
                try { if (File.Exists(ps1)) File.Delete(ps1); } catch { }
                try { if (File.Exists(ico)) File.Delete(ico); } catch { }
            }
        }
    }
}
"@

[IO.File]::WriteAllText($csPath, $code, [Text.UTF8Encoding]::new($false))

$candidates = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)
$csc = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (!$csc) { throw 'Windows標準の C# コンパイラ csc.exe が見つかりませんでした。' }

if (Test-Path $outExe) { Remove-Item $outExe -Force }
Write-Host 'Winすっきり v1.1 EXEを作成しています...' -ForegroundColor Cyan

$args = @(
    '/nologo',
    '/target:winexe',
    '/optimize+',
    '/reference:System.Windows.Forms.dll',
    ('/win32icon:"' + $iconPath + '"'),
    ('/out:"' + $outExe + '"'),
    ('"' + $csPath + '"')
)
& $csc $args
$exitCode = $LASTEXITCODE
try { Remove-Item $csPath -Force -ErrorAction SilentlyContinue } catch {}

if ($exitCode -ne 0 -or !(Test-Path $outExe)) {
    throw "EXEの作成に失敗しました。csc.exe 終了コード: $exitCode"
}

Write-Host ''
Write-Host '完成しました:' -ForegroundColor Green
Write-Host $outExe -ForegroundColor White
