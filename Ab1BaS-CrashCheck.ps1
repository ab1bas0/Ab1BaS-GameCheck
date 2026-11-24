<#
  Ab1BaS CrashCheck v1.0
  Поиск причины вылетов игр, зависаний и синих экранов по журналам Windows.

  Скрипт ТОЛЬКО ЧИТАЕТ данные и ничего не меняет в системе.
  Права администратора НЕ нужны и НЕ запрашиваются.

  Что он смотрит:
   - вылеты программ за последние 14 дней: какая игра упала, на каком модуле и с каким кодом;
   - сбросы видеодрайвера, синие экраны, внезапные перезагрузки, аппаратные ошибки (WHEA), ошибки диска;
   - видеокарту и версию драйвера, память (частота, планки), файл подкачки, свободное место;
   - установленные библиотеки Visual C++ и .NET;
   - запущенные оверлеи и программы, которые часто роняют игры.

  Чего он НЕ делает:
   - ничего не скачивает и не устанавливает;
   - не меняет настройки Windows, драйверов, реестра и игр;
   - никуда не отправляет данные: отчет сохраняется на рабочий стол и копируется в буфер обмена;
   - не собирает пароли, имя ПК, имя пользователя, MAC-адреса и IP. Пути вида C:\Users\Имя заменяются на <user>.

  Запуск: правой кнопкой по файлу -> "Выполнить с помощью PowerShell",
  или в окне PowerShell: powershell -ExecutionPolicy Bypass -File "$HOME\Downloads\Ab1BaS-CrashCheck.ps1"

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

function Short([string]$s, [int]$n) {
    if (-not $s) { return '' }
    $s = ($s -replace '\s+', ' ').Trim()
    if ($s.Length -gt $n) { $s = $s.Substring(0, $n) }
    return $s
}

Clear-Host
Write-Host ''
Write-Host "  Ab1BaS CrashCheck v$Version" -ForegroundColor Cyan
Write-Host '  Поиск причины вылетов. Скрипт только читает данные, права администратора не нужны.' -ForegroundColor Gray
Write-Host ''
$game = Read-Host '  Напиши название игры или ее .exe (например cs2, FortniteClient, GTA5) и нажми Enter. Не знаешь, просто Enter'
$game = ($game -replace '\.exe$', '').Trim()
Write-Host ''
Write-Host '  Читаю журналы Windows за 14 дней, это займет до минуты...' -ForegroundColor Yellow

$since = (Get-Date).AddDays(-14)

$app = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000, 1002; StartTime = $since } -MaxEvents 2000)
$crashes = @($app | ForEach-Object {
    $p = $_.Properties
    [pscustomobject]@{
        Kind   = if ($_.Id -eq 1002) { 'зависание' } else { 'вылет' }
        App    = [string]$p[0].Value
        Ver    = [string]$p[1].Value
        Module = if ($_.Id -eq 1000) { [string]$p[3].Value } else { '' }
        Code   = if ($_.Id -eq 1000) { [string]$p[6].Value } else { '' }
        Time   = $_.TimeCreated
    }
})
$crashGroups = @($crashes | Group-Object { "$($_.Kind)|$($_.App)|$($_.Module)|$($_.Code)" } | Sort-Object Count -Descending)
if ($game) { $focus = @($crashGroups | Where-Object { $_.Name -match [regex]::Escape($game) }) } else { $focus = @() }
$showGroups = @($focus + ($crashGroups | Where-Object { $focus -notcontains $_ }) | Select-Object -First 10)
$crashLines = @($showGroups | ForEach-Object {
    $g = $_.Group[0]
    $last = ($_.Group | Sort-Object Time -Descending | Select-Object -First 1).Time.ToString('MM-dd HH:mm')
    $mod = if ($g.Module) { " модуль $($g.Module)" } else { '' }
    $code = if ($g.Code) { " код $($g.Code)" } else { '' }
    "$($g.Kind) $($g.App) v$($g.Ver)$mod$code x$($_.Count) (последний $last)"
})
$crashLine = if ($crashLines.Count) { $crashLines -join ' | ' } else { 'вылетов программ в журнале нет' }

$wer = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Windows Error Reporting'; Id = 1001; StartTime = $since } -MaxEvents 1000 |
    ForEach-Object {
        $p = $_.Properties
        $ev = [string]$p[2].Value
        $p1 = [string]$p[5].Value
        $p3 = [string]$p[7].Value
        if ($ev -match 'APPCRASH|BEX|LiveKernelEvent|AppHang|MoAppCrash|CLR20r3|BlueScreen') { "$ev $p1 $p3".Trim() }
    } | Group-Object | Sort-Object Count -Descending | Select-Object -First 8 | ForEach-Object { "$($_.Name) x$($_.Count)" })
