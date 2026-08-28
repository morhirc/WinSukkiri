Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase

# 二重起動を防止する。既に起動中なら案内して終了する。
$script:WinNoHaraMutex = $null
try {
    $createdNew = $false
    $script:WinNoHaraMutex = New-Object System.Threading.Mutex($true, "Local\morhirc.WinNoHara", [ref]$createdNew)
    if (-not $createdNew) {
        [System.Windows.MessageBox]::Show(
            "Winの腹の中は既に起動しています。",
            "Winの腹の中",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information
        ) | Out-Null
        if ($script:WinNoHaraMutex) { $script:WinNoHaraMutex.Dispose() }
        exit
    }
} catch {
    # Mutex作成に失敗した場合は、本体起動を優先する。
}

# タスクバーでPowerShellとしてグループ化されないよう、
# Winの腹の中専用のAppUserModelIDを現在プロセスへ設定する。
try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class WinNoHaraAppId
{
    [DllImport("shell32.dll", SetLastError = true)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(
        [MarshalAs(UnmanagedType.LPWStr)] string AppID);
}
"@ -ErrorAction SilentlyContinue

    [void][WinNoHaraAppId]::SetCurrentProcessExplicitAppUserModelID("morhirc.WinNoHara")
} catch {
    # AppUserModelID設定に失敗しても本体は継続する。
}

[xml]$x=@"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Winの腹の中 v1.0" Height="720" Width="1120" Background="#10151D" Foreground="White" WindowStartupLocation="CenterScreen">
<Window.Resources>
<Style TargetType="Button"><Setter Property="Margin" Value="4"/><Setter Property="Padding" Value="10,6"/><Setter Property="Background" Value="#243244"/><Setter Property="Foreground" Value="White"/></Style><Style TargetType="TextBlock"><Setter Property="Foreground" Value="#EAF1F8"/></Style>
<Style x:Key="Card" TargetType="Border"><Setter Property="Background" Value="#18212C"/><Setter Property="CornerRadius" Value="8"/><Setter Property="Padding" Value="14"/><Setter Property="Margin" Value="6"/></Style>
</Window.Resources>
<DockPanel Margin="14">
<Border DockPanel.Dock="Top" Background="#151D27" CornerRadius="10" Padding="16" Margin="0,0,0,10"><Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel><TextBlock Text="Winの腹の中" FontSize="28" FontWeight="Bold"/><TextBlock x:Name="Status" Text="" Margin="22,6,0,0" FontSize="17" FontWeight="SemiBold" Foreground="#AFC4D9" VerticalAlignment="Top" HorizontalAlignment="Left"/><TextBlock Text="見る。見つける。必要な場所を開く。" Foreground="#AFC4D9"/><TextBlock Text="掃除しません。高速化を煽りません。ただし、Windowsの腹の中はかなり見えます。" Foreground="#86C9FF" Margin="0,7,0,0"/></StackPanel><StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center"><Button x:Name="Refresh" Content="再読込"/><Button x:Name="Save" Content="診断結果を保存"/></StackPanel></Grid></Border>
<TabControl Background="#10151D">
<TabItem Header="ホーム"><ScrollViewer><StackPanel Margin="8"><UniformGrid Columns="2">
<Border Style="{StaticResource Card}"><StackPanel><TextBlock Text="Windows / PC" FontSize="18" FontWeight="Bold"/><TextBlock x:Name="PC" FontFamily="Consolas" Margin="0,10"/><WrapPanel><Button x:Name="System" Content="システムを開く"/><Button x:Name="TaskMgr" Content="タスク マネージャー"/></WrapPanel></StackPanel></Border>
<Border Style="{StaticResource Card}"><StackPanel><TextBlock Text="セキュリティ" FontSize="18" FontWeight="Bold"/><TextBlock x:Name="Security" FontFamily="Consolas" Margin="0,10"/><WrapPanel><Button x:Name="AppBrowser" Content="アプリとブラウザー コントロール"/><Button x:Name="Defender" Content="Windows セキュリティ"/><Button x:Name="Firewall" Content="ファイアウォール"/></WrapPanel></StackPanel></Border>
<Border Style="{StaticResource Card}"><StackPanel><TextBlock Text="ネットワーク" FontSize="18" FontWeight="Bold"/><TextBlock x:Name="Network" FontFamily="Consolas" Margin="0,10"/><WrapPanel><Button x:Name="NetSettings" Content="ネットワーク設定"/><Button x:Name="Adapters" Content="ネットワーク接続"/></WrapPanel></StackPanel></Border>
<Border Style="{StaticResource Card}"><StackPanel><TextBlock Text="ストレージ / デバイス" FontSize="18" FontWeight="Bold"/><TextBlock x:Name="Storage" FontFamily="Consolas" Margin="0,10"/><WrapPanel><Button x:Name="StorageSettings" Content="ストレージ設定"/><Button x:Name="DeviceMgr" Content="デバイス マネージャー"/></WrapPanel></StackPanel></Border>
</UniformGrid><Border Style="{StaticResource Card}"><StackPanel><TextBlock Text="直近のシステムイベント" FontSize="18" FontWeight="Bold"/><TextBlock x:Name="Events" FontFamily="Consolas" Margin="0,10"/><WrapPanel><Button x:Name="EventViewer" Content="イベント ビューアー"/><Button x:Name="Reliability" Content="信頼性モニター"/></WrapPanel></StackPanel></Border></StackPanel></ScrollViewer></TabItem>
<TabItem Header="コントロールパネル">
<ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Margin="14">
<TextBlock Text="クラシック設定への入口" FontSize="20" FontWeight="Bold" Margin="4,4,4,10"/>
<WrapPanel>
<Button x:Name="CPHome" Content="コントロール パネル ホーム"/>
<Button x:Name="ProgramsFeatures" Content="プログラムと機能"/>
<Button x:Name="NetworkSharing" Content="ネットワークと共有センター"/>
<Button x:Name="Adapters2" Content="ネットワーク接続"/>
<Button x:Name="PowerOptions" Content="電源オプション"/>
<Button x:Name="Sound" Content="サウンド"/>
<Button x:Name="DevicesPrinters" Content="デバイスとプリンター"/>
<Button x:Name="UserAccounts" Content="ユーザー アカウント"/>
<Button x:Name="CredentialMgr" Content="資格情報マネージャー"/>
<Button x:Name="FirewallCP" Content="Windows Defender ファイアウォール"/>
<Button x:Name="SystemProps" Content="システムのプロパティ"/>
<Button x:Name="AdvancedSystem" Content="システムの詳細設定"/>
<Button x:Name="InternetOptions" Content="インターネット オプション"/>
<Button x:Name="FolderOptions" Content="エクスプローラーのオプション"/>
<Button x:Name="DateTime" Content="日付と時刻"/>
<Button x:Name="Region" Content="地域"/>
<Button x:Name="Mouse" Content="マウス"/>
<Button x:Name="Keyboard" Content="キーボード"/>
<Button x:Name="Fonts" Content="フォント"/>
</WrapPanel></StackPanel></ScrollViewer></TabItem>

