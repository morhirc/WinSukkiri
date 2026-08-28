$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$sourcePs1 = Join-Path $PSScriptRoot 'WinNoHara_v1.0.ps1'
$iconPath = Join-Path $PSScriptRoot 'WinNoHara.ico'
$outExe = Join-Path $PSScriptRoot 'WinNoHara.exe'
$csPath = Join-Path $PSScriptRoot 'WinNoHara_Launcher.cs'

if (!(Test-Path $sourcePs1)) { throw "WinNoHara_v0.97.ps1 がありません。" }
if (!(Test-Path $iconPath)) { throw "WinNoHara.ico がありません。" }

$psBytes = [IO.File]::ReadAllBytes($sourcePs1)
$icoBytes = [IO.File]::ReadAllBytes($iconPath)
$ps64 = [Convert]::ToBase64String($psBytes)
$ico64 = [Convert]::ToBase64String($icoBytes)

$code = @"
using System;
using System.IO;
using System.Diagnostics;
using System.Threading;
using System.Windows.Forms;
using System.Reflection;

[assembly: AssemblyTitle("Winの腹の中")]
[assembly: AssemblyDescription("Windowsの情報・設定・管理項目を見つけて開く参照ツール")]
[assembly: AssemblyProduct("Winの腹の中")]
[assembly: AssemblyCompany("morhirc")]
[assembly: AssemblyCopyright("Copyright © 2026 morhirc")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

internal static class Program
{
    private const string ScriptBase64 = "$ps64";
    private const string IconBase64 = "$ico64";

    [STAThread]
    private static void Main()
    {
        bool createdNew;
        using (Mutex mutex = new Mutex(true, @"Local\morhirc.WinNoHara.Launcher", out createdNew))
        {
            if (!createdNew)
            {
                MessageBox.Show(
                    "Winの腹の中は既に起動しています。",
                    "Winの腹の中",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);
                return;
            }

            string dir = Path.Combine(Path.GetTempPath(), "WinNoHara");
        Directory.CreateDirectory(dir);

        string ps1 = Path.Combine(dir, "WinNoHara.ps1");
        string ico = Path.Combine(dir, "WinNoHara.ico");

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
            psi.EnvironmentVariables["WINNOHARA_ICON"] = ico;

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

# Add-Type の -CompilerOptions は環境差があるため使わない。
# Windows標準の .NET Framework C# コンパイラ csc.exe を直接使用する。
$candidates = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)

$csc = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (!$csc) {
    throw "Windows標準の C# コンパイラ csc.exe が見つかりませんでした。"
}

if (Test-Path $outExe) { Remove-Item $outExe -Force }

Write-Host "C# コンパイラ:" -ForegroundColor DarkGray
Write-Host $csc -ForegroundColor DarkGray
Write-Host ""
Write-Host "EXEを作成しています..." -ForegroundColor Cyan

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

Write-Host ""
Write-Host "完成しました:" -ForegroundColor Green
Write-Host $outExe -ForegroundColor White
Write-Host ""
Write-Host "Explorerで古いアイコンが残る場合は、F5で更新するか、EXEを別名/別フォルダへコピーして確認してください。" -ForegroundColor Yellow