$werLine = if ($wer.Count) { $wer -join ' | ' } else { 'нет' }

$sysIds = 41, 1001, 6008, 4101, 13, 153, 14, 17, 18, 19, 20, 47, 7, 51, 129, 157
$sys = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = $sysIds; StartTime = $since } -MaxEvents 3000)
$sysParts = @()
$k41 = @($sys | Where-Object { $_.Id -eq 41 -and $_.ProviderName -match 'Kernel-Power' })
if ($k41.Count) { $sysParts += "внезапные перезагрузки/выключения (Kernel-Power 41) x$($k41.Count)" }
$bsod = @($sys | Where-Object { $_.Id -eq 1001 -and $_.ProviderName -match 'WER-SystemErrorReporting|BugCheck' })
if ($bsod.Count) {
    $codes = @($bsod | ForEach-Object { if ($_.Message -match '(0x[0-9a-fA-F]{8})') { $Matches[1] } } | Group-Object | ForEach-Object { "$($_.Name) x$($_.Count)" })
    $sysParts += "СИНИЕ ЭКРАНЫ x$($bsod.Count): $($codes -join ', ')"
}
$tdr = @($sys | Where-Object { ($_.Id -eq 4101) -or ($_.ProviderName -match 'nvlddmkm|amdkmdag|amdwddmg|igfx' -and $_.Id -in 13, 14, 153) })
if ($tdr.Count) { $sysParts += "сбросы видеодрайвера (TDR, драйвер перестал отвечать) x$($tdr.Count), источник $(@($tdr | ForEach-Object { $_.ProviderName } | Sort-Object -Unique) -join '/')" }
$whea = @($sys | Where-Object { $_.ProviderName -match 'WHEA' })
if ($whea.Count) { $sysParts += "аппаратные ошибки WHEA x$($whea.Count) (часто разгон, XMP или нестабильное железо): $(Short ($whea[0].Message) 120)" }
$disk = @($sys | Where-Object { $_.ProviderName -match '^disk$|stornvme|storahci|Ntfs' -and $_.Id -in 7, 51, 129, 153, 157 })
if ($disk.Count) { $sysParts += "ошибки диска x$($disk.Count) ($(@($disk | ForEach-Object { "$($_.ProviderName) $($_.Id)" } | Sort-Object -Unique) -join ', '))" }
$unexp = @($sys | Where-Object { $_.Id -eq 6008 })
if ($unexp.Count) { $sysParts += "неожиданные завершения работы (6008) x$($unexp.Count)" }
$sysLine = if ($sysParts.Count) { $sysParts -join ' | ' } else { 'синих экранов, сбросов драйвера и аппаратных ошибок нет' }

$dumpLine = 'нет доступа без прав администратора'
try {
    $dumps = @(Get-ChildItem 'C:\Windows\Minidump' -Filter *.dmp -ErrorAction Stop | Sort-Object LastWriteTime -Descending)
    $dumpLine = if ($dumps.Count) { "$($dumps.Count) шт, последний $($dumps[0].LastWriteTime.ToString('yyyy-MM-dd HH:mm'))" } else { 'нет' }
} catch {}

$os = Get-CimInstance Win32_OperatingSystem
$disp = Get-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'DisplayVersion'
$up = (Get-Date) - $os.LastBootUpTime
$osLine = "$($os.Caption) $disp, сборка $($os.BuildNumber), без перезагрузки $([int]$up.TotalHours) ч"

$cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name.Trim()
$gpus = @(Get-CimInstance Win32_VideoController | ForEach-Object {
    $dd = if ($_.DriverDate) { $_.DriverDate.ToString('yyyy-MM-dd') } else { '?' }
    "$($_.Name), драйвер $($_.DriverVersion) от $dd"
}) -join '; '

$mem = @(Get-CimInstance Win32_PhysicalMemory)
$memGb = [math]::Round(($mem | Measure-Object Capacity -Sum).Sum / 1GB, 0)
$memSticks = @($mem | ForEach-Object { "$([math]::Round($_.Capacity / 1GB, 0))ГБ $($_.ConfiguredClockSpeed)/$($_.Speed)МГц" }) -join ', '
$memLine = "$memGb ГБ, планок $($mem.Count): $memSticks (рабочая/паспортная частота)"

$cs = Get-CimInstance Win32_ComputerSystem
$pfSet = @(Get-CimInstance Win32_PageFileSetting | ForEach-Object { "$($_.Name) $($_.InitialSize)-$($_.MaximumSize)МБ" })
$pfUse = @(Get-CimInstance Win32_PageFileUsage | ForEach-Object { "$($_.Name) $($_.AllocatedBaseSize)МБ" })
$pfLine = if ($cs.AutomaticManagedPagefile) { "автоматически ($($pfUse -join ', '))" } elseif ($pfSet.Count) { "вручную: $($pfSet -join ', ')" } elseif ($pfUse.Count) { $pfUse -join ', ' } else { 'ОТКЛЮЧЕН' }