<TabItem Header="管理ツール">
<ScrollViewer VerticalScrollBarVisibility="Auto"><WrapPanel Margin="16">
<Button x:Name="Update" Content="Windows Update"/>
<Button x:Name="Startup" Content="スタートアップ アプリ"/>
<Button x:Name="StartupUser" Content="スタートアップ フォルダー（自分）"/>
<Button x:Name="StartupAll" Content="スタートアップ フォルダー（全ユーザー）"/>
<Button x:Name="Apps" Content="インストール済みアプリ"/>
<Button x:Name="Power" Content="電源とバッテリー"/>
<Button x:Name="Privacy" Content="プライバシーとセキュリティ"/>
<Button x:Name="Services" Content="サービス"/>
<Button x:Name="Scheduler" Content="タスク スケジューラ"/>
<Button x:Name="ComputerMgmt" Content="コンピューターの管理"/>
<Button x:Name="EventViewer2" Content="イベント ビューアー"/>
<Button x:Name="DeviceMgr2" Content="デバイス マネージャー"/>
<Button x:Name="Msinfo" Content="システム情報"/>
<Button x:Name="Reliability2" Content="信頼性モニター"/>
</WrapPanel></ScrollViewer></TabItem>

<TabItem Header="便利コマンド">
<Grid Margin="12">
<Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition/></Grid.RowDefinitions>
<TextBlock Text="参照系コマンド — 実行して結果を見るだけ" FontSize="20" FontWeight="Bold" Margin="4"/>
<WrapPanel Grid.Row="1" Margin="0,6,0,8">
<Button x:Name="CmdIpconfig" Content="ipconfig /all"/>
<Button x:Name="CmdNetstat" Content="netstat -ano"/>
<Button x:Name="CmdArp" Content="arp -a"/>
<Button x:Name="CmdRoute" Content="route print"/>
<Button x:Name="CmdSysteminfo" Content="systeminfo"/>
<Button x:Name="CmdDriverquery" Content="driverquery"/>
<Button x:Name="CmdNetShare" Content="net share"/>
<Button x:Name="CmdNetUse" Content="net use"/>
<Button x:Name="CmdWhoami" Content="whoami /all"/>
<Button x:Name="CmdPrefix" Content="IPv6 優先順位"/>
</WrapPanel>
<Border Grid.Row="2" Background="#151D27" CornerRadius="8" Padding="10" Margin="0,0,0,8">
<StackPanel>
<TextBlock Text="修復コマンド — Winの腹の中では実行しません" FontSize="16" FontWeight="Bold"/>
<TextBlock Text="必要な場合だけコピーし、管理者権限のターミナル等からユーザー自身で実行してください。" Foreground="#AFC4D9" Margin="0,4,0,0"/>
<WrapPanel Margin="0,5,0,0">
<Button x:Name="CopySfc" Content="sfc /scannow をコピー"/>
<Button x:Name="CopyDism" Content="DISM /RestoreHealth をコピー"/>
</WrapPanel>
</StackPanel>
</Border>
<WrapPanel Grid.Row="3" Margin="0,0,0,8">
<Button x:Name="CopyCommandResult" Content="結果をコピー"/>
</WrapPanel>
<TextBox x:Name="CommandResult" Grid.Row="4" IsReadOnly="True" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" Background="#0C1118" Foreground="#DDE8F2" FontFamily="Consolas" Padding="10"/>
</Grid></TabItem>

