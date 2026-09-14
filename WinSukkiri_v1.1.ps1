
function Open-SignInOptions {
    try{Start-Process 'ms-settings:signinoptions'}catch{
        [System.Windows.MessageBox]::Show("サインイン オプションを開けませんでした。",$appName,'OK','Warning')|Out-Null
    }
}
#requires -version 5.1
# Winすっきり v1.1
# Windows 11 setup / simplification utility

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

$ErrorActionPreference = 'Stop'
$appName = 'Winすっきり'
$appVersion = 'v1.1'
$appDir = Join-Path $env:LOCALAPPDATA 'WinSukkiri'
$backupPath = Join-Path $appDir 'initial-backup.json'
$lastSnapshotPath = Join-Path $appDir 'last-action.json'
$regBackupDir = Join-Path $appDir 'RegistryBackup'
New-Item -ItemType Directory -Path $appDir -Force | Out-Null
New-Item -ItemType Directory -Path $regBackupDir -Force | Out-Null

# --- single instance ---------------------------------------------------------
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\WinSukkiri_SingleInstance', [ref]$createdNew)
if (-not $createdNew) {
    [System.Windows.MessageBox]::Show('Winすっきりは既に起動しています。', $appName, 'OK', 'Information') | Out-Null
    exit
}

function Test-RegValue {
    param([string]$Path,[string]$Name)
    try { $null = Get-ItemPropertyValue -Path $Path -Name $Name -ErrorAction Stop; return $true } catch { return $false }
}
function Get-RegValueSafe {
    param([string]$Path,[string]$Name,$Default=$null)
    try { return Get-ItemPropertyValue -Path $Path -Name $Name -ErrorAction Stop } catch { return $Default }
}

function Get-ShortcutSuffixDisabled {
    $p='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
    try{
        $v=(Get-ItemProperty -Path $p -Name 'link' -ErrorAction Stop).link
        if($v -is [byte[]] -and $v.Length -ge 4){
            return (($v[0] -eq 0) -and ($v[1] -eq 0) -and ($v[2] -eq 0) -and ($v[3] -eq 0))
        }
    }catch{}
    return $false
}
function Set-ShortcutSuffixDisabled {
    param([bool]$Disabled)
    $p='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
    if(-not(Test-Path $p)){New-Item -Path $p -Force | Out-Null}
    # Windows Explorer "link" is REG_BINARY. 00 00 00 00 = do not append " - Shortcut".
    [byte[]]$data = if($Disabled){@(0,0,0,0)}else{@(0x1E,0,0,0)}
    New-ItemProperty -Path $p -Name 'link' -PropertyType Binary -Value $data -Force | Out-Null
    $script:ShortcutSuffixChanged=$true
}

function Ensure-RegKey { param([string]$Path); if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null } }
function Set-RegDword { param([string]$Path,[string]$Name,[int]$Value); Ensure-RegKey $Path; New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null }
function Set-RegString { param([string]$Path,[string]$Name,[string]$Value); Ensure-RegKey $Path; New-ItemProperty -Path $Path -Name $Name -PropertyType String -Value $Value -Force | Out-Null }
function Remove-RegValueSafe { param([string]$Path,[string]$Name); if (Test-RegValue $Path $Name) { Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction SilentlyContinue } }

function Get-BackupObject {
    if (Test-Path $backupPath) { try { return (Get-Content $backupPath -Raw -Encoding UTF8 | ConvertFrom-Json) } catch {} }
    return [pscustomobject]@{}
}
function Save-BackupObject($obj) { $obj | ConvertTo-Json -Depth 10 | Set-Content -Path $backupPath -Encoding UTF8 }
function Backup-RegValueOnce {
    param([string]$Id,[string]$Path,[string]$Name)
    $b = Get-BackupObject
    if ($null -ne $b.PSObject.Properties[$Id]) { return }
    $exists = Test-RegValue $Path $Name
    $value = if ($exists) { Get-RegValueSafe $Path $Name } else { $null }
    $entry = [pscustomobject]@{ path=$Path; name=$Name; exists=$exists; value=$value }
    Add-Member -InputObject $b -NotePropertyName $Id -NotePropertyValue $entry
    Save-BackupObject $b
}
function Restore-RegValueFromBackup {
    param([string]$Id,[string]$FallbackPath,[string]$FallbackName,$FallbackValue,[ValidateSet('DWord','String','Binary')]$FallbackType='DWord')
    $b=Get-BackupObject; $p=$b.PSObject.Properties[$Id]
    if ($null -ne $p) {
        $e=$p.Value
        if ($e.exists) {
            if ($FallbackType -eq 'String') { Set-RegString $e.path $e.name ([string]$e.value) } elseif ($FallbackType -eq 'Binary') { Ensure-RegKey $e.path; New-ItemProperty -Path $e.path -Name $e.name -PropertyType Binary -Value ([byte[]]$e.value) -Force | Out-Null } else { Set-RegDword $e.path $e.name ([int]$e.value) }
        } else { Remove-RegValueSafe $e.path $e.name }
        return
    }
    if ($null -eq $FallbackValue) { Remove-RegValueSafe $FallbackPath $FallbackName }
    elseif ($FallbackType -eq 'String') { Set-RegString $FallbackPath $FallbackName ([string]$FallbackValue) }
    elseif ($FallbackType -eq 'Binary') { Ensure-RegKey $FallbackPath; New-ItemProperty -Path $FallbackPath -Name $FallbackName -PropertyType Binary -Value ([byte[]]$FallbackValue) -Force | Out-Null }
    else { Set-RegDword $FallbackPath $FallbackName ([int]$FallbackValue) }
}

function Invoke-RegElevated {
    param([string[]]$Arguments)
    # Start-Process の ArgumentList は、スペースを含むレジストリキーを配列のまま渡すと
    # Windows PowerShell 5.1 で崩れる場合があるため、各引数を引用して1本の文字列にする。
    $quoted = foreach ($a in $Arguments) {
        $s=[string]$a
        if ($s -match '[\s"]') { '"' + ($s -replace '"','\"') + '"' } else { $s }
    }
    $argLine = ($quoted -join ' ')
    $p = Start-Process -FilePath "$env:SystemRoot\System32\reg.exe" -ArgumentList $argLine -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "管理者権限のレジストリ操作に失敗しました。終了コード: $($p.ExitCode)" }
}
function Export-HklmKeyOnce {
    param([string]$Id,[string]$NativeKey)
    $file=Join-Path $regBackupDir ($Id+'.reg')
    if (Test-Path $file) { return }
    $args=@('export',$NativeKey,$file,'/y')
    try { Invoke-RegElevated $args } catch { }
}
function Remove-HklmKeyElevated { param([string]$NativeKey); Invoke-RegElevated @('delete',$NativeKey,'/f') }
function Restore-HklmKeyElevated {
    param([string]$Id)
    $file=Join-Path $regBackupDir ($Id+'.reg')
    if (-not (Test-Path $file)) { throw 'このPCで削除前のバックアップが見つかりません。再表示は手動対応が必要です。' }
    Invoke-RegElevated @('import',$file)
}
function Set-HklmDwordElevated {
    param([string]$NativeKey,[string]$Name,[int]$Value)
    Invoke-RegElevated @('add',$NativeKey,'/v',$Name,'/t','REG_DWORD','/d',([string]$Value),'/f')
}

$regExplorerAdv='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$regExplorer='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
$regWinExplorerPolicy='HKCU:\Software\Policies\Microsoft\Windows\Explorer'
$regRun='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$regTeams='HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\MSTeams_8wekyb3d8bbwe\TeamsTfwStartupTask'
$regContentDelivery='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$regPrivacy='HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy'
$regDesktop='HKCU:\Control Panel\Desktop'
$regWindowMetrics='HKCU:\Control Panel\Desktop\WindowMetrics'
$regSearch='HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
$homePs='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}'
$galleryPs='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}'
$homeNative='HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}'
$galleryNative='HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}'
$pwdlessPs='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device'
$pwdlessNative='HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device'

$regStartupApproved='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
$regStartupApprovedLM='HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
$regRunLM='HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
$regRun32LM='HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
$regWinlogon='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'