$disks = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
    "$($_.DeviceID) свободно $([math]::Round($_.FreeSpace / 1GB, 0)) из $([math]::Round($_.Size / 1GB, 0)) ГБ"
}) -join '; '
$phys = @(Get-PhysicalDisk | ForEach-Object { "$($_.FriendlyName) ($($_.MediaType), $($_.HealthStatus))" }) -join '; '

$uninst = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
$vc = @(Get-ItemProperty $uninst | Where-Object { $_.DisplayName -match 'Visual C\+\+ 20\d\d|Visual C\+\+ v14' } | ForEach-Object {
    $n = $_.DisplayName
    $y = if ($n -match '(20\d\d)') { $Matches[1] } else { '?' }
    $a = if ($n -match 'x64') { 'x64' } elseif ($n -match 'x86') { 'x86' } else { '' }
    "$y $a"
} | Sort-Object -Unique)
$vcLine = if ($vc.Count) { $vc -join ', ' } else { 'НЕ НАЙДЕНЫ' }
$net = Get-Reg 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' 'Release'
$netLine = if ($net -ge 533320) { '4.8.1' } elseif ($net -ge 528040) { '4.8' } elseif ($net) { "старше 4.8 ($net)" } else { 'н/д' }

$ovRe = 'MSIAfterburner|RTSS|Discord|NVIDIA Overlay|nvcontainer|NVIDIA Share|RadeonSoftware|GameBar|XboxGameBar|obs64|Overwolf|Medal|wallpaper32|wallpaper64|RazerCortex|iCUE|ArmouryCrate|lghub|FanControl|HWiNFO|SignalRGB|OpenRGB|Lively'
$ov = @(Get-Process | Where-Object { $_.ProcessName -match $ovRe } | ForEach-Object { $_.ProcessName } | Sort-Object -Unique)
$ovLine = if ($ov.Count) { $ov -join ', ' } else { 'нет' }

$verdict = @()
if ($bsod.Count) { $verdict += 'были синие экраны: важны коды BugCheck' }
if ($tdr.Count) { $verdict += 'видеодрайвер падает: драйвер, разгон видеокарты или питание' }
if ($whea.Count) { $verdict += 'аппаратные ошибки: подозрение на разгон, XMP или перегрев' }
if ($disk.Count) { $verdict += 'ошибки диска: проверить диск, на котором стоит игра' }
if (-not $vc.Count) { $verdict += 'нет библиотек Visual C++' }
if ($pfLine -eq 'ОТКЛЮЧЕН') { $verdict += 'файл подкачки отключен: частая причина вылетов' }
if ($focus.Count) { $verdict += "вылеты выбранной игры найдены: $($focus.Count) вид(ов)" }
elseif ($game) { $verdict += "вылетов '$game' в журнале нет: игра закрывается сама или пишет ошибку только в свой лог" }
$verdictLine = if ($verdict.Count) { $verdict -join '; ' } else { 'явных системных причин не видно, нужна ошибка из самой игры' }

$report = @"
=== Ab1BaS CrashCheck v$Version ===
Дата: $((Get-Date).ToString('yyyy-MM-dd HH:mm')) | игра: $(if ($game) { $game } else { 'не указана' })
Система: $osLine
Процессор: $cpu
Видеокарта: $gpus
Память: $memLine
Файл подкачки: $pfLine
Диски: $disks | $phys
Visual C++: $vcLine | .NET: $netLine
Запущены оверлеи/утилиты: $ovLine
Вылеты и зависания программ (14 дн): $crashLine
Отчеты об ошибках Windows: $werLine
Система (14 дн): $sysLine
Дампы синих экранов: $dumpLine
Предварительно: $verdictLine
"@

$report = Hide-Private $report

$file = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Ab1BaS-CrashCheck.txt'
$report | Out-File -FilePath $file -Encoding utf8
$copied = $false
try { Set-Clipboard -Value $report; $copied = $true } catch {}

Write-Host ''
Write-Host $report
Write-Host ''
if ($copied) { Write-Host '  Готово. Отчет уже скопирован: вставь его (Ctrl+V) в чат FunPay и напиши, когда именно вылетает игра.' -ForegroundColor Green }
else { Write-Host '  Готово. Скопируй отчет из файла на рабочем столе и вставь в чат FunPay.' -ForegroundColor Green }
Write-Host '  Копия отчета: файл Ab1BaS-CrashCheck.txt на рабочем столе.' -ForegroundColor Gray
Write-Host ''
Read-Host '  Нажми Enter, чтобы закрыть'
