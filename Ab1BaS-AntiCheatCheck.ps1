<#
  Ab1BaS AntiCheatCheck v1.0
  Диагностика античитов: FACEIT, Riot Vanguard, Easy Anti-Cheat, BattlEye.

  Скрипт ТОЛЬКО ЧИТАЕТ данные и ничего не меняет в системе.
  Права администратора НЕ нужны и НЕ запрашиваются.

  Что он смотрит:
   - версию Windows и последние обновления;
   - режим загрузки (UEFI или Legacy), Secure Boot, наличие TPM 2.0;
   - изоляцию ядра (VBS, HVCI) и виртуализацию;
   - установлены ли и запущены ли службы античитов;
   - программы, которые часто конфликтуют с античитами;
   - ошибки античитов и заблокированные драйверы в журналах Windows за 14 дней.

  Чего он НЕ делает:
   - ничего не скачивает и не устанавливает;
   - не меняет настройки Windows, BIOS, реестра, игр и античитов;
   - никуда не отправляет данные: отчет сохраняется на рабочий стол и копируется в буфер обмена;
   - не собирает пароли, имя ПК, имя пользователя, MAC-адреса и IP.

  Запуск: правой кнопкой по файлу -> "Выполнить с помощью PowerShell",
  или в окне PowerShell: powershell -ExecutionPolicy Bypass -File "$HOME\Downloads\Ab1BaS-AntiCheatCheck.ps1"

  Автор: Ab1BaS. Перепродажа запрещена.
#>

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$Version = '1.0'

function Hide-Private([string]$s) {
    if (-not $s) { return $s }
    $s = $s -replace '(?i)([a-z]:\\users\\)[^\\\s"]+', '$1<user>'
    if ($env:COMPUTERNAME -and $env:COMPUTERNAME.Length -ge 4) { $s = $s -replace [regex]::Escape($env:COMPUTERNAME), '<pc>' }
    if ($env:USERNAME -and $env:USERNAME.Length -ge 4) { $s = $s -replace [regex]::Escape($env:USERNAME), '<user>' }
    return ($s -replace '([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}', 'XX-XX-XX-XX-XX-XX')
}

function Get-Reg($path, $name) {
    try { return (Get-ItemProperty -Path $path -Name $name -ErrorAction Stop).$name } catch { return $null }
}

Clear-Host
Write-Host ''
Write-Host "  Ab1BaS AntiCheatCheck v$Version" -ForegroundColor Cyan
Write-Host '  Проверка античитов. Скрипт только читает данные, права администратора не нужны.' -ForegroundColor Gray
Write-Host ''
Write-Host '  Собираю данные, это займет до минуты...' -ForegroundColor Yellow

$os = Get-CimInstance Win32_OperatingSystem
$cv = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$disp = Get-Reg $cv 'DisplayVersion'
$ubr = Get-Reg $cv 'UBR'
$build = [int]$os.BuildNumber
$isWin11 = $build -ge 22000
$osLine = "$($os.Caption) $disp, сборка $build.$ubr"
$hf = @(Get-HotFix | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending | Select-Object -First 3 | ForEach-Object { "$($_.HotFixID) $($_.InstalledOn.ToString('yyyy-MM-dd'))" })
$hfLine = if ($hf.Count) { $hf -join ', ' } else { 'не удалось получить' }

$fw = Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control' 'PEFirmwareType'
$fwLine = switch ($fw) { 1 { 'Legacy BIOS (CSM)' } 2 { 'UEFI' } default { 'н/д' } }

$sb = $null
try { $sb = Confirm-SecureBootUEFI -ErrorAction Stop } catch {}
if ($null -eq $sb) {
    $v = Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' 'UEFISecureBootEnabled'
    if ($null -ne $v) { $sb = ($v -eq 1) }
}
$sbLine = if ($sb -eq $true) { 'ВКЛ' } elseif ($sb -eq $false) { 'ВЫКЛ' } else { 'н/д (не поддерживается или Legacy)' }

$tpmDev = @(Get-PnpDevice -PresentOnly | Where-Object { $_.FriendlyName -match 'Trusted Platform Module|TPM' })
$tpmLine = if ($tpmDev.Count) { ($tpmDev | ForEach-Object { "$($_.FriendlyName) [$($_.Status)]" }) -join ', ' } else { 'НЕ НАЙДЕН (выключен в BIOS или отсутствует)' }

$dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard
$vbsMap = @{ 0 = 'выкл'; 1 = 'включена, но не работает'; 2 = 'работает' }
$vbsLine = 'н/д'
$hvciLine = 'н/д'
if ($dg) {
    $vbsLine = $vbsMap[[int]$dg.VirtualizationBasedSecurityStatus]
    $hvciLine = if (@($dg.SecurityServicesRunning) -contains 2) { 'работает' } elseif (@($dg.SecurityServicesConfigured) -contains 2) { 'настроена, но не работает' } else { 'выкл' }
}
$hvciReg = Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled'
if ($null -ne $hvciReg) { $hvciLine += " (параметр Целостность памяти: $hvciReg)" }

$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$cs = Get-CimInstance Win32_ComputerSystem
$virtLine = "виртуализация в BIOS: $(if ($cpu.VirtualizationFirmwareEnabled) { 'ВКЛ' } else { 'выкл или скрыта гипервизором' }), гипервизор Windows: $(if ($cs.HypervisorPresent) { 'работает' } else { 'нет' })"
$vdb = Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config' 'VulnerableDriverBlocklistEnable'
$vdbLine = if ($null -eq $vdb) { 'по умолчанию' } elseif ($vdb -eq 1) { 'ВКЛ' } else { 'ВЫКЛ' }

$acNames = 'vgc', 'vgk', 'FACEIT', 'FACEITService', 'EasyAntiCheat', 'EasyAntiCheat_EOS', 'EasyAntiCheat_EOSSys', 'BEService', 'BEDaisy'
$acParts = @()
foreach ($n in $acNames) {
    $s = Get-Service -Name $n
    if ($s) { $acParts += "$n=$($s.Status)/$($s.StartType)"; continue }
    $d = Get-CimInstance Win32_SystemDriver -Filter "Name='$n'"
    if ($d) { $acParts += "$n(драйвер)=$($d.State)/$($d.StartMode)" }
}
$acLine = if ($acParts.Count) { $acParts -join '; ' } else { 'ни один античит не найден' }

$conflictRe = 'MSI Afterburner|RivaTuner|Cheat Engine|Process Hacker|System Informer|VirtualBox|VMware|BlueStacks|LDPlayer|Nox|MEmu|Razer Synapse|iCUE|Armoury Crate|G HUB|FanControl|OpenRGB|SignalRGB|ThrottleStop|HWiNFO|AIDA64|CPU-Z|Wallpaper Engine|NZXT CAM|MSI Center|Dragon Center|EasyTune|AI Suite|Hamachi|Radmin VPN|Cloudflare WARP|Proton VPN|NordVPN|Avast|AVG|Kaspersky|ESET|Dr\.Web|360 Total|McAfee|Norton|Bitdefender'
$uninst = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
$apps = @(Get-ItemProperty $uninst | Where-Object { $_.DisplayName -match $conflictRe } | ForEach-Object { $_.DisplayName.Trim() } | Sort-Object -Unique)
$appsLine = if ($apps.Count) { ($apps | Select-Object -First 15) -join ', ' } else { 'нет' }
$runRe = 'MSIAfterburner|RTSS|cheatengine|ProcessHacker|SystemInformer|VBoxSVC|vmware|HD-Player|dnplayer|RazerCentral|iCUE|ArmouryCrate|lghub|FanControl|OpenRGB|ThrottleStop|HWiNFO|aida64|wallpaper32|wallpaper64|NZXT|MSI.CentralServer'
$runs = @(Get-Process | Where-Object { $_.ProcessName -match $runRe } | ForEach-Object { $_.ProcessName } | Sort-Object -Unique)
$runLine = if ($runs.Count) { $runs -join ', ' } else { 'нет' }