function Get-WindowsDisplayName {
    $os=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build=0; [void][int]::TryParse([string]$os.CurrentBuild,[ref]$build)
    $name=[string]$os.ProductName
    if($build -ge 22000){
        if($name -match 'Windows 10'){ $name=$name -replace 'Windows 10','Windows 11' }
        elseif($name -notmatch 'Windows 11'){ $name='Windows 11 ' + $name }
    }
    return [pscustomobject]@{Name=$name;Build="$($os.CurrentBuild).$($os.UBR)";DisplayVersion=[string]$os.DisplayVersion}
}
function Get-PendingRestartReasons {
    $r=New-Object System.Collections.Generic.List[string]
    if(Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'){$r.Add('Windows Update の再起動待ち')}
    if(Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'){$r.Add('コンポーネント更新の完了待ち')}
    try{$v=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations;if($v){$r.Add('ファイル置換処理の完了待ち')}}catch{}
    return @($r)
}
function Get-AutoLogonStatus {
    return ((Get-RegValueSafe $regWinlogon 'AutoAdminLogon' '0') -eq '1')
}
function Get-StartupApprovedState {
    param([string]$Bucket,[string]$Name,[string]$Scope='HKCU')
    $root=if($Scope -eq 'HKLM'){$regStartupApprovedLM}else{$regStartupApproved}
    $p=Join-Path $root $Bucket
    $v=Get-RegValueSafe $p $Name $null
    if($null -eq $v){return $null}
    try{
        $b=[byte[]]$v
        if($b.Count -gt 0){
            # StartupApproved は Microsoft が値体系を公開していないため、
            # Windows 11 実機 + 既知の観測値で判定する。
            # このPCで確認: 00/04=ON, 01/03=OFF。
            # 既知の世代: 02/06/08=ON, 03/07/09=OFF。
            switch([int]$b[0]){
                0 { return $true }
                1 { return $false }
                2 { return $true }
                3 { return $false }
                4 { return $true }
                6 { return $true }
                7 { return $false }
                8 { return $true }
                9 { return $false }
                default { return $null }
            }
        }
    }catch{}
    return $null
}
function Set-StartupApprovedState {
    param([string]$Bucket,[string]$Name,[bool]$Enabled,[string]$Scope='HKCU')
    $root=if($Scope -eq 'HKLM'){$regStartupApprovedLM}else{$regStartupApproved}
    $p=Join-Path $root $Bucket
    # Windows/Task Managerで一般的な可変値。無効化時の時刻部分はWindows側で再生成され得る。
    $b=New-Object byte[] 12;$b[0]=if($Enabled){2}else{3}
    if($Scope -eq 'HKLM'){
        # 全ユーザー側は通常ユーザーから直接書けないため、この1操作だけUAC昇格する。
        $native='HKLM\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\'+$Bucket
        $hex=($b|ForEach-Object{$_.ToString('X2')}) -join ''
        Invoke-RegElevated @('add',$native,'/v',$Name,'/t','REG_BINARY','/d',$hex,'/f')
    }else{
        Ensure-RegKey $p
        New-ItemProperty -Path $p -Name $Name -Value $b -PropertyType Binary -Force|Out-Null
    }
}
function Get-OneDriveStartupEnabled {
    $runExists=Test-RegValue $regRun 'OneDrive'
    $approved=Get-StartupApprovedState 'Run' 'OneDrive'
    if($approved -eq $false){return $false}
    if(-not $runExists){return $false}
    return $true
}
function Set-OneDriveStartupEnabled([bool]$Enabled){
    if(Test-RegValue $regRun 'OneDrive'){ Set-StartupApprovedState 'Run' 'OneDrive' $Enabled; return }
    if(-not $Enabled){ return }
    throw 'OneDriveのスタートアップ登録がありません。OneDriveを一度起動してからWindows側で設定してください。'
}
function Test-TeamsInstalled {
    try{if(Get-AppxPackage -Name MSTeams -ErrorAction SilentlyContinue){return $true}}catch{}
    if(Test-Path "$env:LOCALAPPDATA\Microsoft\WindowsApps\ms-teams.exe"){return $true}
    return (Test-Path $regTeams)
}
function Get-TeamsStartupEnabled {
    # 新Teamsは、未起動だとStartupTaskの状態キー自体が無い場合がある。
    # その場合は「自動起動していない」と解釈する。
    if(Test-Path $regTeams){
        $state=Get-RegValueSafe $regTeams 'State' $null
        if($null -ne $state){ return ([int]$state -eq 2) }
    }
    foreach($n in @('Teams','MSTeams','Microsoft Teams','ms-teams.exe')){
        $a=Get-StartupApprovedState 'Run' $n
        if($a -ne $null){return [bool]$a}
    }
    return $false
}
function Set-TeamsStartupEnabled([bool]$Enabled){
    if(Test-Path $regTeams){Set-RegDword $regTeams 'State' $(if($Enabled){2}else{1});return}
    foreach($n in @('Teams','MSTeams','Microsoft Teams','ms-teams.exe')){
        $a=Get-StartupApprovedState 'Run' $n
        if($a -ne $null){Set-StartupApprovedState 'Run' $n $Enabled;return}
    }
    if(-not $Enabled){return}
    throw 'Teamsのスタートアップ登録はまだ作成されていません。Teamsを一度起動してから有効化してください。'
}

function Get-AppxStartupTaskFriendlyName {
    param([string]$PackageFamilyName,[string]$TaskId,[string]$PackageName)
    switch -Regex ($TaskId) {
        '^TeamsTfwStartupTask$' { return 'Microsoft Teams' }
        '^CalendarStartupId$'   { return 'Calendar' }
        '^FilesStartupId$'      { return 'Files' }
        '^PeopleStartupId$'     { return 'People' }
        '^WebViewHostStartupId$'{ return 'Microsoft 365 Copilot' }
        '^StartTerminalOnLoginTask$' { return 'Windows Terminal' }
        '^CmdPalStartup$'       { return 'Command Palette' }
        'Xbox'                  { return 'Xbox' }
        default {
            if($PackageName -eq 'Microsoft.GamingApp'){return 'Xbox'}
            if($PackageName -eq 'Microsoft.WindowsTerminal'){return 'Windows Terminal'}
            if($PackageName -eq 'Microsoft.CommandPalette'){return 'Command Palette'}
            return $TaskId
        }
    }
}
function Get-AppxStartupTaskState {
    param([string]$PackageFamilyName,[string]$TaskId)
    $p="HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\$PackageFamilyName\$TaskId"
    if(Test-Path $p){
        $state=Get-RegValueSafe $p 'State' $null
        if($null -ne $state){
            # Windows 11実機確認:
            # State=2 -> ON
            # State=1 -> OFF（ユーザーがOFF）
            # State=0 -> OFF（まだ有効化していない初期状態）
            return ([int]$state -eq 2)
        }
    }
    return $false
}
function Set-AppxStartupTaskState {
    param([string]$PackageFamilyName,[string]$TaskId,[bool]$Enabled)
    $p="HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\$PackageFamilyName\$TaskId"
    Ensure-RegKey $p
    Set-RegDword $p 'State' $(if($Enabled){2}else{1})
    Set-RegDword $p 'UserEnabledStartupOnce' 1
}
function Get-AppxStartupTasks {
    $result=New-Object System.Collections.Generic.List[object]
    foreach($pkg in @(Get-AppxPackage -ErrorAction SilentlyContinue)){
        try{$manifest=Get-AppxPackageManifest $pkg.PackageFullName -ErrorAction Stop}catch{continue}
        if($null -eq $manifest){continue}
        $exts=@($manifest.Package.Applications.Application.Extensions.Extension)
        foreach($ext in $exts){
            if([string]$ext.Category -notmatch 'startupTask'){continue}
            $taskId=[string]$ext.StartupTask.TaskId
            if([string]::IsNullOrWhiteSpace($taskId)){continue}
            $friendly=Get-AppxStartupTaskFriendlyName $pkg.PackageFamilyName $taskId $pkg.Name
            $result.Add([pscustomobject]@{
                PackageName=$pkg.Name
                PackageFamilyName=$pkg.PackageFamilyName
                TaskId=$taskId
                DisplayName=$friendly
                Enabled=(Get-AppxStartupTaskState $pkg.PackageFamilyName $taskId)
            })
        }
    }
    return @($result | Sort-Object DisplayName,TaskId -Unique)
}


function Get-ExecutablePathFromStartupCommand {
    param([string]$Command)
    if([string]::IsNullOrWhiteSpace($Command)){return $null}
    $s=[Environment]::ExpandEnvironmentVariables($Command.Trim())
    if($s -eq '(登録情報のみ)'){return $null}
    if($s.StartsWith('"')){
        $m=[regex]::Match($s,'^"([^"]+)"')
        if($m.Success){return $m.Groups[1].Value}
    }
    $m=[regex]::Match($s,'^(.+?\.(?:exe|com|bat|cmd|ps1|ahk))(?=\s|$)',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if($m.Success){return $m.Groups[1].Value.Trim('"')}
    $first=($s -split '\s+')[0].Trim('"')
    if(Test-Path -LiteralPath $first){return $first}
    return $null
}
function Resolve-ShortcutTargetSafe {
    param([string]$ShortcutPath)
    try{
        if(-not(Test-Path -LiteralPath $ShortcutPath)){return $null}
        $ws=New-Object -ComObject WScript.Shell
        $sc=$ws.CreateShortcut($ShortcutPath)
        $target=[string]$sc.TargetPath
        if(-not [string]::IsNullOrWhiteSpace($target)){return [Environment]::ExpandEnvironmentVariables($target)}
    }catch{}
    return $null
}
function Get-FileFriendlyNameSafe {
    param([string]$Path)
    if([string]::IsNullOrWhiteSpace($Path)){return $null}
    try{
        $p=[Environment]::ExpandEnvironmentVariables($Path.Trim('"'))
        if(-not(Test-Path -LiteralPath $p)){return $null}
        $fi=[Diagnostics.FileVersionInfo]::GetVersionInfo($p)
        foreach($candidate in @([string]$fi.FileDescription,[string]$fi.ProductName)){
            if(-not [string]::IsNullOrWhiteSpace($candidate)){
                $c=$candidate.Trim()
                if($c -notmatch '^(Microsoft®? Windows®? Operating System|Microsoft Windows)$'){return $c}
            }
        }
        return [IO.Path]::GetFileNameWithoutExtension($p)
    }catch{return $null}
}
function Get-StartupFriendlyName {
    param([string]$Name,[string]$Command,[string]$Source)
    $fallback=[string]$Name
    if($fallback -match '(?i)\.lnk$'){$fallback=[IO.Path]::GetFileNameWithoutExtension($fallback)}

    # Shortcut: resolve the actual target first, then read FileDescription/ProductName.
    if([string]$Name -match '(?i)\.lnk$'){
        $shortcut=$Command
        if(Test-Path -LiteralPath $shortcut){
            $target=Resolve-ShortcutTargetSafe $shortcut
            $friendly=Get-FileFriendlyNameSafe $target
            if($friendly){return $friendly}
        }
    }

    # Run / StartupApproved entry: derive a human-readable name from its executable.
    $exe=Get-ExecutablePathFromStartupCommand $Command
    $friendly=Get-FileFriendlyNameSafe $exe
    if($friendly){return $friendly}

    # Last-resort aliases for entries whose executable metadata is unavailable.
    switch -Regex ($fallback) {
        '^SecurityHealth$' { return 'Windows Security notification icon' }
        '^MicrosoftEdgeAutoLaunch_' { return 'Microsoft Edge' }
        '^EPLTarget\\' { return 'EPSON Status Monitor 3' }
        '^BUFFALO NAS Navigator2$' { return 'NASNavigator2' }
        '^ELECOM Mouse Assistant 6$' { return 'MouseAssistant' }
        '^NAS Scheduler$' { return 'NAS Function Scheduling Application' }
        '^SoftEther VPN Client Manager Startup$' { return 'SoftEther VPN' }
        default { return $fallback }
    }
}


function Test-StartupFolderEntryExists {
    param([string]$Name)
    if([string]::IsNullOrWhiteSpace($Name)){return $false}
    foreach($folder in @([Environment]::GetFolderPath('Startup'),[Environment]::GetFolderPath('CommonStartup'))){
        if($folder -and (Test-Path -LiteralPath (Join-Path $folder $Name))){return $true}
    }
    return $false
}
function Get-StartupItems {
    $items=@{}
    function PutItem($key,$name,$cmd,$source,$bucket,$enabled,$canEdit,$scope='HKCU'){
        $display=Get-StartupFriendlyName $name $cmd $source
        if(!$items.ContainsKey($key)){$items[$key]=[pscustomobject]@{Key=$key;Name=$name;DisplayName=$display;Command=$cmd;Source=$source;Bucket=$bucket;Enabled=$enabled;CanEdit=$canEdit;Scope=$scope}}
        else{
            if($cmd -and -not $items[$key].Command){$items[$key].Command=$cmd}
            $items[$key].Enabled=$enabled
            $items[$key].DisplayName=Get-StartupFriendlyName $items[$key].Name $items[$key].Command $items[$key].Source
        }
    }

    # Run registrations: HKCU, HKLM, HKLM 32bit. Registration existence and approved state are separate.
    foreach($rd in @(
        @{Path=$regRun; Scope='HKCU'; Label='現在のユーザー / Run'; Bucket='Run'},
        @{Path=$regRunLM; Scope='HKLM'; Label='すべてのユーザー / Run'; Bucket='Run'},
        @{Path=$regRun32LM; Scope='HKLM'; Label='すべてのユーザー / Run32'; Bucket='Run32'}
    )){
        $props=@();try{$props=(Get-ItemProperty $rd.Path -ErrorAction Stop).PSObject.Properties|Where-Object{$_.Name-notmatch'^PS'}}catch{}
        foreach($p in $props){
            $a=Get-StartupApprovedState $rd.Bucket $p.Name $rd.Scope
            $en=if($a -eq $null){$true}else{[bool]$a}
            PutItem ($rd.Scope+'_'+$rd.Bucket+'|'+$p.Name) $p.Name ([string]$p.Value) $rd.Label $rd.Bucket $en $true $rd.Scope
        }
    }

    # Approved-only records, including disabled entries whose registration is not directly visible.
    foreach($ad in @(
        @{Root=$regStartupApproved; Scope='HKCU'; Label='Windows スタートアップ（ユーザー）'},
        @{Root=$regStartupApprovedLM; Scope='HKLM'; Label='Windows スタートアップ（全ユーザー）'}
    )){
        foreach($bucket in @('Run','Run32','StartupFolder')){
            $ap=Join-Path $ad.Root $bucket
            if(Test-Path $ap){
                $props=(Get-ItemProperty $ap).PSObject.Properties|Where-Object{$_.Name-notmatch'^PS'}
                foreach($p in $props){
                    $a=Get-StartupApprovedState $bucket $p.Name $ad.Scope
                    if($a -eq $null){continue}
                    # StartupApprovedだけ残り、実際のStartupフォルダーに.lnkが無い履歴は
                    # Windows標準のスタートアップ一覧にも出ないため、通常項目として表示しない。
                    if($bucket -eq 'StartupFolder' -and -not (Test-StartupFolderEntryExists $p.Name)){continue}
                    # Avoid duplicate Run rows when the registration was already found.
                    $existing=@($items.Values|Where-Object{$_.Name -eq $p.Name -and $_.Bucket -eq $bucket -and $_.Scope -eq $ad.Scope})
                    if($existing.Count -gt 0){foreach($x in $existing){$x.Enabled=[bool]$a};continue}
                    PutItem ('APPROVED_'+$ad.Scope+'_'+$bucket+'|'+$p.Name) $p.Name '(登録情報のみ)' ($ad.Label+' / '+$bucket) $bucket ([bool]$a) $true $ad.Scope
                }
            }
        }
    }

    # Startup folders: current user's folder uses HKCU approval; common folder uses HKLM approval.
    foreach($f in @(
        @{Path=[Environment]::GetFolderPath('Startup');Label='スタートアップ フォルダー';Scope='HKCU'},
        @{Path=[Environment]::GetFolderPath('CommonStartup');Label='共通スタートアップ フォルダー';Scope='HKLM'}
    )){
        if(Test-Path $f.Path){
            foreach($file in Get-ChildItem $f.Path -File -ErrorAction SilentlyContinue){
                $a=Get-StartupApprovedState 'StartupFolder' $file.Name $f.Scope
                $en=if($a -eq $null){$true}else{[bool]$a}
                $existing=@($items.Values|Where-Object{$_.Name -eq $file.Name -and $_.Bucket -eq 'StartupFolder' -and $_.Scope -eq $f.Scope})
                if($existing.Count -gt 0){foreach($x in $existing){$x.Command=$file.FullName;$x.Source=$f.Label;$x.Enabled=$en;$x.DisplayName=Get-StartupFriendlyName $x.Name $x.Command $x.Source};continue}
                PutItem ('FOLDER_'+$f.Scope+'|'+$file.FullName) $file.Name $file.FullName $f.Label 'StartupFolder' $en $true $f.Scope
            }
        }
    }

    # Microsoft Store / Appx StartupTask (Windows標準スタートアップに出る項目)
    $appxTasks=@(Get-AppxStartupTasks)
    foreach($task in $appxTasks){
        if($task.TaskId -eq 'TeamsTfwStartupTask'){
            # TeamsはWindows標準側では1項目に見えるため、古いTeams系の重複行を除く。
            foreach($k in @($items.Keys)){
                $n=[string]$items[$k].Name
                if($n -match '(?i)(^Teams$|MSTeams|Microsoft Teams|ms-teams)'){$items.Remove($k)}
            }
        }
        PutItem ('APPX|'+$task.PackageFamilyName+'|'+$task.TaskId) $task.TaskId 'Windows App StartupTask' 'Windows アプリ / StartupTask' 'AppxStartupTask' ([bool]$task.Enabled) $true $task.PackageFamilyName
        $items['APPX|'+$task.PackageFamilyName+'|'+$task.TaskId].DisplayName=$task.DisplayName
    }

    if(Test-TeamsInstalled){
        $hasTeams=@($items.Values|Where-Object{$_.DisplayName -eq 'Microsoft Teams'}).Count -gt 0
        if(-not $hasTeams){PutItem 'SPECIAL|Teams' 'Microsoft Teams' '新Teams StartupTask' 'アプリのスタートアップ' 'TeamsSpecial' (Get-TeamsStartupEnabled) $true 'HKCU'}
    }
    return @($items.Values|Sort-Object DisplayName,Source)
}

$regExplorerRoot='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
$regAutoplay='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers'
function Get-NoShortcutSuffix {
    if(-not (Test-RegValue $regExplorerRoot 'link')){return $false}
    try{$v=[byte[]](Get-ItemPropertyValue -Path $regExplorerRoot -Name 'link'); return ($v.Count -ge 4 -and $v[0] -eq 0 -and $v[1] -eq 0 -and $v[2] -eq 0 -and $v[3] -eq 0)}catch{return $false}
}
function Set-NoShortcutSuffix([bool]$Enabled){
    Ensure-RegKey $regExplorerRoot
    if($Enabled){
        [byte[]]$data=@(0x00,0x00,0x00,0x00)
        New-ItemProperty -Path $regExplorerRoot -Name 'link' -PropertyType Binary -Value $data -Force | Out-Null
    }else{
        # Windows標準へ戻す: Explorer\link のカスタム値を削除する。
        Remove-ItemProperty -Path $regExplorerRoot -Name 'link' -ErrorAction SilentlyContinue
        $naming='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\NamingTemplates'
        if(Test-Path $naming){
            Remove-ItemProperty -Path $naming -Name 'ShortcutNameTemplate' -ErrorAction SilentlyContinue
            try{
                $props=(Get-ItemProperty $naming -ErrorAction Stop).PSObject.Properties |
                    Where-Object { $_.Name -notmatch '^PS' }
                if(@($props).Count -eq 0){Remove-Item $naming -Force -ErrorAction SilentlyContinue}
            }catch{}
        }
    }
    $script:ShortcutSuffixChanged=$true
}


# --- v1.1 additional settings ----------------------------------------------
$classicMenuPs='HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
$classicMenuParentPs='HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'
$regSearchPolicy='HKCU:\Software\Policies\Microsoft\Windows\Explorer'
$regPower='HKLM:\SYSTEM\CurrentControlSet\Control\Power'
$script:ClassicContextMenuChanged=$false
$script:FileExtChanged=$false

function Invoke-ExeElevated {
    param([string]$FilePath,[string]$Arguments)
    $p=Start-Process -FilePath $FilePath -ArgumentList $Arguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    if($p.ExitCode -ne 0){throw "管理者権限の処理に失敗しました。終了コード: $($p.ExitCode)"}
}
function Invoke-PowerShellElevated {
    param([string]$Code)
    $bytes=[Text.Encoding]::Unicode.GetBytes($Code)
    $encoded=[Convert]::ToBase64String($bytes)
    Invoke-ExeElevated "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"
}

function Get-HibernateDisabled {
    try{return ([int](Get-ItemPropertyValue -Path $regPower -Name 'HibernateEnabled' -ErrorAction Stop) -eq 0)}catch{return $false}
}
function Set-HibernateEnabled([bool]$Enabled){
    $arg=if($Enabled){'/hibernate on'}else{'/hibernate off'}
    Invoke-ExeElevated "$env:SystemRoot\System32\powercfg.exe" $arg
}

function Get-ClassicContextMenuEnabled {
    return (Test-Path $classicMenuPs)
}
function Set-ClassicContextMenuEnabled([bool]$Enabled){
    if($Enabled){
        Ensure-RegKey $classicMenuPs
        Set-Item -Path $classicMenuPs -Value '' -Force
    }else{
        if(Test-Path $classicMenuParentPs){Remove-Item -Path $classicMenuParentPs -Recurse -Force -ErrorAction Stop}
    }
    $script:ClassicContextMenuChanged=$true
}

function Get-WebSearchSuppressed {
    $a=(Get-RegValueSafe $regSearchPolicy 'DisableSearchBoxSuggestions' 0) -eq 1
    $b=(Get-RegValueSafe $regSearch 'BingSearchEnabled' 1) -eq 0
    return ($a -and $b)
}
function Set-WebSearchSuppressed([bool]$Enabled){
    if($Enabled){
        Backup-RegValueOnce 'DisableSearchBoxSuggestions' $regSearchPolicy 'DisableSearchBoxSuggestions'
        Backup-RegValueOnce 'BingSearchEnabled' $regSearch 'BingSearchEnabled'
        Set-RegDword $regSearchPolicy 'DisableSearchBoxSuggestions' 1
        Set-RegDword $regSearch 'BingSearchEnabled' 0
    }else{
        Restore-RegValueFromBackup 'DisableSearchBoxSuggestions' $regSearchPolicy 'DisableSearchBoxSuggestions' $null
        Restore-RegValueFromBackup 'BingSearchEnabled' $regSearch 'BingSearchEnabled' $null
    }
}

function Get-DefaultDnsInterfaceIndexes {
    try{
        # 実際のIPv4既定経路を優先。VPN等で複数ある場合も、Upかつ既定経路を持つものだけを対象にする。
        $routes=@(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
            Where-Object { $_.State -eq 'Alive' } |
            Sort-Object RouteMetric,InterfaceMetric)
        $result=@()
        foreach($r in $routes){
            try{
                $a=Get-NetAdapter -InterfaceIndex $r.InterfaceIndex -ErrorAction Stop
                if($a.Status -eq 'Up' -and $result -notcontains [int]$r.InterfaceIndex){$result += [int]$r.InterfaceIndex}
            }catch{}
        }
        return @($result)
    }catch{return @()}
}
function Get-DnsPresetApplied([ValidateSet('Cloudflare','Google')]$Preset){
    $idx=@(Get-DefaultDnsInterfaceIndexes)
    if($idx.Count -eq 0){return $false}
    $required=if($Preset -eq 'Cloudflare'){@('1.1.1.1','1.0.0.1')}else{@('8.8.8.8','8.8.4.4')}
    foreach($i in $idx){
        try{$current=@((Get-DnsClientServerAddress -InterfaceIndex $i -AddressFamily IPv4 -ErrorAction Stop).ServerAddresses)}catch{return $false}
        if(($current -join ',') -ne ($required -join ',')){return $false}
    }
    return $true
}
function Set-DnsPreset([ValidateSet('Auto','Cloudflare','Google')]$Preset){
    $idx=@(Get-DefaultDnsInterfaceIndexes)
    if($idx.Count -eq 0){throw 'IPv4の既定経路を持つ有効なネットワーク接続が見つかりません。'}
    $idxLiteral=($idx | ForEach-Object {[string][int]$_}) -join ','
    if($Preset -eq 'Auto'){
        $code="`$ErrorActionPreference='Stop'; `$idx=@($idxLiteral); foreach(`$i in `$idx){Set-DnsClientServerAddress -InterfaceIndex `$i -ResetServerAddresses}; Clear-DnsClientCache -ErrorAction SilentlyContinue"
    }else{
        $servers=if($Preset -eq 'Cloudflare'){"'1.1.1.1','1.0.0.1'"}else{"'8.8.8.8','8.8.4.4'"}
        $code="`$ErrorActionPreference='Stop'; `$idx=@($idxLiteral); `$servers=@($servers); foreach(`$i in `$idx){Set-DnsClientServerAddress -InterfaceIndex `$i -ServerAddresses `$servers}; Clear-DnsClientCache -ErrorAction SilentlyContinue"
    }
    Invoke-PowerShellElevated $code
    Start-Sleep -Milliseconds 400
    if($Preset -ne 'Auto' -and -not (Get-DnsPresetApplied $Preset)){
        $actual=@()
        foreach($i in $idx){
            try{$actual += "IF $i = "+((Get-DnsClientServerAddress -InterfaceIndex $i -AddressFamily IPv4).ServerAddresses -join ', ')}catch{}
        }
        throw "DNS変更後の確認に失敗しました。現在値: $($actual -join ' / ')"
    }
}
$settings=@(
 [pscustomobject]@{Id='OneDrive';Cat='シンプル化';Title='OneDriveを自動起動しない';Subtitle='Windows側の現在状態を読み取って判定します。';Risk='安全';NeedsAdmin=$false;Restart='不要';Recommended=$true;Exists={$true};IsApplied={-not(Get-OneDriveStartupEnabled)};Apply={Set-OneDriveStartupEnabled $false};Revert={Set-OneDriveStartupEnabled $true};Detail='OneDriveが実際にサインイン時起動する状態かを判定します。Winすっきり以外でOFFにしていても「すっきり済み」と認識します。OneDriveや同期済みファイルは削除しません。'},
 [pscustomobject]@{Id='Teams';Cat='シンプル化';Title='Microsoft Teamsを自動起動しない';Subtitle='未登録・Windows側OFFも「自動起動なし」と判定します。';Risk='安全';NeedsAdmin=$false;Restart='不要';Recommended=$true;Exists={Test-TeamsInstalled};IsApplied={-not(Get-TeamsStartupEnabled)};Apply={Set-TeamsStartupEnabled $false};Revert={Set-TeamsStartupEnabled $true};Detail='Teamsが未起動でスタートアップ登録自体が無い場合も「自動起動していない」と判定します。Windows側でOFFにした状態も共通ロジックで読み取ります。'},
 [pscustomobject]@{Id='WindowsTips';Cat='シンプル化';Title='Windowsのヒント・おすすめを減らす';Subtitle='Windowsのお節介系コンテンツの一部を抑えます。';Risk='安全';NeedsAdmin=$false;Restart='不要';Recommended=$true;Exists={$true};IsApplied={((Get-RegValueSafe $regContentDelivery 'SubscribedContent-338389Enabled' 1) -eq 0) -and ((Get-RegValueSafe $regContentDelivery 'SoftLandingEnabled' 1) -eq 0)};Apply={Backup-RegValueOnce 'SubscribedContent-338389Enabled' $regContentDelivery 'SubscribedContent-338389Enabled';Backup-RegValueOnce 'SoftLandingEnabled' $regContentDelivery 'SoftLandingEnabled';Set-RegDword $regContentDelivery 'SubscribedContent-338389Enabled' 0;Set-RegDword $regContentDelivery 'SoftLandingEnabled' 0};Revert={Restore-RegValueFromBackup 'SubscribedContent-338389Enabled' $regContentDelivery 'SubscribedContent-338389Enabled' 1;Restore-RegValueFromBackup 'SoftLandingEnabled' $regContentDelivery 'SoftLandingEnabled' 1};Detail='Windows使用中のヒントや提案コンテンツを減らす複合設定です。セキュリティ通知は止めません。Windows設定に1対1で対応する項目ではありません。'},
 [pscustomobject]@{Id='SuggestedApps';Cat='シンプル化';Title='ヒント・ショートカット・新しいアプリのおすすめを表示しない';Subtitle='Windows 11「ヒント、ショートカット、新しいアプリなどのおすすめ」をOFFにします。';Risk='安全';NeedsAdmin=$false;Restart='不要';Recommended=$true;Exists={$true};IsApplied={(Get-RegValueSafe $regExplorerAdv 'Start_IrisRecommendations' 1) -eq 0};Apply={Backup-RegValueOnce 'Start_IrisRecommendations' $regExplorerAdv 'Start_IrisRecommendations';Set-RegDword $regExplorerAdv 'Start_IrisRecommendations' 0};Revert={Restore-RegValueFromBackup 'Start_IrisRecommendations' $regExplorerAdv 'Start_IrisRecommendations' 1};Detail='Windows 設定 → 個人用設定 → スタート →「ヒント、ショートカット、新しいアプリなどのおすすめを表示します」と1対1で対応します。Windows側がOFFならWinすっきりではON（すっきり済み）になります。'},
 [pscustomobject]@{Id='TaskView';Cat='デスクトップ';Title='タスクビューボタンを表示しない';Subtitle='使わない場合はタスクバーをすっきり。';Risk='安全';NeedsAdmin=$false;Restart='Explorer';Recommended=$true;Exists={$true};IsApplied={(Get-RegValueSafe $regExplorerAdv 'ShowTaskViewButton' 1) -eq 0};Apply={Backup-RegValueOnce 'ShowTaskViewButton' $regExplorerAdv 'ShowTaskViewButton';Set-RegDword $regExplorerAdv 'ShowTaskViewButton' 0};Revert={Restore-RegValueFromBackup 'ShowTaskViewButton' $regExplorerAdv 'ShowTaskViewButton' 1};Detail='タスクビューボタンだけを隠します。Win+Tabはそのまま使えます。'},
 [pscustomobject]@{Id='SearchIcon';Cat='デスクトップ';Title='タスクバーの検索をアイコン表示にする';Subtitle='大きな検索ボックスを小さくします。';Risk='安全';NeedsAdmin=$false;Restart='Explorer';Recommended=$true;Exists={$true};IsApplied={(Get-RegValueSafe $regSearch 'SearchboxTaskbarMode' 2) -eq 1};Apply={Backup-RegValueOnce 'SearchboxTaskbarMode' $regSearch 'SearchboxTaskbarMode';Set-RegDword $regSearch 'SearchboxTaskbarMode' 1};Revert={Restore-RegValueFromBackup 'SearchboxTaskbarMode' $regSearch 'SearchboxTaskbarMode' 2};Detail='タスクバーの検索をアイコン中心の表示にします。検索機能そのものは残ります。'},
 [pscustomobject]@{Id='NoWebSearch';Cat='シンプル化';Title='スタート検索のWeb候補を抑える';Subtitle='BingなどのWeb候補を抑え、アプリ・設定・ローカル検索を中心にします。';Risk='注意';NeedsAdmin=$false;Restart='再起動';Recommended=$true;Exists={$true};IsApplied={Get-WebSearchSuppressed};Apply={Set-WebSearchSuppressed $true};Revert={Set-WebSearchSuppressed $false};Detail='スタート／Windows検索に混ざるWeb候補を抑えるため、ユーザー単位の検索関連レジストリを設定します。Windows Updateで検索仕様が変わると効き方が変わる可能性があります。検索機能そのものは停止しません。'},

 [pscustomobject]@{Id='NoShortcutSuffix';Cat='エクスプローラー';Title='ショートカット名に「- ショートカット」を付けない';Subtitle='新しく作るショートカットの名前をすっきりさせます。';Risk='安全';NeedsAdmin=$false;Restart='Explorer';Recommended=$true;Exists={$true};IsApplied={Get-NoShortcutSuffix};Apply={Set-NoShortcutSuffix $true};Revert={Set-NoShortcutSuffix $false};Detail='Windowsが新しいショートカットを作る際に付ける「- ショートカット」という末尾を付けない設定です。既存ショートカットの名前は変更しません。OFFに戻すとカスタム値を削除してWindows標準の命名動作へ戻します。'},
 [pscustomobject]@{Id='ClassicContextMenu';Cat='エクスプローラー';Title='右クリックメニューを従来表示にする';Subtitle='Windows 11の「その他のオプションを確認」を省き、従来型メニューを直接表示します。';Risk='注意';NeedsAdmin=$false;Restart='Explorer';Recommended=$false;Exists={$true};IsApplied={Get-ClassicContextMenuEnabled};Apply={Set-ClassicContextMenuEnabled $true};Revert={Set-ClassicContextMenuEnabled $false};Detail='HKCUのCLSID設定を使って従来型の右クリックメニューへ切り替えます。Windows 11の非公式互換設定のため、将来の更新で動作しなくなる可能性があります。OFFで追加キーを削除し標準動作へ戻します。'},

 [pscustomobject]@{Id='DisableAutoplay';Cat='エクスプローラー';Title='ドライブの自動再生を無効にする';Subtitle='USBメモリなどを接続したときの自動再生を止めます。';Risk='安全';NeedsAdmin=$false;Restart='不要';Recommended=$true;Exists={$true};IsApplied={(Get-RegValueSafe $regAutoplay 'DisableAutoplay' 0) -eq 1};Apply={Backup-RegValueOnce 'DisableAutoplay' $regAutoplay 'DisableAutoplay';Set-RegDword $regAutoplay 'DisableAutoplay' 1};Revert={Restore-RegValueFromBackup 'DisableAutoplay' $regAutoplay 'DisableAutoplay' 0};Detail='Windowsの自動再生機能を無効にします。ドライブ自体を無効化したり、USB機器を使えなくしたりはしません。'},
 [pscustomobject]@{Id='FileExt';Cat='エクスプローラー';Title='ファイル名の拡張子を表示する';Subtitle='.jpg / .exe / .txt を常に表示します。';Risk='安全';NeedsAdmin=$false;Restart='Explorer';Recommended=$true;Exists={$true};IsApplied={(Get-RegValueSafe $regExplorerAdv 'HideFileExt' 1) -eq 0};Apply={Backup-RegValueOnce 'HideFileExt' $regExplorerAdv 'HideFileExt';Set-RegDword $regExplorerAdv 'HideFileExt' 0;$script:FileExtChanged=$true};Revert={Restore-RegValueFromBackup 'HideFileExt' $regExplorerAdv 'HideFileExt' 1;$script:FileExtChanged=$true};Detail='拡張子を常時表示します。変更後はExplorer再起動を案内します。'},
 [pscustomobject]@{Id='HiddenFiles';Cat='エクスプローラー';Title='隠しファイルを表示する';Subtitle='隠し属性のファイルを見えるようにします。';Risk='注意';NeedsAdmin=$false;Restart='Explorer';Recommended=$false;Exists={$true};IsApplied={(Get-RegValueSafe $regExplorerAdv 'Hidden' 2) -eq 1};Apply={Backup-RegValueOnce 'Hidden' $regExplorerAdv 'Hidden';Set-RegDword $regExplorerAdv 'Hidden' 1};Revert={Restore-RegValueFromBackup 'Hidden' $regExplorerAdv 'Hidden' 2};Detail='隠し属性のファイルやフォルダーを表示します。保護されたOSファイルには触れません。'},
 [pscustomobject]@{Id='ThisPC';Cat='エクスプローラー';Title='エクスプローラーは「PC」から開く';Subtitle='ホームではなくドライブ一覧を最初に表示。';Risk='安全';NeedsAdmin=$false;Restart='Explorer';Recommended=$true;Exists={$true};IsApplied={(Get-RegValueSafe $regExplorerAdv 'LaunchTo' 2) -eq 1};Apply={Backup-RegValueOnce 'LaunchTo' $regExplorerAdv 'LaunchTo';Set-RegDword $regExplorerAdv 'LaunchTo' 1};Revert={Restore-RegValueFromBackup 'LaunchTo' $regExplorerAdv 'LaunchTo' 2};Detail='Explorer起動時の開始場所を「PC」にします。'},
 [pscustomobject]@{Id='RecentFiles';Cat='エクスプローラー';Title='最近使ったファイルをホームに表示しない';Subtitle='Explorerホームの最近使用したファイルを抑えます。';Risk='安全';NeedsAdmin=$false;Restart='Explorer';Recommended=$true;Exists={$true};IsApplied={(Get-RegValueSafe $regExplorer 'ShowRecent' 1) -eq 0};Apply={Backup-RegValueOnce 'ShowRecent' $regExplorer 'ShowRecent';Set-RegDword $regExplorer 'ShowRecent' 0};Revert={Restore-RegValueFromBackup 'ShowRecent' $regExplorer 'ShowRecent' 1};Detail='最近使用したファイルをExplorerホームから非表示にします。ファイルは削除しません。'},
 [pscustomobject]@{Id='FrequentFolders';Cat='エクスプローラー';Title='よく使うフォルダーをホームに表示しない';Subtitle='Explorerホームの頻繁なフォルダー表示を抑えます。';Risk='安全';NeedsAdmin=$false;Restart='Explorer';Recommended=$true;Exists={$true};IsApplied={(Get-RegValueSafe $regExplorer 'ShowFrequent' 1) -eq 0};Apply={Backup-RegValueOnce 'ShowFrequent' $regExplorer 'ShowFrequent';Set-RegDword $regExplorer 'ShowFrequent' 0};Revert={Restore-RegValueFromBackup 'ShowFrequent' $regExplorer 'ShowFrequent' 1};Detail='よく使用するフォルダーをExplorerホームから非表示にします。'},
 [pscustomobject]@{Id='SyncTips';Cat='エクスプローラー';Title='Explorerのおすすめ通知を表示しない';Subtitle='同期サービスなどの案内表示を抑えます。';Risk='安全';NeedsAdmin=$false;Restart='Explorer';Recommended=$true;Exists={$true};IsApplied={(Get-RegValueSafe $regExplorerAdv 'ShowSyncProviderNotifications' 1) -eq 0};Apply={Backup-RegValueOnce 'ShowSyncProviderNotifications' $regExplorerAdv 'ShowSyncProviderNotifications';Set-RegDword $regExplorerAdv 'ShowSyncProviderNotifications' 0};Revert={Restore-RegValueFromBackup 'ShowSyncProviderNotifications' $regExplorerAdv 'ShowSyncProviderNotifications' 1};Detail='Explorer上部などに表示される同期サービスやWindows機能の案内を抑えます。'},
 [pscustomobject]@{Id='HideHome';Cat='エクスプローラー';Title='ナビゲーションから「ホーム」を非表示';Subtitle='既に手動で消していても「すっきり済み」と判定します。';Risk='注意';NeedsAdmin=$true;Restart='Explorer';Recommended=$false;Exists={$true};IsApplied={-not(Test-Path $homePs)};Apply={if(Test-Path $homePs){Export-HklmKeyOnce 'ExplorerHome' $homeNative;Remove-HklmKeyElevated $homeNative}};Revert={if(Test-Path $homePs){return};Restore-HklmKeyElevated 'ExplorerHome'};Detail='Explorer左ナビゲーションの「ホーム」を非表示にします。キーが既に無ければ、Winすっきり以外の方法で変更済みでもONとして認識します。再表示はWinすっきりが削除前バックアップを持つ場合のみ自動復元します。'},
 [pscustomobject]@{Id='HideGallery';Cat='エクスプローラー';Title='ナビゲーションから「ギャラリー」を非表示';Subtitle='既に手動で消していても「すっきり済み」と判定します。';Risk='注意';NeedsAdmin=$true;Restart='Explorer';Recommended=$false;Exists={$true};IsApplied={-not(Test-Path $galleryPs)};Apply={if(Test-Path $galleryPs){Export-HklmKeyOnce 'ExplorerGallery' $galleryNative;Remove-HklmKeyElevated $galleryNative}};Revert={if(Test-Path $galleryPs){return};Restore-HklmKeyElevated 'ExplorerGallery'};Detail='Explorer左ナビゲーションの「ギャラリー」を非表示にします。キーが既に無ければ、Winすっきり以外の方法で変更済みでもONとして認識します。写真データは削除しません。'},
 [pscustomobject]@{Id='TailoredExperiences';Cat='プライバシー';Title='診断データを使った個人向け提案をOFF';Subtitle='診断データ由来のおすすめを抑えます。';Risk='安全';NeedsAdmin=$false;Restart='不要';Recommended=$true;Exists={$true};IsApplied={(Get-RegValueSafe $regPrivacy 'TailoredExperiencesWithDiagnosticDataEnabled' 1) -eq 0};Apply={Backup-RegValueOnce 'TailoredExperiences' $regPrivacy 'TailoredExperiencesWithDiagnosticDataEnabled';Set-RegDword $regPrivacy 'TailoredExperiencesWithDiagnosticDataEnabled' 0};Revert={Restore-RegValueFromBackup 'TailoredExperiences' $regPrivacy 'TailoredExperiencesWithDiagnosticDataEnabled' 1};Detail='診断データを利用したパーソナライズされたヒントやおすすめを抑えます。'},
 [pscustomobject]@{Id='Animations';Cat='パフォーマンス';Title='ウィンドウのアニメーションを減らす';Subtitle='見た目の演出を少し抑えます。';Risk='安全';NeedsAdmin=$false;Restart='サインアウト';Recommended=$false;Exists={$true};IsApplied={(Get-RegValueSafe $regWindowMetrics 'MinAnimate' '1') -eq '0'};Apply={Backup-RegValueOnce 'MinAnimate' $regWindowMetrics 'MinAnimate';Set-RegString $regWindowMetrics 'MinAnimate' '0'};Revert={Restore-RegValueFromBackup 'MinAnimate' $regWindowMetrics 'MinAnimate' '1' 'String'};Detail='最小化・最大化などのアニメーションを減らします。FPSが上がる等を保証する設定ではありません。'},
 [pscustomobject]@{Id='MenuDelay';Cat='パフォーマンス';Title='メニュー表示の待ち時間を短くする';Subtitle='メニューが開くまでを100msにします。';Risk='注意';NeedsAdmin=$false;Restart='サインアウト';Recommended=$false;Exists={$true};IsApplied={(Get-RegValueSafe $regDesktop 'MenuShowDelay' '400') -eq '100'};Apply={Backup-RegValueOnce 'MenuShowDelay' $regDesktop 'MenuShowDelay';Set-RegString $regDesktop 'MenuShowDelay' '100'};Revert={Restore-RegValueFromBackup 'MenuShowDelay' $regDesktop 'MenuShowDelay' '400' 'String'};Detail='メニュー表示待ち時間を100msにします。極端な0msにはしません。'},

 [pscustomobject]@{Id='DisableHibernate';Cat='パフォーマンス';Title='休止状態を無効にする';Subtitle='powercfg /hibernate off を実行し、hiberfil.sysを削除して容量を確保します。';Risk='注意';NeedsAdmin=$true;Restart='不要';Recommended=$false;Exists={$true};IsApplied={Get-HibernateDisabled};Apply={Set-HibernateEnabled $false};Revert={Set-HibernateEnabled $true};Detail='休止状態を無効にするとhiberfil.sysが削除されます。Windowsの高速スタートアップも休止機能を利用するため、同時に使えなくなります。OFFに戻すと powercfg /hibernate on を実行します。'},
 [pscustomobject]@{Id='DnsCloudflare';Cat='詳細設定';Title='DNSをCloudflareにする';Subtitle='現在使っているIPv4の既定経路に 1.1.1.1 / 1.0.0.1 を設定します。';Risk='注意';NeedsAdmin=$true;Restart='不要';Recommended=$false;Exists={@(Get-DefaultDnsInterfaceIndexes).Count -gt 0};IsApplied={Get-DnsPresetApplied 'Cloudflare'};Apply={Set-DnsPreset 'Cloudflare'};Revert={Set-DnsPreset 'Auto'};Detail='既定ゲートウェイを持つ現在有効なIPv4ネットワーク接続にCloudflare DNSを設定します。OFFに戻すとDNSサーバーを自動取得へ戻します。VPNや会社管理PCなど独自DNSが必要な環境では使用しないでください。'},
 [pscustomobject]@{Id='DnsGoogle';Cat='詳細設定';Title='DNSをGoogleにする';Subtitle='現在使っているIPv4の既定経路に 8.8.8.8 / 8.8.4.4 を設定します。';Risk='注意';NeedsAdmin=$true;Restart='不要';Recommended=$false;Exists={@(Get-DefaultDnsInterfaceIndexes).Count -gt 0};IsApplied={Get-DnsPresetApplied 'Google'};Apply={Set-DnsPreset 'Google'};Revert={Set-DnsPreset 'Auto'};Detail='既定ゲートウェイを持つ現在有効なIPv4ネットワーク接続にGoogle Public DNSを設定します。OFFに戻すとDNSサーバーを自動取得へ戻します。VPNや会社管理PCなど独自DNSが必要な環境では使用しないでください。'},
 [pscustomobject]@{Id='NetplwizHelper';Cat='詳細設定';Title='自動ログイン設定の互換モードを有効にする';Subtitle='自動ログインのON/OFF状態そのものとは別の設定です。';Risk='上級';NeedsAdmin=$true;Restart='再起動';Recommended=$false;Exists={$true};IsApplied={(Get-RegValueSafe $pwdlessPs 'DevicePasswordLessBuildVersion' 2) -eq 0};Apply={Backup-RegValueOnce 'DevicePasswordLessBuildVersion' $pwdlessPs 'DevicePasswordLessBuildVersion';Set-HklmDwordElevated $pwdlessNative 'DevicePasswordLessBuildVersion' 0};Revert={$b=Get-BackupObject;$p=$b.PSObject.Properties['DevicePasswordLessBuildVersion'];$v=2;if($null -ne $p -and $p.Value.exists){$v=[int]$p.Value.value};Set-HklmDwordElevated $pwdlessNative 'DevicePasswordLessBuildVersion' $v};Detail='Windowsの自動ログイン設定で使われる互換設定を変更します。現在自動ログイン中かどうかとは別です。Windowsのバージョンやサインイン構成によっては、netplwizの従来チェック欄が表示されない場合があります。WinすっきりはパスワードやPINを取得・保存・変更しません。'}
)

# --- XAML -------------------------------------------------------------------
$xaml=@"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
 Title="Winすっきり v1.1" Height="680" Width="1120" MinHeight="560" MinWidth="900" ResizeMode="CanResize" WindowStartupLocation="CenterScreen" Background="#F4F6FA" FontFamily="Segoe UI, Yu Gothic UI">
 <Window.Resources>
  <Style TargetType="Button"><Setter Property="Padding" Value="14,9"/><Setter Property="Margin" Value="3"/><Setter Property="Background" Value="#FFFFFF"/><Setter Property="BorderBrush" Value="#D8DDE8"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border CornerRadius="8" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border></ControlTemplate></Setter.Value></Setter></Style>
  <Style x:Key="NavButton" TargetType="Button"><Setter Property="HorizontalContentAlignment" Value="Left"/><Setter Property="Background" Value="Transparent"/><Setter Property="BorderBrush" Value="Transparent"/><Setter Property="Margin" Value="0,2"/><Setter Property="Padding" Value="12,9"/></Style>
  <Style x:Key="ToggleStyle" TargetType="CheckBox"><Setter Property="Cursor" Value="Hand"/><Setter Property="Width" Value="52"/><Setter Property="Height" Value="28"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="CheckBox"><Grid Width="52" Height="28"><Border x:Name="track" CornerRadius="14" Background="#C8CEDA"/><Ellipse x:Name="dot" Width="22" Height="22" Fill="White" HorizontalAlignment="Left" Margin="3,0,0,0"/></Grid><ControlTemplate.Triggers><Trigger Property="IsChecked" Value="True"><Setter TargetName="track" Property="Background" Value="#6D5CE7"/><Setter TargetName="dot" Property="HorizontalAlignment" Value="Right"/><Setter TargetName="dot" Property="Margin" Value="0,0,3,0"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter TargetName="track" Property="Opacity" Value="0.45"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
 </Window.Resources>
 <Grid>
  <Grid.ColumnDefinitions><ColumnDefinition Width="235"/><ColumnDefinition Width="*"/><ColumnDefinition Width="340"/></Grid.ColumnDefinitions><Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="58"/></Grid.RowDefinitions>
  <Border Grid.Column="0" Grid.RowSpan="2" Background="#FAFBFD" BorderBrush="#E2E6EE" BorderThickness="0,0,1,0"><DockPanel Margin="14"><StackPanel DockPanel.Dock="Top"><TextBlock Text="◇ Winすっきり" FontSize="21" FontWeight="SemiBold" Margin="6,8,0,0"/><TextBlock Text="Windows 11を、もっとシンプルに。" Foreground="#697181" FontSize="12" Margin="6,4,0,16"/><Button x:Name="NavHome" Style="{StaticResource NavButton}" Content="⌂  ホーム"/><Button x:Name="NavSimple" Style="{StaticResource NavButton}" Content="⚡  シンプル化"/><Button x:Name="NavDesktop" Style="{StaticResource NavButton}" Content="▣  デスクトップ"/><Button x:Name="NavExplorer" Style="{StaticResource NavButton}" Content="▤  エクスプローラー"/><Button x:Name="NavStartup" Style="{StaticResource NavButton}" Content="↗  起動・スタートアップ"/><Button x:Name="NavCheck" Style="{StaticResource NavButton}" Content="✓  PCチェック"/><Button x:Name="NavPrivacy" Style="{StaticResource NavButton}" Content="●  プライバシー"/><Button x:Name="NavPerf" Style="{StaticResource NavButton}" Content="↯  パフォーマンス"/><Button x:Name="NavAdvanced" Style="{StaticResource NavButton}" Content="⚙  詳細設定"/><Button x:Name="NavFolders" Style="{StaticResource NavButton}" Content="▰  ユーザーフォルダーの保存場所" Margin="12,2,0,2"/></StackPanel><StackPanel DockPanel.Dock="Bottom"><Separator Margin="0,8"/><Button x:Name="BtnExport" Content="💾  マイ設定を保存" HorizontalContentAlignment="Left"/><Button x:Name="BtnImport" Content="📂  マイ設定を読み込む" HorizontalContentAlignment="Left"/><Button x:Name="BtnRestoreLast" Content="↶  直前の変更を元に戻す" HorizontalContentAlignment="Left"/><TextBlock Text="v1.1" Foreground="#9AA1AE" FontSize="11" Margin="8,8,0,0"/></StackPanel></DockPanel></Border>
  <Grid Grid.Column="1" Margin="26,20,18,12"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions><TextBlock x:Name="PageTitle" Text="ホーム" FontSize="27" FontWeight="SemiBold"/><Grid Grid.Row="1" Margin="0,10,0,12"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock x:Name="SummaryText" Text="現在の状態を読み込み中..." VerticalAlignment="Center" Foreground="#5F6673"/><StackPanel Grid.Column="1" Orientation="Horizontal"><Button x:Name="BtnRecommended" Content="おすすめを選択"/><Button x:Name="BtnReload" Content="↻ 再読込"/></StackPanel></Grid><Grid Grid.Row="2"><ScrollViewer x:Name="SettingsScroll" VerticalScrollBarVisibility="Auto"><StackPanel x:Name="SettingsPanel"/></ScrollViewer><ScrollViewer x:Name="SpecialScroll" Visibility="Collapsed" VerticalScrollBarVisibility="Auto"><StackPanel x:Name="SpecialPanel"/></ScrollViewer></Grid></Grid>
  <ScrollViewer Grid.Column="2" Margin="0,20,18,12" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"><Border Margin="0" Background="#F8F9FC" CornerRadius="12" BorderBrush="#E0E4ED" BorderThickness="1" Padding="20"><StackPanel><TextBlock Text="詳細" FontSize="22" FontWeight="SemiBold" Margin="0,0,0,16"/><Border x:Name="RiskBorder" Background="#E9E6FF" CornerRadius="8" Padding="8,4" HorizontalAlignment="Left"><TextBlock x:Name="DetailRisk" Text="安全" Foreground="#5146BE" FontWeight="SemiBold"/></Border><TextBlock x:Name="DetailTitle" Text="Winすっきり" FontSize="18" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,14,0,8"/><TextBlock x:Name="DetailBody" Text="左のカテゴリから設定やPCチェックを選べます。" Foreground="#636B7A" TextWrapping="Wrap" LineHeight="22"/><Separator Margin="0,20"/><Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions><StackPanel><TextBlock Text="管理者権限" Foreground="#8B92A0" FontSize="12"/><TextBlock x:Name="DetailAdmin" Text="不要" FontWeight="SemiBold" Margin="0,4,0,0"/></StackPanel><StackPanel Grid.Column="1"><TextBlock Text="反映" Foreground="#8B92A0" FontSize="12"/><TextBlock x:Name="DetailRestart" Text="すぐ反映" FontWeight="SemiBold" Margin="0,4,0,0"/></StackPanel></Grid><Button x:Name="BtnNetplwiz" Content="netplwizを開く" Visibility="Collapsed" Margin="0,22,0,0"/><Button x:Name="BtnSignInOptions" Content="サインイン オプションを開く" Visibility="Collapsed" Margin="0,8,0,0"/><Button x:Name="BtnOneDriveStop" Content="OneDriveを終了" Visibility="Collapsed" Margin="0,8,0,0"/><Button x:Name="BtnExplorerRestart" Content="Explorerを再起動" Visibility="Collapsed" Margin="0,10,0,0"/><Border Background="#FFF7DA" CornerRadius="8" Padding="12" Margin="0,18,0,0"><TextBlock Text="削除系・Defender/UAC/Windows Update停止・怪しい高速化は行いません。" TextWrapping="Wrap" Foreground="#675B2A"/></Border></StackPanel></Border></ScrollViewer>
  <Border Grid.Column="1" Grid.ColumnSpan="2" Grid.Row="1" Background="White" BorderBrush="#E3E7EF" BorderThickness="0,1,0,0"><Grid Margin="18,8"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock x:Name="StatusText" Text="準備完了" VerticalAlignment="Center" Foreground="#687080"/><Button x:Name="BtnApply" Grid.Column="1" Content="選択した変更を適用" Background="#6D5CE7" Foreground="White" BorderBrush="#6D5CE7" Padding="22,9"/></Grid></Border>
 </Grid>
</Window>
"@
[xml]$xml=$xaml;$reader=New-Object System.Xml.XmlNodeReader $xml;$window=[Windows.Markup.XamlReader]::Load($reader)

# 実行基準フォルダー（PS1 / EXE 両対応）
# PS2EXE では $PSScriptRoot / [Environment]::ProcessPath の挙動差があるため、
# 実行中プロセスの MainModule.FileName を最優先にして確実に EXE の実体位置を取ります。
$processPath = $null
$script:WinSukkiriBaseDir = $null

try {
    $processPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
} catch {
    $processPath = $null
}

try {
    if (-not [string]::IsNullOrWhiteSpace([string]$processPath)) {
        $processName = [IO.Path]::GetFileName([string]$processPath)
        $processExt  = [IO.Path]::GetExtension([string]$processPath)

        if (($processExt -ieq '.exe') -and
            ($processName -notmatch '^(powershell|powershell_ise|pwsh)(\.exe)?$')) {
            $script:WinSukkiriBaseDir = [IO.Path]::GetDirectoryName([string]$processPath)
        }
    }
} catch {
    $script:WinSukkiriBaseDir = $null
}

# PS1 / VBS 経由の実行ではスクリプト自身の場所を使います。
if ([string]::IsNullOrWhiteSpace([string]$script:WinSukkiriBaseDir)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$PSScriptRoot)) {
        $script:WinSukkiriBaseDir = [string]$PSScriptRoot
    }
}

# 最後の保険。空のままにはしません。
if ([string]::IsNullOrWhiteSpace([string]$script:WinSukkiriBaseDir)) {
    try {
        $script:WinSukkiriBaseDir = (Get-Location).Path
    } catch {
        $script:WinSukkiriBaseDir = $null
    }
}

# 正式アイコン
try{
    $iconPath=Join-Path $script:WinSukkiriBaseDir 'WinSukkiri.ico'
    if(Test-Path -LiteralPath $iconPath){
        $iconUri=New-Object System.Uri($iconPath,[System.UriKind]::Absolute)
        $window.Icon=[System.Windows.Media.Imaging.BitmapFrame]::Create($iconUri)
    } elseif($processPath -and (Test-Path -LiteralPath $processPath)) {
        Add-Type -AssemblyName System.Drawing
        $exeIcon=[System.Drawing.Icon]::ExtractAssociatedIcon($processPath)
        if($exeIcon){
            $bmp=[System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon(
                $exeIcon.Handle,
                [System.Windows.Int32Rect]::Empty,
                [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions()
            )
            $window.Icon=$bmp
        }
    }
}catch{
    # アイコン読込失敗だけで本体を止めない
}

function W($n){$window.FindName($n)}
$SettingsPanel=W 'SettingsPanel';$SpecialPanel=W 'SpecialPanel';$SettingsScroll=W 'SettingsScroll';$SpecialScroll=W 'SpecialScroll';$PageTitle=W 'PageTitle';$SummaryText=W 'SummaryText';$StatusText=W 'StatusText';$DetailRisk=W 'DetailRisk';$RiskBorder=W 'RiskBorder';$DetailTitle=W 'DetailTitle';$DetailBody=W 'DetailBody';$DetailAdmin=W 'DetailAdmin';$DetailRestart=W 'DetailRestart';$BtnApply=W 'BtnApply';$BtnRecommended=W 'BtnRecommended';$BtnNetplwiz=W 'BtnNetplwiz';$BtnSignInOptions=W 'BtnSignInOptions';$BtnOneDriveStop=W 'BtnOneDriveStop'
$toggleMap=@{};$cardMap=@{};$initialMap=@{};$script:startupToggleMap=@{};$script:startupInitialMap=@{};$script:startupItemMap=@{};$script:currentPage='Home';$script:currentSettingsCategory=''
function Brush($hex){New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($hex))}
function Update-Details($s){
    $DetailRisk.Text=$s.Risk;$DetailTitle.Text=$s.Title
    $body=$s.Detail
    if($s.Id -eq 'NetplwizHelper'){$body+="`n`n現在の自動ログイン: " + $(if(Get-AutoLogonStatus){'有効 ✓'}else{'無効 / 検出なし'}) + "`n`n※ PIN・パスワードの変更や削除はWindowsの「サインイン オプション」から行ってください。Winすっきりは認証情報を操作しません。"}
    $DetailBody.Text=$body
    $DetailAdmin.Text=if($s.NeedsAdmin){'必要（実行時に確認）'}else{'不要'}
    $DetailRestart.Text=switch($s.Restart){'Explorer'{'Explorer再起動で確実'}'サインアウト'{'サインアウト後'}'再起動'{'Windows再起動後'}default{'すぐ反映'}}
    $RiskBorder.Background=if($s.Risk -eq '安全'){Brush '#E8F7EF'}elseif($s.Risk -eq '上級'){Brush '#FFE4E4'}else{Brush '#FFF4D6'}
    $BtnNetplwiz.Visibility=if($s.Id -eq 'NetplwizHelper'){'Visible'}else{'Collapsed'};$BtnSignInOptions.Visibility=if($s.Id -eq 'NetplwizHelper'){'Visible'}else{'Collapsed'};$BtnOneDriveStop.Visibility=if($s.Id -eq 'OneDrive'){'Visible'}else{'Collapsed'};if($null -ne $BtnExplorerRestart){$BtnExplorerRestart.Visibility=if($s.Cat -eq 'エクスプローラー'){'Visible'}else{'Collapsed'}}
}
function Add-SettingCard($s){$b=New-Object Windows.Controls.Border;$b.Background='White';$b.BorderBrush=Brush '#E0E4ED';$b.BorderThickness=1;$b.CornerRadius=10;$b.Margin='0,0,0,10';$b.Padding='14,12';$b.Cursor='Hand';$g=New-Object Windows.Controls.Grid;$g.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition));$c=New-Object Windows.Controls.ColumnDefinition;$c.Width='Auto';$g.ColumnDefinitions.Add($c);$sp=New-Object Windows.Controls.StackPanel;$t=New-Object Windows.Controls.TextBlock;$t.Text=$s.Title;$t.FontSize=15;$t.FontWeight='SemiBold';$t.TextWrapping='Wrap';$sub=New-Object Windows.Controls.TextBlock;$sub.Text=$s.Subtitle;$sub.Foreground=Brush '#77808F';$sub.FontSize=12;$sub.Margin='0,4,0,0';$sub.TextWrapping='Wrap';$sp.Children.Add($t)|Out-Null;$sp.Children.Add($sub)|Out-Null;$g.Children.Add($sp)|Out-Null;$tog=New-Object Windows.Controls.CheckBox;$tog.Style=$window.Resources['ToggleStyle'];$tog.VerticalAlignment='Center';$tog.Margin='16,0,0,0';[Windows.Controls.Grid]::SetColumn($tog,1);$g.Children.Add($tog)|Out-Null;$b.Child=$g;$SettingsPanel.Children.Add($b)|Out-Null;$toggleMap[$s.Id]=$tog;$cardMap[$s.Id]=$b;$b.Tag=$s;$b.Add_MouseLeftButtonUp({param($sender,$e) Update-Details $sender.Tag})}
foreach($s in $settings){Add-SettingCard $s}
function Reload-State{$ap=0;$av=0;foreach($s in $settings){$t=$toggleMap[$s.Id];try{$ex=[bool](& $s.Exists)}catch{$ex=$false};$t.IsEnabled=$ex;if($ex){$av++;try{$v=[bool](& $s.IsApplied)}catch{$v=$false};$t.IsChecked=$v;$initialMap[$s.Id]=$v;if($v){$ap++}}else{$t.IsChecked=$false;$initialMap[$s.Id]=$false}};$SummaryText.Text="現在 $ap / $av 項目をすっきり設定済み";$StatusText.Text='現在のWindows設定を読み込みました。'}
function Show-SettingsCategory($cat){$script:currentPage='Settings';$script:currentSettingsCategory=$cat;$SpecialScroll.Visibility='Collapsed';$SettingsScroll.Visibility='Visible';$BtnApply.Visibility='Visible';$BtnRecommended.Visibility=if($cat -eq 'シンプル化'){'Visible'}else{'Collapsed'};$PageTitle.Text=$cat;foreach($s in $settings){$cardMap[$s.Id].Visibility=if($s.Cat-eq$cat){'Visible'}else{'Collapsed'}};$catSettings=@($settings|Where-Object Cat -eq $cat);$count=$catSettings.Count;$SummaryText.Text="$count 項目の設定があります。";if($cat -eq '詳細設定' -and $count -eq 1){Update-Details ($catSettings[0])}else{$DetailRisk.Text='安全';$DetailAdmin.Text='項目を選択';$DetailRestart.Text='項目を選択';$DetailTitle.Text=$cat;$DetailBody.Text='項目をクリックすると、現在状態の判定方法と変更内容を表示します。';$BtnNetplwiz.Visibility='Collapsed';$BtnSignInOptions.Visibility='Collapsed';$BtnOneDriveStop.Visibility='Collapsed';if($null -ne $BtnExplorerRestart){$BtnExplorerRestart.Visibility=if($cat -eq 'エクスプローラー'){'Visible'}else{'Collapsed'}}}}
function Add-SpecialHeader($title,$body){$t=New-Object Windows.Controls.TextBlock;$t.Text=$title;$t.FontSize=20;$t.FontWeight='SemiBold';$t.Margin='0,4,0,6';$SpecialPanel.Children.Add($t)|Out-Null;$d=New-Object Windows.Controls.TextBlock;$d.Text=$body;$d.Foreground=Brush '#667085';$d.TextWrapping='Wrap';$d.Margin='0,0,0,14';$SpecialPanel.Children.Add($d)|Out-Null}
function Add-InfoCard($title,$value,$note=''){$b=New-Object Windows.Controls.Border;$b.Background='White';$b.BorderBrush=Brush '#E0E4ED';$b.BorderThickness=1;$b.CornerRadius=10;$b.Margin='0,0,0,9';$b.Padding='14';$sp=New-Object Windows.Controls.StackPanel;$t=New-Object Windows.Controls.TextBlock;$t.Text=$title;$t.FontWeight='SemiBold';$v=New-Object Windows.Controls.TextBlock;$v.Text=$value;$v.FontSize=16;$v.Margin='0,4,0,0';$sp.Children.Add($t)|Out-Null;$sp.Children.Add($v)|Out-Null;if($note){$n=New-Object Windows.Controls.TextBlock;$n.Text=$note;$n.Foreground=Brush '#77808F';$n.TextWrapping='Wrap';$n.Margin='0,4,0,0';$sp.Children.Add($n)|Out-Null};$b.Child=$sp;$SpecialPanel.Children.Add($b)|Out-Null}
function Show-Home{
    $script:currentPage='Home'
    $SettingsScroll.Visibility='Collapsed';$SpecialScroll.Visibility='Visible';$BtnApply.Visibility='Collapsed';$BtnRecommended.Visibility='Collapsed';$PageTitle.Text='ホーム';$SpecialPanel.Children.Clear()
    Add-SpecialHeader 'Windows 11を、もっとシンプルに。' 'チェックして、整えて、いつものPCへ。'
    $ap=($settings|Where-Object{$toggleMap[$_.Id].IsEnabled -and $toggleMap[$_.Id].IsChecked}).Count
    Add-InfoCard 'すっきり設定' "$ap / $($settings.Count) 項目" '紫のONは「目的の状態になっている」を表します。Winすっきり以外で変更済みでも認識します。'
    $startup=@(Get-StartupItems);Add-InfoCard 'スタートアップ' "$($startup.Count) 件を検出" 'Run、Windowsの無効化状態、スタートアップフォルダーなどをまとめて確認します。'
    Add-InfoCard '次におすすめ' 'PCチェック' 'ドライバー未適用・空き容量・再起動待ち理由などを確認できます。'
    $SummaryText.Text='Winすっきり v1.1';$DetailRisk.Text='安全';$DetailAdmin.Text='不要';$DetailRestart.Text='すぐ反映';$DetailTitle.Text='ホーム';$DetailBody.Text='Winすっきりはキーボードのファンクションキーに頼らず、補助機能も画面からマウスで開けます。現在のWindowsが目的の状態かを優先して判定します。'
}
function Set-StartupItemState {
    param($item,[bool]$Enabled)
    switch($item.Bucket){
        'TeamsSpecial' { Set-TeamsStartupEnabled $Enabled; break }
        'AppxStartupTask' { Set-AppxStartupTaskState $item.Scope $item.Name $Enabled; break }
        default { Set-StartupApprovedState $item.Bucket $item.Name $Enabled $item.Scope; break }
    }
}
function Add-StartupCard($item){
    $b=New-Object Windows.Controls.Border;$b.Background='White';$b.BorderBrush=Brush '#E0E4ED';$b.BorderThickness=1;$b.CornerRadius=10;$b.Margin='0,0,0,8';$b.Padding='13'
    $g=New-Object Windows.Controls.Grid;$g.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition));$cc=New-Object Windows.Controls.ColumnDefinition;$cc.Width='Auto';$g.ColumnDefinitions.Add($cc)
    $sp=New-Object Windows.Controls.StackPanel;$t=New-Object Windows.Controls.TextBlock;$t.Text=$item.DisplayName;$t.FontWeight='SemiBold'
    $sub=New-Object Windows.Controls.TextBlock;$sub.Text=($item.Source+'  |  '+$item.Command);$sub.Foreground=Brush '#77808F';$sub.FontSize=11;$sub.TextTrimming='CharacterEllipsis';$sub.MaxWidth=520
    $sp.Children.Add($t)|Out-Null;$sp.Children.Add($sub)|Out-Null;$g.Children.Add($sp)|Out-Null
    $tog=New-Object Windows.Controls.CheckBox;$tog.Style=$window.Resources['ToggleStyle'];$tog.IsChecked=-not [bool]$item.Enabled;$tog.VerticalAlignment='Center';$tog.IsEnabled=[bool]$item.CanEdit
    $tog.Tag=$item.Key;[Windows.Controls.Grid]::SetColumn($tog,1)
    $tog.Add_Click({
        param($sender,$e)
        $key=[string]$sender.Tag
        $it=$script:startupItemMap[$key]
        $before=[bool]$script:startupInitialMap[$key];$after=[bool]$sender.IsChecked
        if($before -ne $after){$StatusText.Text="「$($it.DisplayName)」を変更予定にしました。［選択した変更を適用］で反映します。"}
        else{$StatusText.Text="「$($it.DisplayName)」は現在の設定と同じです。"}
    })
    $g.Children.Add($tog)|Out-Null;$b.Child=$g;$SpecialPanel.Children.Add($b)|Out-Null
    $script:startupToggleMap[$item.Key]=$tog;$script:startupInitialMap[$item.Key]=-not [bool]$item.Enabled;$script:startupItemMap[$item.Key]=$item
}
function Show-Startup{
    $script:currentPage='Startup'
    $SettingsScroll.Visibility='Collapsed';$SpecialScroll.Visibility='Visible';$BtnApply.Visibility='Visible';$BtnRecommended.Visibility='Collapsed';$PageTitle.Text='起動・スタートアップ';$SpecialPanel.Children.Clear()
    $script:startupToggleMap=@{};$script:startupInitialMap=@{};$script:startupItemMap=@{}
    Add-SpecialHeader 'スタートアップ管理' 'Windows標準のStartupTask、Run、StartupApproved、スタートアップフォルダーをまとめて表示します。紫ON＝自動起動しない（すっきり状態）です。最後に［選択した変更を適用］で反映します。'
    $items=@(Get-StartupItems)
    if(!$items.Count){Add-InfoCard 'スタートアップ' '登録なし'}else{foreach($it in $items){Add-StartupCard $it}}
    $btn=New-Object Windows.Controls.Button;$btn.Content='Windowsのスタートアップ設定を開く';$btn.HorizontalAlignment='Left';$btn.Margin='0,8,0,0';$btn.Add_Click({Start-Process 'ms-settings:startupapps'});$SpecialPanel.Children.Add($btn)|Out-Null
    $SummaryText.Text="$($items.Count) 件を検出";$DetailRisk.Text='安全';$DetailAdmin.Text='ユーザー項目は不要 / 全ユーザー項目は権限が必要な場合あり';$DetailRestart.Text='次回サインイン';$DetailTitle.Text='スタートアップ管理';$DetailBody.Text='Windows設定に出るMicrosoft系StartupTaskも表示します。Windows側で変更した後は［現在の設定を再読み込み］で一覧を作り直します。'
}
function Apply-StartupChanges {
    $changes=@()
    foreach($key in @($script:startupToggleMap.Keys)){
        $t=$script:startupToggleMap[$key];$was=[bool]$script:startupInitialMap[$key];$want=[bool]$t.IsChecked
        if($want -ne $was){$changes += [pscustomobject]@{Key=$key;Item=$script:startupItemMap[$key];Want=$want}}
    }
    if(!$changes){[System.Windows.MessageBox]::Show('スタートアップに変更する項目はありません。',$appName)|Out-Null;return}
    $preview=($changes|ForEach-Object{"・$($_.Item.DisplayName) → Winすっきり $(if($_.Want){'ON（自動起動 OFF）'}else{'OFF（自動起動 ON）'})"})-join"`n"
    if([System.Windows.MessageBox]::Show("選択したスタートアップ設定を適用します。`n`n$preview`n`nよろしいですか？",$appName,'YesNo','Question') -ne 'Yes'){$StatusText.Text='変更をキャンセルしました。';return}
    $ok=@();$err=@();$window.Cursor=[Windows.Input.Cursors]::Wait
    try{
        foreach($c in $changes){
            try{Set-StartupItemState $c.Item (-not [bool]$c.Want);$ok+=$c.Item.DisplayName}
            catch{$err+="$($c.Item.DisplayName): $($_.Exception.Message)"}
        }
    }finally{$window.Cursor=[Windows.Input.Cursors]::Arrow}
    Show-Startup
    $msg="変更しました: $($ok.Count) 項目"
    if($ok.Count){$msg+="`n"+(($ok|ForEach-Object{"✓ $_"})-join"`n")}
    if($err.Count){$msg+="`n`n変更できませんでした: $($err.Count) 項目`n"+(($err|ForEach-Object{"⚠ $_"})-join"`n")}
    [System.Windows.MessageBox]::Show($msg,$appName,'OK',$(if($err.Count){'Warning'}else{'Information'}))|Out-Null
    $StatusText.Text="スタートアップ: 成功 $($ok.Count) / 失敗 $($err.Count)"
}
function Get-UserFolderLocations {
    $shell='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    $defs=@(
        @{Name='デスクトップ'; Reg='Desktop'; Fallback=[Environment]::GetFolderPath('Desktop')},
        @{Name='ダウンロード'; Reg='{374DE290-123F-4565-9164-39C4925E467B}'; Fallback=(Join-Path $env:USERPROFILE 'Downloads')},
        @{Name='ドキュメント'; Reg='Personal'; Fallback=[Environment]::GetFolderPath('MyDocuments')},
        @{Name='ピクチャ'; Reg='My Pictures'; Fallback=[Environment]::GetFolderPath('MyPictures')},
        @{Name='ミュージック'; Reg='My Music'; Fallback=[Environment]::GetFolderPath('MyMusic')},
        @{Name='ビデオ'; Reg='My Video'; Fallback=[Environment]::GetFolderPath('MyVideos')}
    )
    foreach($d in $defs){
        $raw=Get-RegValueSafe $shell $d.Reg $d.Fallback
        $path=[Environment]::ExpandEnvironmentVariables([string]$raw)
        [pscustomobject]@{Name=$d.Name;Path=$path;Exists=(Test-Path -LiteralPath $path)}
    }
}
function Test-PathUnderOneDrive([string]$Path){
    if([string]::IsNullOrWhiteSpace($Path)){return $false}

    # Known Folder が明示的に OneDrive 配下なら、環境変数の状態に関係なく捕捉する。
    # OneDriveを終了した直後や構成差のあるPCでも安全側に倒す。
    $normalized = $Path.Replace('/','\\').TrimEnd('\\')
    if($normalized -match '(?i)\\OneDrive(?:\\|$)'){ return $true }

    $roots=@()
    foreach($n in @('OneDrive','OneDriveConsumer','OneDriveCommercial')){
        $v=[Environment]::GetEnvironmentVariable($n,'Process')
        if(-not [string]::IsNullOrWhiteSpace($v)){$roots+=$v.TrimEnd('\\')}
    }
    $roots+=@(Get-ChildItem Env: -ErrorAction SilentlyContinue|Where-Object Name -like 'OneDrive*'|ForEach-Object{$_.Value.TrimEnd('\\')})
    foreach($r in @($roots|Select-Object -Unique)){
        if($Path.TrimEnd('\\').Equals($r,[StringComparison]::OrdinalIgnoreCase) -or $Path.StartsWith($r+'\\',[StringComparison]::OrdinalIgnoreCase)){return $true}
    }
    return $false
}
function Move-UserKnownFolder($folder){
    $dlg=New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description="$($folder.Name) の新しい保存場所を選択してください。"
    $dlg.ShowNewFolderButton=$true
    if(Test-Path -LiteralPath $folder.Path){$dlg.SelectedPath=$folder.Path}

    # FolderBrowserDialog の標準UIが英語になる環境への対策。
    # 表示中だけ日本語カルチャを明示し、終了後は元へ戻す。
    $thread=[System.Threading.Thread]::CurrentThread
    $oldUiCulture=$thread.CurrentUICulture
    $oldCulture=$thread.CurrentCulture
    try{
        $ja=[System.Globalization.CultureInfo]::GetCultureInfo('ja-JP')
        $thread.CurrentUICulture=$ja
        $thread.CurrentCulture=$ja
        $dialogResult=$dlg.ShowDialog()
    }finally{
        $thread.CurrentUICulture=$oldUiCulture
        $thread.CurrentCulture=$oldCulture
    }
    if($dialogResult -ne [System.Windows.Forms.DialogResult]::OK){return}
    $dest=$dlg.SelectedPath.TrimEnd('\\')
    $src=$folder.Path.TrimEnd('\\')
    if($dest -eq $src){[System.Windows.MessageBox]::Show('現在と同じ場所です。',$appName)|Out-Null;return}
    if($dest -match '^[A-Za-z]:\\?$'){[System.Windows.MessageBox]::Show('ドライブ直下は選べません。D:\\user\\デスクトップ のような専用フォルダーを選んでください。',$appName,'OK','Warning')|Out-Null;return}
    try{New-Item -ItemType Directory -Path $dest -Force|Out-Null}catch{[System.Windows.MessageBox]::Show("移動先を作成できません。`n$($_.Exception.Message)",$appName,'OK','Error')|Out-Null;return}

    $srcIsOneDrive=Test-PathUnderOneDrive $src
    $oneDriveRunning=$null -ne (Get-Process -Name OneDrive -ErrorAction SilentlyContinue)
    $move=[System.Windows.MessageBox]::Show("$($folder.Name) の保存場所を変更します。`n`n現在: $src`n変更先: $dest`n`n現在のファイルも新しい場所へ移動しますか？`n「いいえ」なら保存場所だけ変更します。`n`n※ 移動するフォルダー内のファイルを使用しているアプリは、先に終了してください。",$appName,'YesNoCancel','Question')
    if($move -eq 'Cancel'){return}

    if($move -eq 'Yes' -and $srcIsOneDrive -and -not $oneDriveRunning){
        $safe=[System.Windows.MessageBox]::Show("現在の保存場所はOneDrive配下ですが、OneDriveは起動していません。`n`nこの状態ではクラウド管理中のファイルを安全に移動できない場合があります。`n`n既存ファイルには触れず、保存場所だけ新しいローカルフォルダーへ変更しますか？`n`n［はい］保存場所だけ変更`n［いいえ］何も変更しない",$appName,'YesNo','Warning')
        if($safe -ne 'Yes'){$StatusText.Text='ユーザーフォルダーの変更をキャンセルしました。';return}
        $move='No'
    }

    try{
        $shell='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
        Backup-RegValueOnce ('KnownFolder_'+$folder.Reg) $shell $folder.Reg
        if($move -eq 'Yes' -and (Test-Path -LiteralPath $src)){
            # Winすっきり自身が移動元の中にあると、自分自身を移動できず失敗するため事前に止める。
            # EXE / PS1 の実体位置を正規化して自己移動を防止
            if ([string]::IsNullOrWhiteSpace([string]$script:WinSukkiriBaseDir)) {
                throw 'Winすっきり本体の実行場所を取得できませんでした。'
            }

            $appRoot=[System.IO.Path]::GetFullPath([string]$script:WinSukkiriBaseDir).TrimEnd('\')
            $srcFull=[System.IO.Path]::GetFullPath([string]$src).TrimEnd('\')
            if($appRoot.Equals($srcFull,[StringComparison]::OrdinalIgnoreCase) -or
               $appRoot.StartsWith($srcFull+'\',[StringComparison]::OrdinalIgnoreCase)){
                [System.Windows.MessageBox]::Show("Winすっきりが、移動対象の $($folder.Name) 内から起動されています。`n`nこのままではWinすっきり自身を移動できません。`nWinすっきりを別の場所へ移動してから、もう一度お試しください。",$appName,'OK','Warning')|Out-Null
                return
            }
            # 最終防衛線：OneDrive停止中のOneDrive配下には絶対にMove-Itemしない。
            if((Test-PathUnderOneDrive $src) -and ($null -eq (Get-Process -Name OneDrive -ErrorAction SilentlyContinue))){
                throw '安全機構により停止しました。OneDrive停止中のOneDrive配下から既存ファイルは移動しません。'
            }
            Get-ChildItem -LiteralPath $src -Force -ErrorAction Stop|ForEach-Object{Move-Item -LiteralPath $_.FullName -Destination $dest -Force -ErrorAction Stop}
        }
        Set-RegString $shell $folder.Reg $dest
        $what=if($move -eq 'Yes'){'既存ファイルを移動し、保存場所を変更しました。'}else{'既存ファイルには触れず、保存場所だけ変更しました。'}
        [System.Windows.MessageBox]::Show("$($folder.Name)：$what`n`nExplorerを再起動すると表示に反映されます。",$appName)|Out-Null
        $StatusText.Text="$($folder.Name) の保存場所を変更しました。"
        Show-UserFolders
    }catch{
        $msg=[string]$_.Exception.Message
        if($msg -match '(?i)in use|being used|使用中|別のプロセス'){
            [System.Windows.MessageBox]::Show("使用中のファイルまたはフォルダーがあるため、移動できませんでした。`n`n移動対象のファイルを使用しているアプリを終了して、もう一度お試しください。`n`n保存場所の変更は完了していません。",$appName,'OK','Warning')|Out-Null
        }else{
            [System.Windows.MessageBox]::Show("変更できませんでした。`n`n$msg",$appName,'OK','Error')|Out-Null
        }
    }
}
function Show-UserFolders {
    $script:currentPage='Folders'
    $SettingsScroll.Visibility='Collapsed';$SpecialScroll.Visibility='Visible';$BtnApply.Visibility='Collapsed';$BtnRecommended.Visibility='Collapsed';$PageTitle.Text='ユーザーフォルダーの保存場所';$SpecialPanel.Children.Clear()
    Add-SpecialHeader 'デスクトップなどの保存場所' 'Windowsが使っている6フォルダーの現在位置を確認できます。「変更」で新しい保存先を選べます。'
    Add-InfoCard '変更する前に' '移動対象のファイルを使用しているアプリを終了してください。' 'Winすっきり自身が移動対象フォルダー内にある場合は、別の場所へ移してから実行してください。OneDrive配下から移動する場合は同期状態も確認してください。大切なファイルは事前のバックアップをおすすめします。'
    $shell='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    $defs=@(
        @{Name='デスクトップ'; Reg='Desktop'; Fallback=[Environment]::GetFolderPath('Desktop')},
        @{Name='ダウンロード'; Reg='{374DE290-123F-4565-9164-39C4925E467B}'; Fallback=(Join-Path $env:USERPROFILE 'Downloads')},
        @{Name='ドキュメント'; Reg='Personal'; Fallback=[Environment]::GetFolderPath('MyDocuments')},
        @{Name='ピクチャ'; Reg='My Pictures'; Fallback=[Environment]::GetFolderPath('MyPictures')},
        @{Name='ミュージック'; Reg='My Music'; Fallback=[Environment]::GetFolderPath('MyMusic')},
        @{Name='ビデオ'; Reg='My Video'; Fallback=[Environment]::GetFolderPath('MyVideos')}
    )
    foreach($d in $defs){
        $raw=Get-RegValueSafe $shell $d.Reg $d.Fallback;$path=[Environment]::ExpandEnvironmentVariables([string]$raw)
        $f=[pscustomobject]@{Name=$d.Name;Reg=$d.Reg;Path=$path;Exists=(Test-Path -LiteralPath $path)}
        $b=New-Object Windows.Controls.Border;$b.Background='White';$b.BorderBrush=Brush '#E0E4ED';$b.BorderThickness=1;$b.CornerRadius=10;$b.Margin='0,0,0,9';$b.Padding='14'
        $g=New-Object Windows.Controls.Grid;$g.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition));$c=New-Object Windows.Controls.ColumnDefinition;$c.Width='Auto';$g.ColumnDefinitions.Add($c)
        $sp=New-Object Windows.Controls.StackPanel;$t=New-Object Windows.Controls.TextBlock;$t.Text=$f.Name;$t.FontWeight='SemiBold';$v=New-Object Windows.Controls.TextBlock;$v.Text=$f.Path;$v.FontSize=14;$v.Margin='0,4,12,0';$v.TextWrapping='Wrap';$sp.Children.Add($t)|Out-Null;$sp.Children.Add($v)|Out-Null;$g.Children.Add($sp)|Out-Null
        $btn=New-Object Windows.Controls.Button;$btn.Content='変更';$btn.VerticalAlignment='Center';$local=$f;$btn.Add_Click({Move-UserKnownFolder $local}.GetNewClosure());[Windows.Controls.Grid]::SetColumn($btn,1);$g.Children.Add($btn)|Out-Null;$b.Child=$g;$SpecialPanel.Children.Add($b)|Out-Null
    }
    $SummaryText.Text='6 個のユーザーフォルダーの保存場所';$DetailRisk.Text='注意';$RiskBorder.Background=Brush '#FFF4D6';$DetailAdmin.Text='不要';$DetailRestart.Text='Explorer';$DetailTitle.Text='保存場所の確認・変更';$DetailBody.Text='変更前に、移動対象のファイルを使用しているアプリを終了してください。Winすっきり自身が移動対象フォルダー内にある場合は事前に警告します。OneDrive配下でOneDriveが停止中の場合は、既存ファイルには触れず保存場所だけ変更する安全確認を行います。ドライブ直下は選べません。';$BtnNetplwiz.Visibility='Collapsed';$BtnSignInOptions.Visibility='Collapsed';$BtnOneDriveStop.Visibility='Collapsed';if($null -ne $BtnExplorerRestart){$BtnExplorerRestart.Visibility='Collapsed'}
}
function Show-PCCheck{
    $script:currentPage='Check'
    $SettingsScroll.Visibility='Collapsed';$SpecialScroll.Visibility='Visible';$BtnApply.Visibility='Collapsed';$BtnRecommended.Visibility='Collapsed';$PageTitle.Text='PCチェック';$SpecialPanel.Children.Clear();$StatusText.Text='PCをチェックしています...';$window.Cursor=[Windows.Input.Cursors]::Wait
    try{
        Add-SpecialHeader 'このPCをチェック' '変更は行いません。Windows初期セットアップ時の確認用です。'
        $os=Get-WindowsDisplayName;$ver=if($os.DisplayVersion){"  Version $($os.DisplayVersion)"}else{''};Add-InfoCard 'Windows' "$($os.Name)$ver  Build $($os.Build)"
        $drv=Get-PSDrive -Name C;$free=[math]::Round($drv.Free/1GB,1);$total=[math]::Round(($drv.Used+$drv.Free)/1GB,1);Add-InfoCard 'C: 空き容量' "$free GB / $total GB" $(if($free -lt 20){'空き容量が少なめです。'}else{'空き容量は十分あります。'})
        $bad=@();try{$bad=Get-PnpDevice -PresentOnly -ErrorAction Stop|Where-Object{$_.Status -ne 'OK' -and $_.Status -ne 'Unknown'}}catch{};Add-InfoCard 'デバイス' $(if($bad.Count -eq 0){'問題なし ✓'}else{"問題あり $($bad.Count) 件"}) $(if($bad.Count){(($bad|Select-Object -First 5|ForEach-Object{"$($_.Status): $($_.FriendlyName)"})-join"`n")}else{'PnPデバイスにエラーは見つかりませんでした。'})
        $net=@(Get-NetAdapter -ErrorAction SilentlyContinue|Where-Object Status -eq 'Up');Add-InfoCard 'ネットワーク' $(if($net.Count){"接続中 $($net.Count) 個"}else{'接続なし'}) (($net|ForEach-Object{$_.Name})-join', ')
        $reasons=@(Get-PendingRestartReasons);Add-InfoCard '再起動待ち' $(if($reasons.Count){'あり ⚠'}else{'なし ✓'}) $(if($reasons.Count){($reasons|ForEach-Object{'・'+$_})-join"`n"}else{'Windowsが要求する再起動待ちは検出されませんでした。'})
        try{$mp=Get-MpComputerStatus -ErrorAction Stop;Add-InfoCard 'Microsoft Defender' $(if($mp.AntivirusEnabled){'有効 ✓'}else{'無効 / 他製品の可能性'}) "リアルタイム保護: $($mp.RealTimeProtectionEnabled)"}catch{Add-InfoCard 'Microsoft Defender' '状態を取得できませんでした'}
        $btn=New-Object Windows.Controls.Button;$btn.Content='デバイス マネージャーを開く';$btn.HorizontalAlignment='Left';$btn.Add_Click({Start-Process devmgmt.msc});$SpecialPanel.Children.Add($btn)|Out-Null
        $SummaryText.Text='チェック完了';$DetailRisk.Text='安全';$RiskBorder.Background=Brush '#E8F7EF';$DetailAdmin.Text='不要（取得できる範囲）';$DetailRestart.Text='変更しません';$DetailTitle.Text='PCチェック';$DetailBody.Text='ドライバー未適用、ディスク空き、ネットワーク、再起動待ちの理由、Defenderの基本状態を確認します。'
    }finally{$window.Cursor=[Windows.Input.Cursors]::Arrow;$StatusText.Text='PCチェックが完了しました。'}
}
function Save-LastSnapshot{$o=[ordered]@{app='WinSukkiri';version='1.1.1';created=(Get-Date).ToString('s');settings=[ordered]@{}};foreach($s in $settings){if($toggleMap[$s.Id].IsEnabled){$o.settings[$s.Id]=[bool]$initialMap[$s.Id]}};$o|ConvertTo-Json -Depth 6|Set-Content $lastSnapshotPath -Encoding UTF8}
function Restore-LastSnapshot{if(!(Test-Path $lastSnapshotPath)){[System.Windows.MessageBox]::Show('まだ直前の変更は保存されていません。',$appName)|Out-Null;return};if([System.Windows.MessageBox]::Show('直前の変更前の状態へ戻します。よろしいですか？',$appName,'YesNo','Question') -ne 'Yes'){return};$o=Get-Content $lastSnapshotPath -Raw -Encoding UTF8|ConvertFrom-Json;$ok=0;$err=@();foreach($s in $settings){$p=$o.settings.PSObject.Properties[$s.Id];if($null -eq $p){continue};$want=[bool]$p.Value;try{$now=[bool](& $s.IsApplied);if($want -ne $now){if($want){&$s.Apply}else{&$s.Revert};$ok++}}catch{$err+="$($s.Title): $($_.Exception.Message)"}};Reload-State;if($err.Count){[System.Windows.MessageBox]::Show("復元: $ok 件`n失敗: $($err.Count) 件`n`n"+($err-join"`n"),$appName,'OK','Warning')|Out-Null}else{[System.Windows.MessageBox]::Show("直前の状態へ戻しました。`n復元: $ok 件",$appName)|Out-Null}}