<TabItem Header="深掘り">
<Grid Margin="12">
<Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition/></Grid.RowDefinitions>
<TextBlock Text="Windowsの腹の中を、項目ごとに深く見る" FontSize="20" FontWeight="Bold" Margin="4,2,4,8"/>
<WrapPanel Grid.Row="1" Margin="0,0,0,8">
<Button x:Name="DeepStartup" Content="スタートアップ登録元"/>
<Button x:Name="DeepServices" Content="サービス詳細"/>
<Button x:Name="DeepTasks" Content="タスク詳細"/>
<Button x:Name="DeepEvents" Content="直近の重大・エラー"/>
<Button x:Name="DeepNetwork" Content="ネットワーク深掘り"/>
<Button x:Name="DeepShares" Content="共有 / SMB"/>
<Button x:Name="DeepDevices" Content="デバイス異常"/>
<Button x:Name="DeepStorage" Content="ストレージ"/>
<Button x:Name="DeepDrivers" Content="ドライバー"/>
<Button x:Name="DeepFeatures" Content="Windows機能"/>
<Button x:Name="DeepEnv" Content="環境変数"/>
<Button x:Name="DeepLicense" Content="ライセンス状態"/><Button x:Name="ShowOemKey" Content="OEMキーを表示"/>
<Button x:Name="DeepDump" Content="ダンプ設定"/>
<Button x:Name="DeepCopy" Content="表示内容をコピー"/>
</WrapPanel>
<TextBox x:Name="Raw" Grid.Row="2" IsReadOnly="True" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" Background="#0C1118" Foreground="#DDE8F2" FontFamily="Consolas" Padding="10"/>
</Grid>
</TabItem>
</TabControl></DockPanel></Window>
"@
$r=New-Object System.Xml.XmlNodeReader $x

$w=[Windows.Markup.XamlReader]::Load($r)