$since = (Get-Date).AddDays(-14)
$acRe = 'vgk|vgc|Vanguard|FACEIT|EasyAntiCheat|BEService|BEDaisy|BattlEye'
$evParts = @()
foreach ($log in 'Application', 'System') {
    Get-WinEvent -FilterHashtable @{ LogName = $log; Level = 1, 2, 3; StartTime = $since } -MaxEvents 3000 |
        Where-Object { $_.ProviderName -match $acRe -or $_.Message -match $acRe } |
        Group-Object { "$($_.ProviderName) id$($_.Id)" } | Sort-Object Count -Descending | Select-Object -First 6 |
        ForEach-Object {
            $m = ($_.Group[0].Message -replace '\s+', ' ')
            if ($m.Length -gt 160) { $m = $m.Substring(0, 160) }
            $evParts += "[$log] $($_.Name) x$($_.Count), последний $($_.Group[0].TimeCreated.ToString('MM-dd HH:mm')): $m"
        }
}
$evLine = if ($evParts.Count) { $evParts -join ' | ' } else { 'ошибок античитов в журналах нет' }

$ciParts = @()
$ciLine = 'нет'
try {
    $ciEv = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-CodeIntegrity/Operational'; Id = 3033, 3063, 3077, 3089; StartTime = $since } -MaxEvents 500 -ErrorAction Stop)
    $ciParts = @($ciEv | ForEach-Object { if ($_.Message -match '([\w\-\.]+\.(sys|dll|exe))') { $Matches[1] } } | Group-Object | Sort-Object Count -Descending | Select-Object -First 8 |
        ForEach-Object { "$($_.Name) x$($_.Count)" })
    if ($ciParts.Count) { $ciLine = $ciParts -join ', ' }
} catch {
    if ($_.Exception.Message -notmatch 'No events|не найдено|Не найдено|не удается найти') { $ciLine = 'журнал недоступен без прав администратора' }
}

$gpu = @(Get-CimInstance Win32_VideoController | ForEach-Object { "$($_.Name) драйвер $($_.DriverVersion)" }) -join '; '

$verdict = @()
if (-not $isWin11) { $verdict += 'Windows 10: FACEIT и часть игр требуют Windows 11' }
if ($fw -eq 1) { $verdict += 'Legacy BIOS: Secure Boot невозможен без перехода на UEFI' }
if ($sb -eq $false) { $verdict += 'Secure Boot выключен' }
if (-not $tpmDev.Count) { $verdict += 'TPM не виден в системе' }
if ($ciParts.Count) { $verdict += 'Windows блокирует драйверы (см. строку Заблокированные драйверы)' }
if ($apps.Count -or $runs.Count) { $verdict += 'есть программы, которые часто конфликтуют с античитами' }
$verdictLine = if ($verdict.Count) { $verdict -join '; ' } else { 'базовые требования выполнены, смотрим ошибки и коды из игры' }

$report = @"
=== Ab1BaS AntiCheatCheck v$Version ===
Дата: $((Get-Date).ToString('yyyy-MM-dd HH:mm'))
Система: $osLine
Последние обновления: $hfLine
Загрузка: $fwLine | Secure Boot: $sbLine
TPM: $tpmLine
Изоляция ядра: VBS $vbsLine, HVCI $hvciLine
Виртуализация: $virtLine
Блок уязвимых драйверов: $vdbLine
Видеокарта: $gpu
Античиты: $acLine
Программы-конфликты (установлены): $appsLine
Программы-конфликты (запущены): $runLine
Заблокированные драйверы за 14 дней: $ciLine
Ошибки античитов за 14 дней: $evLine
Предварительно: $verdictLine
"@

$report = Hide-Private $report

$file = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Ab1BaS-AntiCheatCheck.txt'
$report | Out-File -FilePath $file -Encoding utf8
$copied = $false
try { Set-Clipboard -Value $report; $copied = $true } catch {}

Write-Host ''
Write-Host $report
Write-Host ''
if ($copied) { Write-Host '  Готово. Отчет уже скопирован: вставь его (Ctrl+V) в чат FunPay и напиши точный текст ошибки из игры.' -ForegroundColor Green }
else { Write-Host '  Готово. Скопируй отчет из файла на рабочем столе и вставь в чат FunPay.' -ForegroundColor Green }
Write-Host '  Копия отчета: файл Ab1BaS-AntiCheatCheck.txt на рабочем столе.' -ForegroundColor Gray
Write-Host ''
Read-Host '  Нажми Enter, чтобы закрыть'