function Prompt-RestartExplorerIfNeeded {
    $reasons=@()
    if($script:ShortcutSuffixChanged){$reasons+='ショートカット名'}
    if($script:ClassicContextMenuChanged){$reasons+='右クリックメニュー'}
    if($script:FileExtChanged){$reasons+='ファイル名の拡張子'}
    if($reasons.Count -eq 0){return}

    $script:ShortcutSuffixChanged=$false
    $script:ClassicContextMenuChanged=$false
    $script:FileExtChanged=$false
    $reasonText=($reasons -join '・')
    $r=[System.Windows.MessageBox]::Show(
        "$reasonText の設定を確実に反映するため、Explorerを再起動しますか？`n`n［はい］: Explorerを再起動します。`n［いいえ］: 今は再起動しません。",
        $appName,'YesNo','Question')
    if($r -eq 'Yes'){
        try{
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 700
            Start-Process explorer.exe
            $StatusText.Text='Explorerを再起動しました。'
        }catch{
            [System.Windows.MessageBox]::Show("Explorerの再起動に失敗しました。`n$($_.Exception.Message)",$appName,'OK','Warning')|Out-Null
        }
    }
}

function Apply-Changes{$changes=@();foreach($s in $settings){$t=$toggleMap[$s.Id];if(!$t.IsEnabled -or $cardMap[$s.Id].Visibility -ne 'Visible'){continue};$want=[bool]$t.IsChecked;$was=[bool]$initialMap[$s.Id];if($want -ne $was){$changes+=[pscustomobject]@{Setting=$s;Want=$want}}};if(!$changes){[System.Windows.MessageBox]::Show('このカテゴリに変更する項目はありません。',$appName)|Out-Null;return};$preview=($changes|ForEach-Object{"・$($_.Setting.Title) → $(if($_.Want){'すっきり状態にする'}else{'標準寄りに戻す'})"})-join"`n";$msg="選択した設定をWindowsに適用します。`n`n変更する項目: $($changes.Count) 件`n`n$preview`n`nよろしいですか？";if([System.Windows.MessageBox]::Show($msg,$appName,'YesNo','Question') -ne 'Yes'){$StatusText.Text='変更をキャンセルしました。';return};Save-LastSnapshot;$StatusText.Text='設定を変更しています...';$window.Cursor=[Windows.Input.Cursors]::Wait;$ok=@();$err=@();try{foreach($c in $changes){try{if($c.Want){&$c.Setting.Apply}else{&$c.Setting.Revert};$ok+=$c.Setting.Title}catch{$err+="$($c.Setting.Title): $($_.Exception.Message)"}}}finally{$window.Cursor=[Windows.Input.Cursors]::Arrow};Reload-State;$text="変更しました: $($ok.Count) 項目";if($ok.Count){$text+="`n"+(($ok|ForEach-Object{"✓ $_"})-join"`n")};if($err.Count){$text+="`n`n変更できませんでした: $($err.Count) 項目`n"+(($err|ForEach-Object{"⚠ $_"})-join"`n")};[System.Windows.MessageBox]::Show($text,$appName,'OK',$(if($err.Count){'Warning'}else{'Information'}))|Out-Null;$StatusText.Text="成功 $($ok.Count) / 失敗 $($err.Count)"}
# events
(W 'NavHome').Add_Click({Show-Home});(W 'NavSimple').Add_Click({Show-SettingsCategory 'シンプル化'});(W 'NavDesktop').Add_Click({Show-SettingsCategory 'デスクトップ'});(W 'NavFolders').Add_Click({Show-UserFolders});(W 'NavExplorer').Add_Click({Show-SettingsCategory 'エクスプローラー'});(W 'NavStartup').Add_Click({Show-Startup});(W 'NavCheck').Add_Click({Show-PCCheck});(W 'NavPrivacy').Add_Click({Show-SettingsCategory 'プライバシー'});(W 'NavPerf').Add_Click({Show-SettingsCategory 'パフォーマンス'});(W 'NavAdvanced').Add_Click({Show-SettingsCategory '詳細設定'});$BtnApply.Add_Click({if($script:currentPage -eq 'Startup'){Apply-StartupChanges}else{Apply-Changes;Prompt-RestartExplorerIfNeeded}});(W 'BtnReload').Add_Click({if($script:currentPage -eq 'Startup'){Show-Startup}else{Reload-State;if($script:currentPage -eq 'Settings' -and $script:currentSettingsCategory){Show-SettingsCategory $script:currentSettingsCategory}}});(W 'BtnRestoreLast').Add_Click({Restore-LastSnapshot});$BtnRecommended.Add_Click({foreach($s in $settings|Where-Object Cat -eq 'シンプル化'){if($s.Recommended -and $toggleMap[$s.Id].IsEnabled){$toggleMap[$s.Id].IsChecked=$true}};$StatusText.Text='おすすめ項目を選択しました。まだ適用していません。'});(W 'BtnExplorerRestart').Add_Click({try{Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue;Start-Sleep -Milliseconds 500;Start-Process explorer.exe;$StatusText.Text='Explorerを再起動しました。'}catch{[System.Windows.MessageBox]::Show($_.Exception.Message,$appName)|Out-Null}});$BtnNetplwiz.Add_Click({
    $msg="Windows標準のユーザー アカウント設定（netplwiz）を開きます。`n`nWinすっきりはパスワードやPINを取得・保存・変更しません。`n入力する認証情報や自動ログイン設定の内容はWindows側で管理されます。`n`n続けますか？"
    if([System.Windows.MessageBox]::Show($msg,$appName,'YesNo','Information') -eq 'Yes'){Start-Process netplwiz.exe}
});$BtnOneDriveStop.Add_Click({
    $od=Get-Process -Name OneDrive -ErrorAction SilentlyContinue
    if(-not $od){[System.Windows.MessageBox]::Show('OneDriveは現在起動していません。',$appName,'OK','Information')|Out-Null;return}
    if([System.Windows.MessageBox]::Show('現在起動しているOneDriveを終了します。`n`n自動起動設定や同期設定、ファイルは変更しません。`nよろしいですか？',$appName,'YesNo','Question') -ne 'Yes'){return}
    try{Stop-Process -Name OneDrive -ErrorAction Stop;$StatusText.Text='OneDriveを終了しました。';[System.Windows.MessageBox]::Show('OneDriveを終了しました。',$appName,'OK','Information')|Out-Null}catch{[System.Windows.MessageBox]::Show("OneDriveを終了できませんでした。`n$($_.Exception.Message)",$appName,'OK','Warning')|Out-Null}
});$BtnSignInOptions.Add_Click({Open-SignInOptions});(W 'BtnExport').Add_Click({$dlg=New-Object Microsoft.Win32.SaveFileDialog;$dlg.Filter='Winすっきり設定 (*.json)|*.json';$dlg.FileName='WinSukkiri-my-settings.json';if($dlg.ShowDialog()){$o=[ordered]@{app='WinSukkiri';version='1.1.1';created=(Get-Date).ToString('s');settings=[ordered]@{}};foreach($s in $settings){if($toggleMap[$s.Id].IsEnabled){$o.settings[$s.Id]=[bool]$toggleMap[$s.Id].IsChecked}};$o|ConvertTo-Json -Depth 6|Set-Content $dlg.FileName -Encoding UTF8;$StatusText.Text='マイ設定を保存しました。'}});(W 'BtnImport').Add_Click({$dlg=New-Object Microsoft.Win32.OpenFileDialog;$dlg.Filter='Winすっきり設定 (*.json)|*.json';if($dlg.ShowDialog()){try{$o=Get-Content $dlg.FileName -Raw -Encoding UTF8|ConvertFrom-Json;foreach($s in $settings){$p=$o.settings.PSObject.Properties[$s.Id];if($null -ne $p -and $toggleMap[$s.Id].IsEnabled){$toggleMap[$s.Id].IsChecked=[bool]$p.Value}};$StatusText.Text='マイ設定を読み込みました。カテゴリごとに確認して適用してください。'}catch{[System.Windows.MessageBox]::Show('設定ファイルを読み込めませんでした。',$appName)|Out-Null}}})
try{Reload-State;Show-Home;$window.ShowDialog()|Out-Null}finally{if($mutex){$mutex.ReleaseMutex()|Out-Null;$mutex.Dispose()}}