# EXEランチャーが展開した正式ICOを、WPFウィンドウにも明示的に設定。
# これによりPowerShell既定アイコンではなくWinの腹の中アイコンを表示する。
try {
    $windowIconPath = $env:WINNOHARA_ICON
    if (-not [string]::IsNullOrWhiteSpace($windowIconPath) -and (Test-Path $windowIconPath)) {
        $iconStream = [System.IO.File]::OpenRead($windowIconPath)
        try {
            $decoder = New-Object System.Windows.Media.Imaging.IconBitmapDecoder(
                $iconStream,
                [System.Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,
                [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            )
            $bestFrame = $decoder.Frames | Sort-Object PixelWidth -Descending | Select-Object -First 1
            if ($bestFrame) {
                $w.Icon = $bestFrame
            }
        }
        finally {
            $iconStream.Dispose()
        }
    }
} catch {
    # アイコン設定に失敗しても本体機能は継続する。
}

function C($n){$w.FindName($n)}
function Open($t,$a=""){try{if($a){Start-Process $t -ArgumentList $a}else{Start-Process $t}}catch{[System.Windows.MessageBox]::Show($_.Exception.Message,"Winの腹の中")|Out-Null}}
function SAC {
 try {$v=(Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy" -ErrorAction Stop).VerifiedAndReputablePolicyState
 if($null-ne $v){switch([int]$v){0{"OFF"}1{"ON"}2{"評価モード"}default{"不明 ($v)"}};return}}catch{}
 "取得できません"
}
function RebootPending {
 if((Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") -or (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired")){"あり"}else{"なし"}
}
function Collect {
 (C Status).Text="確認中..."
 $os=Get-CimInstance Win32_OperatingSystem;$cs=Get-CimInstance Win32_ComputerSystem;$cpu=Get-CimInstance Win32_Processor|Select-Object -First 1
 $up=(Get-Date)-$os.LastBootUpTime;$ram=[math]::Round($cs.TotalPhysicalMemory/1GB,1);$d=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($os.SystemDrive)'"
 $free=[math]::Round($d.FreeSpace/1GB,1);$size=[math]::Round($d.Size/1GB,1)
 try{$mp=Get-MpComputerStatus -ErrorAction Stop;$def=if($mp.AntivirusEnabled){"ON"}else{"OFF"}}catch{$def="取得できません"}
 try{$fp=Get-NetFirewallProfile -ErrorAction Stop;$fw="$(@($fp|? Enabled).Count)/$(@($fp).Count) プロファイル ON"}catch{$fw="取得できません"}
 try{$u=(Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name EnableLUA -ErrorAction Stop).EnableLUA;$uac=if($u){"ON"}else{"OFF"}}catch{$uac="取得できません"}
 $sac=SAC;$rp=RebootPending
 (C PC).Text="PC名       $env:COMPUTERNAME`nWindows    $($os.Caption)`nBuild      $($os.BuildNumber)`nCPU        $($cpu.Name)`nRAM        $ram GB`n稼働時間   $($up.Days)日 $($up.Hours)時間 $($up.Minutes)分`n再起動待ち $rp"
 (C Security).Text="Defender          $def`nFirewall          $fw`nSmart App Control $sac`nUAC               $uac"
 try{$nets=Get-NetIPConfiguration|?{$_.NetAdapter.Status-eq"Up"};$nl=@();foreach($n in $nets){$na=Get-NetAdapter -InterfaceIndex $n.InterfaceIndex -ErrorAction SilentlyContinue;$nl+="$($n.InterfaceAlias)  $($na.LinkSpeed)`nIPv4: $(($n.IPv4Address.IPAddress)-join', ')`nGW: $(($n.IPv4DefaultGateway.NextHop)-join', ')`nDNS: $(($n.DNSServer.ServerAddresses)-join', ')"};(C Network).Text=$nl-join"`n`n"}catch{(C Network).Text="取得できません"}
 try{$bad=@(Get-PnpDevice -PresentOnly|? Status-ne"OK")}catch{$bad=@()}
 (C Storage).Text="$($os.SystemDrive) 空き $free / $size GB`nデバイス異常候補 $($bad.Count) 件"
 try{$ev=Get-WinEvent -FilterHashtable @{LogName="System";Level=1,2;StartTime=(Get-Date).AddDays(-7)} -ErrorAction Stop|Select-Object -First 8 TimeCreated,Id,ProviderName,Message;$el=$ev|%{"{0:MM/dd HH:mm} ID {1} {2}"-f$_.TimeCreated,$_.Id,$_.ProviderName};(C Events).Text=if($el){$el-join"`n"}else{"該当なし"}}catch{(C Events).Text="取得できません"}
 $raw=@("=== Winの腹の中 v1.01 ===","取得日時: $(Get-Date)","","=== OS ===",($os|fl Caption,Version,BuildNumber,OSArchitecture,LastBootUpTime|Out-String),"=== Security ===","Defender: $def`nFirewall: $fw`nSmart App Control: $sac`nUAC: $uac`nReboot pending: $rp","=== Network ===")
 try{$raw+=(Get-NetIPConfiguration|fl InterfaceAlias,InterfaceDescription,IPv4Address,IPv6Address,IPv4DefaultGateway,DNSServer|Out-String)}catch{}
 $raw+="=== IPv6 Prefix Policy ===";try{$raw+=(netsh interface ipv6 show prefixpolicies|Out-String)}catch{}
 $raw+="=== Physical Disks ===";try{$raw+=(Get-PhysicalDisk|ft FriendlyName,MediaType,HealthStatus,OperationalStatus,Size -Auto|Out-String)}catch{}
 $raw+="=== Devices not OK ===";if($bad){$raw+=($bad|ft Class,FriendlyName,Status -Auto|Out-String)}else{$raw+="なし / 取得できません"}
 $raw+="=== Recent System Critical/Error ===";if($ev){$raw+=($ev|fl|Out-String)}else{$raw+="なし / 取得できません"}
 $raw+="=== Minidump ===";$dm=Get-ChildItem "$env:SystemRoot\Minidump\*.dmp" -ErrorAction SilentlyContinue|sort LastWriteTime -Descending|select -First 10 Name,Length,LastWriteTime;if($dm){$raw+=($dm|ft -Auto|Out-String)}else{$raw+="Minidumpなし"}
 (C Raw).Text=$raw-join"`r`n";(C Status).Text="確認完了 $(Get-Date -Format HH:mm:ss) ※原則読み取り専用"
}

$script:CommandBusy = $false
$script:CurrentJob = $null
$script:CommandTimer = $null

function Set-CommandButtonsEnabled([bool]$enabled) {
 foreach($n in @("CmdIpconfig","CmdNetstat","CmdArp","CmdRoute","CmdSysteminfo","CmdDriverquery","CmdNetShare","CmdNetUse","CmdWhoami","CmdPrefix")) {
  try { (C $n).IsEnabled = $enabled } catch {}
 }
}

function Finish-CommandJob {
 try {
  if($script:CurrentJob) {
   Remove-Job $script:CurrentJob -Force -ErrorAction SilentlyContinue
  }
 } catch {}
 $script:CurrentJob = $null
 $script:CommandBusy = $false
 Set-CommandButtonsEnabled $true
}

function Run-ReadOnlyCommand([string]$commandLine) {
 if($script:CommandBusy){ return }

 $script:CommandBusy = $true
 Set-CommandButtonsEnabled $false
 (C CommandResult).Text = "取得中...`r`n> $commandLine"
 (C Status).Text = "コマンド実行中: $commandLine"

 try {
  $script:CurrentJob = Start-Job -ArgumentList $commandLine -ScriptBlock {
   param($cmd)

   # netsh の日本語出力は日本語Windowsでは CP932 になるため、
   # IPv6 優先順位だけ受信側の文字コードを明示して文字化けを防ぐ。
   if($cmd -eq "netsh interface ipv6 show prefixpolicies") {
    $enc = [System.Text.Encoding]::GetEncoding(932)
    [Console]::OutputEncoding = $enc
    $OutputEncoding = $enc
   } else {
    $OutputEncoding = [Console]::OutputEncoding
   }

   & $env:ComSpec /d /c $cmd 2>&1 | Out-String -Width 4096
  }

  $script:CommandTimer = New-Object Windows.Threading.DispatcherTimer
  $script:CommandTimer.Interval = [TimeSpan]::FromMilliseconds(250)

  $script:CommandTimer.Add_Tick({
   try {
    if(-not $script:CurrentJob) { return }

    $state = $script:CurrentJob.State
    if($state -in @("Completed","Failed","Stopped")) {
     $script:CommandTimer.Stop()

     $jobOutput = ""
     try {
      $jobOutput = (Receive-Job $script:CurrentJob -ErrorAction SilentlyContinue | Out-String -Width 4096)
     } catch {}

     if([string]::IsNullOrWhiteSpace($jobOutput)) {
      if($state -eq "Failed") {
       $reason = ""
       try { $reason = $script:CurrentJob.ChildJobs[0].JobStateInfo.Reason.Message } catch {}
       if([string]::IsNullOrWhiteSpace($reason)) { $reason = "詳細を取得できませんでした。" }
       $jobOutput = "実行失敗:`r`n$reason"
      } else {
       $jobOutput = "コマンドは終了しましたが、表示できる結果がありませんでした。"
      }
     }

     (C CommandResult).Text = "> $commandLine`r`n`r`n" + $jobOutput
     (C Status).Text = if($state -eq "Completed"){"コマンド完了"}else{"実行失敗"}
     Finish-CommandJob
    }
   } catch {
    try { $script:CommandTimer.Stop() } catch {}
    (C CommandResult).Text = "実行失敗:`r`n" + $_.Exception.Message
    (C Status).Text = "実行失敗"
    Finish-CommandJob
   }
  })

  $script:CommandTimer.Start()
 } catch {
  (C CommandResult).Text = "実行失敗:`r`n" + $_.Exception.Message
  (C Status).Text = "実行失敗"
  Finish-CommandJob
 }
}


function Show-DeepResult([string]$title,[scriptblock]$work) {
 (C Raw).Text = "取得中...`r`n$title"
 (C Status).Text = "深掘り中: $title"
 try {
  $job = Start-Job -ScriptBlock $work
  $timer = New-Object Windows.Threading.DispatcherTimer
  $timer.Interval = [TimeSpan]::FromMilliseconds(250)
  $timer.Add_Tick({
   try {
    if($job.State -in @("Completed","Failed","Stopped")) {
     $timer.Stop()
     $o = Receive-Job $job -ErrorAction SilentlyContinue | Out-String -Width 4096
     if([string]::IsNullOrWhiteSpace($o)) {
      $o = if($job.State -eq "Completed"){"該当情報はありません。"}else{"取得に失敗しました。"}
     }
     (C Raw).Text = "=== $title ===`r`n取得日時: $(Get-Date -Format 'yyyy/MM/dd HH:mm:ss')`r`n`r`n$o"
     (C Status).Text = "深掘り完了"
     Remove-Job $job -Force -ErrorAction SilentlyContinue
    }
   } catch {
    try{$timer.Stop()}catch{}
    (C Raw).Text = "取得失敗:`r`n" + $_.Exception.Message
    (C Status).Text = "取得失敗"
    try{Remove-Job $job -Force -ErrorAction SilentlyContinue}catch{}
   }
  }.GetNewClosure())
  $timer.Start()
 } catch {
  (C Raw).Text = "取得失敗:`r`n" + $_.Exception.Message
  (C Status).Text = "取得失敗"
 }
}

(C DeepStartup).Add_Click({
 Show-DeepResult "スタートアップ登録元" {
  "---- HKCU Run ----"
  Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue |
   Select-Object * -ExcludeProperty PSPath,PSParentPath,PSChildName,PSDrive,PSProvider | Format-List
  "---- HKLM Run ----"
  Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue |
   Select-Object * -ExcludeProperty PSPath,PSParentPath,PSChildName,PSDrive,PSProvider | Format-List
  "---- HKLM Run (32bit) ----"
  Get-ItemProperty 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue |
   Select-Object * -ExcludeProperty PSPath,PSParentPath,PSChildName,PSDrive,PSProvider | Format-List
  "---- Startup Folder / User ----"
  Get-ChildItem ([Environment]::GetFolderPath('Startup')) -Force -ErrorAction SilentlyContinue | Select Name,FullName,LastWriteTime | Format-Table -Auto
  "---- Startup Folder / All Users ----"
  Get-ChildItem ([Environment]::GetFolderPath('CommonStartup')) -Force -ErrorAction SilentlyContinue | Select Name,FullName,LastWriteTime | Format-Table -Auto
 }
})

(C DeepServices).Add_Click({
 Show-DeepResult "サービス詳細" {
  Get-CimInstance Win32_Service | Sort-Object StartMode,Name |
   Select Name,DisplayName,State,StartMode,StartName,PathName |
   Format-Table -Auto -Wrap
 }
})

(C DeepTasks).Add_Click({
 Show-DeepResult "タスク詳細" {
  Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
   $i = $_ | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
   [pscustomobject]@{
    TaskPath=$_.TaskPath; TaskName=$_.TaskName; State=$_.State
    LastRunTime=$i.LastRunTime; LastTaskResult=$i.LastTaskResult; NextRunTime=$i.NextRunTime
   }
  } | Sort TaskPath,TaskName | Format-Table -Auto -Wrap
 }
})

(C DeepEvents).Add_Click({
 Show-DeepResult "直近の重大・エラー" {
  Get-WinEvent -FilterHashtable @{LogName='System';Level=1,2;StartTime=(Get-Date).AddDays(-7)} -MaxEvents 80 -ErrorAction SilentlyContinue |
   Select TimeCreated,Id,ProviderName,LevelDisplayName,@{n='Message';e={($_.Message -replace "`r|`n",' ')}} |
   Format-Table -Auto -Wrap
 }
})

(C DeepNetwork).Add_Click({
 Show-DeepResult "ネットワーク深掘り" {
  "---- IP Configuration ----"
  Get-NetIPConfiguration -ErrorAction SilentlyContinue | Format-List InterfaceAlias,InterfaceDescription,IPv4Address,IPv6Address,IPv4DefaultGateway,DNSServer
  "---- Adapters ----"
  Get-NetAdapter -ErrorAction SilentlyContinue | Select Name,InterfaceDescription,Status,LinkSpeed,MacAddress | Format-Table -Auto
  "---- IPv6 Prefix Policy ----"
  netsh interface ipv6 show prefixpolicies
  "---- Routes ----"
  Get-NetRoute -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select -First 80 ifIndex,DestinationPrefix,NextHop,RouteMetric,State | Format-Table -Auto
 }
})

(C DeepShares).Add_Click({
 Show-DeepResult "共有 / SMB" {
  "---- SMB Client Configuration ----"
  Get-SmbClientConfiguration -ErrorAction SilentlyContinue | Format-List
  "---- SMB Server Configuration ----"
  Get-SmbServerConfiguration -ErrorAction SilentlyContinue | Format-List
  "---- Local Shares ----"
  Get-SmbShare -ErrorAction SilentlyContinue | Select Name,Path,Description,CurrentUsers | Format-Table -Auto
  "---- SMB Connections ----"
  Get-SmbConnection -ErrorAction SilentlyContinue | Select ServerName,ShareName,UserName,Dialect,NumOpens | Format-Table -Auto
 }
})

(C DeepDevices).Add_Click({
 Show-DeepResult "デバイス異常" {
  Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
   Where-Object {$_.Status -ne 'OK'} |
   Select Status,Class,FriendlyName,InstanceId,Problem |
   Format-Table -Auto -Wrap
 }
})

(C DeepStorage).Add_Click({
 Show-DeepResult "ストレージ" {
  "---- Physical Disks ----"
  Get-PhysicalDisk -ErrorAction SilentlyContinue | Select FriendlyName,MediaType,BusType,HealthStatus,OperationalStatus,Size | Format-Table -Auto
  "---- Volumes ----"
  Get-Volume -ErrorAction SilentlyContinue | Select DriveLetter,FileSystemLabel,FileSystem,HealthStatus,SizeRemaining,Size | Format-Table -Auto
  "---- Disks ----"
  Get-Disk -ErrorAction SilentlyContinue | Select Number,FriendlyName,PartitionStyle,OperationalStatus,HealthStatus,Size | Format-Table -Auto
 }
})

(C DeepDrivers).Add_Click({
 Show-DeepResult "ドライバー" {
  Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
   Sort-Object DeviceName |
   Select DeviceName,DriverProviderName,DriverVersion,DriverDate,InfName |
   Format-Table -Auto -Wrap
 }
})

(C DeepFeatures).Add_Click({
 Show-DeepResult "Windows機能" {
  try {
   $f=Get-WindowsOptionalFeature -Online -ErrorAction Stop | Sort-Object FeatureName | Select FeatureName,State
   if($f){$f | Format-Table -Auto}
   else{"この環境ではWindows機能を取得できませんでした。`r`n環境によっては管理者権限で起動すると取得できる場合があります。"}
  } catch {
   "この環境ではWindows機能を取得できませんでした。"
   "環境によっては管理者権限で起動すると取得できる場合があります。"
   ""
   "詳細: $($_.Exception.Message)"
  }
 }
})

(C DeepEnv).Add_Click({
 Show-DeepResult "環境変数" {
  "---- Process ----"
  Get-ChildItem Env: | Sort Name | Format-Table -Auto
  "---- User ----"
  [Environment]::GetEnvironmentVariables('User').GetEnumerator() | Sort Name | Format-Table Name,Value -Auto -Wrap
  "---- Machine ----"
  [Environment]::GetEnvironmentVariables('Machine').GetEnumerator() | Sort Name | Format-Table Name,Value -Auto -Wrap
 }
})

$script:OemProductKey = $null

function Get-OemProductKey {
 try {
  $svc = Get-CimInstance SoftwareLicensingService -ErrorAction Stop
  $key = [string]$svc.OA3xOriginalProductKey
  if([string]::IsNullOrWhiteSpace($key)) { return $null }
  return $key.Trim()
 } catch { return $null }
}

(C DeepLicense).Add_Click({
 Show-DeepResult "ライセンス状態" {
  $map = @{
   0='ライセンスなし';1='ライセンス認証済み';2='初期猶予期間';3='追加猶予期間';
   4='非正規猶予期間';5='通知';6='延長猶予期間'
  }
  $wins = Get-CimInstance SoftwareLicensingProduct -ErrorAction SilentlyContinue |
   Where-Object {$_.Name -like 'Windows*' -and $_.PartialProductKey}
  foreach($w in $wins) {
   [pscustomobject]@{
    Name=$w.Name
    Description=$w.Description
    LicenseStatus=if($map.ContainsKey([int]$w.LicenseStatus)){$map[[int]$w.LicenseStatus]}else{$w.LicenseStatus}
    PartialProductKey=$w.PartialProductKey
   } | Format-List
  }
  $svc = Get-CimInstance SoftwareLicensingService -ErrorAction SilentlyContinue
  $hasOem = -not [string]::IsNullOrWhiteSpace([string]$svc.OA3xOriginalProductKey)
  "`r`nUEFI/BIOS OEMキー: " + $(if($hasOem){"保存されています（［OEMキーを表示］で確認）"}else{"保存されていない、または取得できません"})
  "`r`n※PartialProductKey はフルキーではなく、プロダクトキーの末尾5文字です。"
  "`r`n※フルOEMキーは通常表示・一括コピーには含めません。"
 }
})

(C ShowOemKey).Add_Click({
 $script:OemProductKey = Get-OemProductKey
 if([string]::IsNullOrWhiteSpace($script:OemProductKey)) {
  [System.Windows.MessageBox]::Show("UEFI/BIOSに保存されたOEMプロダクトキーは見つかりませんでした。","Winの腹の中") | Out-Null
 } else {
  [System.Windows.MessageBox]::Show(
   "UEFI/BIOS OEMプロダクトキー`r`n`r`n$($script:OemProductKey)`r`n`r`n※スクリーンショットや共有時の取り扱いに注意してください。",
   "Winの腹の中 - 秘密情報"
  ) | Out-Null
 }
})



(C DeepDump).Add_Click({
 Show-DeepResult "ダンプ設定" {
  "---- CrashControl ----"
  Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -ErrorAction SilentlyContinue |
   Select CrashDumpEnabled,DumpFile,MinidumpDir,LogEvent,AutoReboot,Overwrite,AlwaysKeepMemoryDump |
   Format-List
  "---- Existing Dump Files ----"
  Get-Item "$env:SystemRoot\MEMORY.DMP" -ErrorAction SilentlyContinue | Select FullName,Length,LastWriteTime | Format-Table -Auto
  Get-ChildItem "$env:SystemRoot\Minidump\*.dmp" -ErrorAction SilentlyContinue | Sort LastWriteTime -Descending | Select -First 20 FullName,Length,LastWriteTime | Format-Table -Auto
 }
})

(C DeepCopy).Add_Click({
 $v=(C Raw).Text
 if(-not [string]::IsNullOrWhiteSpace($v)) {
  [System.Windows.Clipboard]::SetText($v)
  (C Status).Text="深掘り結果をコピーしました"
 }
})

function Copy-Command([string]$s) {
 [System.Windows.Clipboard]::SetText($s)
 (C Status).Text="コマンドをコピーしました: $s"
}
# Control Panel / classic settings
@{
CPHome="control.exe";ProgramsFeatures="appwiz.cpl";NetworkSharing="control.exe /name Microsoft.NetworkAndSharingCenter";Adapters2="ncpa.cpl";PowerOptions="powercfg.cpl";Sound="mmsys.cpl";DevicesPrinters="control.exe printers";UserAccounts="control.exe userpasswords2";CredentialMgr="control.exe /name Microsoft.CredentialManager";FirewallCP="firewall.cpl";SystemProps="sysdm.cpl";AdvancedSystem="SystemPropertiesAdvanced.exe";InternetOptions="inetcpl.cpl";FolderOptions="control.exe folders";DateTime="timedate.cpl";Region="intl.cpl";Mouse="main.cpl";Keyboard="control.exe keyboard";Fonts="control.exe fonts"
}.GetEnumerator()|%{$n=$_.Key;$v=$_.Value;$parts=$v.Split(' ',2);$exe=$parts[0];$arg=if($parts.Count-gt1){$parts[1]}else{""};(C $n).Add_Click({Open $exe $arg}.GetNewClosure())}
(C StartupUser).Add_Click({Open "explorer.exe" "shell:startup"})
(C StartupAll).Add_Click({Open "explorer.exe" "shell:common startup"})
(C EventViewer2).Add_Click({Open "eventvwr.msc"})
(C DeviceMgr2).Add_Click({Open "devmgmt.msc"})
(C Reliability2).Add_Click({Open "perfmon.exe" "/rel"})
(C CmdIpconfig).Add_Click({Run-ReadOnlyCommand "ipconfig /all"})
(C CmdNetstat).Add_Click({Run-ReadOnlyCommand "netstat -ano"})
(C CmdArp).Add_Click({Run-ReadOnlyCommand "arp -a"})
(C CmdRoute).Add_Click({Run-ReadOnlyCommand "route print"})
(C CmdSysteminfo).Add_Click({Run-ReadOnlyCommand "systeminfo"})
(C CmdDriverquery).Add_Click({Run-ReadOnlyCommand "driverquery"})
(C CmdNetShare).Add_Click({Run-ReadOnlyCommand "net share"})
(C CmdNetUse).Add_Click({Run-ReadOnlyCommand "net use"})
(C CmdWhoami).Add_Click({Run-ReadOnlyCommand "whoami /all"})
(C CmdPrefix).Add_Click({Run-ReadOnlyCommand "netsh interface ipv6 show prefixpolicies"})
(C CopySfc).Add_Click({Copy-Command "sfc /scannow"})
(C CopyDism).Add_Click({Copy-Command "DISM /Online /Cleanup-Image /RestoreHealth"})
(C CopyCommandResult).Add_Click({[System.Windows.Clipboard]::SetText((C CommandResult).Text);(C Status).Text="実行結果をコピーしました"})
@{
System="ms-settings:about";TaskMgr="taskmgr.exe";AppBrowser="windowsdefender://appbrowser";Defender="windowsdefender:";Firewall="windowsdefender://network";NetSettings="ms-settings:network-status";Adapters="ncpa.cpl";StorageSettings="ms-settings:storagesense";DeviceMgr="devmgmt.msc";EventViewer="eventvwr.msc";Update="ms-settings:windowsupdate";Startup="ms-settings:startupapps";Apps="ms-settings:appsfeatures";Power="ms-settings:powersleep";Privacy="ms-settings:privacy";Services="services.msc";Scheduler="taskschd.msc";ComputerMgmt="compmgmt.msc";Msinfo="msinfo32.exe"
}.GetEnumerator()|%{$name=$_.Key;$target=$_.Value;(C $name).Add_Click({Open $target}.GetNewClosure())}
(C Reliability).Add_Click({Open "perfmon.exe" "/rel"})
(C Refresh).Add_Click({Collect})
(C Save).Add_Click({$d=New-Object Microsoft.Win32.SaveFileDialog;$d.Filter="Text (*.txt)|*.txt";$d.FileName="WinNoHara_$(Get-Date -Format yyyyMMdd_HHmmss).txt";if($d.ShowDialog()){[IO.File]::WriteAllText($d.FileName,(C Raw).Text,[Text.UTF8Encoding]::new($true));(C Status).Text="保存: $($d.FileName)"}})
$w.Add_ContentRendered({
 try {
  (C Status).Text='Windowsの情報を取得しています…'

  $startTimer = New-Object Windows.Threading.DispatcherTimer
  $startTimer.Interval = [TimeSpan]::FromMilliseconds(250)
  $startTimer.Add_Tick({
   $startTimer.Stop()
   try {
    Collect
    (C Status).Text='取得完了'

    $doneTimer = New-Object Windows.Threading.DispatcherTimer
    $doneTimer.Interval = [TimeSpan]::FromMilliseconds(1500)
    $doneTimer.Add_Tick({
     $doneTimer.Stop()
     try { (C Status).Text='' } catch {}
    }.GetNewClosure())
    $doneTimer.Start()
   } catch {
    try { (C Status).Text='情報取得に失敗' } catch {}
   }
  }.GetNewClosure())
  $startTimer.Start()
 } catch {
  try { (C Status).Text='情報取得に失敗' } catch {}
 }
})
$w.ShowDialog()|Out-Null
try { if ($script:WinNoHaraMutex) { $script:WinNoHaraMutex.ReleaseMutex(); $script:WinNoHaraMutex.Dispose() } } catch {}
