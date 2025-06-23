# CombinedScript.ps1
#---------------------------------------------------------------
# Setzt eine statische IP, aktiviert Office per MAK online und stellt die IP-Konfiguration wieder her
# Usage: powershell.exe -ExecutionPolicy Bypass -File CombinedScript.ps1 -OfficeKey YOUR-KEY-HERE


function Assert-Admin {
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
        Write-Error 'Dieses Skript muss mit Administrator-Rechten ausgeführt werden!'
        exit 1
    }
}
# 0) Prüfungsrechte
Assert-Admin

# --- Teil 1: Statische IP setzen mit Backup ---
Write-Host '## Teil 1: Statische IP setzen und Backup anlegen' -ForegroundColor Cyan
$netCfg = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway.NextHop } |
    Where-Object { -not (Get-NetAdapter -InterfaceIndex $_.InterfaceIndex).Virtual } |
    Select-Object -First 1
if (-not $netCfg) {
    $netCfg = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and -not $_.Virtual } | Select-Object -First 1
    Write-Host 'Kein Gateway-Adapter gefunden, verwende ersten physischen Up-Adapter' -ForegroundColor Yellow
} else {
    Write-Host 'Gefundener physischer Adapter via DefaultGateway' -ForegroundColor Green
}
$ifaceIdx = $netCfg.InterfaceIndex
$adapter  = Get-NetAdapter -InterfaceIndex $ifaceIdx
Write-Host "Adapter: $($adapter.Name) (Index $ifaceIdx)"

# Backup aktueller Konfiguration
$guid      = $adapter.InterfaceGuid
$src       = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
$dstParent = 'HKCU:\Software\NetIPBackup'
$dst       = "$dstParent\$guid"
if (-not (Test-Path $dstParent)) { New-Item -Path $dstParent -ItemType Directory | Out-Null }
if (-not (Test-Path $dst))       { New-Item -Path $dst -ItemType Directory | Out-Null }
$props = 'EnableDHCP','IPAddress','SubnetMask','DefaultGateway','NameServer'
foreach ($p in $props) {
    $v = Get-ItemPropertyValue -Path $src -Name $p -ErrorAction SilentlyContinue
    if ($null -ne $v) { Set-ItemProperty -Path $dst -Name $p -Value $v }
}
Write-Host 'Backup abgeschlossen.'

# Statische Konfiguration anwenden
$staticBase = '192.168.116'
$lastOctets = 1..3
$dnsServers = '192.168.116.12','192.168.116.23'
Set-NetIPInterface -InterfaceIndex $ifaceIdx -Dhcp Disabled
foreach ($store in 'ActiveStore','PersistentStore') {
    Get-NetIPAddress -InterfaceIndex $ifaceIdx -AddressFamily IPv4 -PolicyStore $store | Remove-NetIPAddress -Confirm:$false
    Get-NetRoute     -InterfaceIndex $ifaceIdx -DestinationPrefix '0.0.0.0/0' -PolicyStore $store | Remove-NetRoute     -Confirm:$false
}
$chosen = $null
foreach ($o in (Get-Random -InputObject $lastOctets -Count $lastOctets.Length)) {
    $cand = "$staticBase.$o"
    $alive = Test-NetConnection -ComputerName $cand -Port 443 -InformationLevel Quiet -ErrorAction SilentlyContinue
    if (-not $alive) { $chosen = $cand; break }
}
if (-not $chosen) { Write-Error 'Keine freie IP gefunden!'; exit 1 }
New-NetIPAddress -InterfaceIndex $ifaceIdx -IPAddress $chosen -PrefixLength 23 -DefaultGateway "$staticBase.8"
Set-DnsClientServerAddress -InterfaceIndex $ifaceIdx -ServerAddresses $dnsServers
Write-Host "Statische IP $chosen/23 gesetzt."
Disable-NetAdapter -Name $adapter.Name -Confirm:$false; Start-Sleep 2; Enable-NetAdapter -Name $adapter.Name -Confirm:$false

# --- Teil 2: Office Aktivierung ---
Write-Host '## Teil 2: Office aktivieren' -ForegroundColor Cyan
# Suche ospp.vbs im Office-Installationsverzeichnis
$paths = @(
    "$env:ProgramFiles\Microsoft Office",
    "$env:ProgramFiles(x86)\Microsoft Office"
)
$osppFile = $paths | ForEach-Object { Get-ChildItem -Path $_ -Recurse -Filter ospp.vbs -ErrorAction SilentlyContinue } | Select-Object -First 1
if (-not $osppFile) {
    Write-Error 'ospp.vbs nicht gefunden. Bitte Pfad prüfen!'; exit 1
}
$officePath = $osppFile.DirectoryName
Write-Host "Gefundener Office-Pfad: $officePath"
Push-Location $officePath

# Warte auf Erreichbarkeit des Aktivierungs-Servers (Port 443) mit Timeout 60 Sekunden
Write-Host 'Warte auf TCP Port 443 von activation.sls.microsoft.com (max. 60s)...' -NoNewline
$startTime = Get-Date
do {
    $result = Test-NetConnection -ComputerName 'activation.sls.microsoft.com' -Port 443
    if ($result.TcpTestSucceeded) {
        Write-Host ' OK'
        break
    }
    Start-Sleep -Seconds 5
} while ((Get-Date) - $startTime).TotalSeconds -lt 60
if (-not $result.TcpTestSucceeded) {
    Write-Error 'Timeout: Aktivierungs-Server nicht innerhalb von 60 Sekunden erreichbar.'
    exit 1
}



# Online-Aktivierung durchführen
Write-Host 'Starte Online-Aktivierung' -ForegroundColor Cyan
cscript ospp.vbs /act
cscript ospp.vbs /dstatus
Pop-Location

# --- Teil 3: IP Restore aus Backup ---
Write-Host '## Teil 3: IP-Restore aus Backup' -ForegroundColor Cyan
$backupRoot = 'HKCU:\Software\NetIPBackup'
if (-not (Test-Path $backupRoot)) { Write-Warning 'Kein IP-Backup gefunden.'; exit 0 }
Get-ChildItem -Path $backupRoot | ForEach-Object {
    $g = $_.PSChildName; $dst = "$backupRoot\$g"
    Write-Host "Restore GUID $g"
    $adapter = Get-NetAdapter | Where-Object InterfaceGuid -EQ $g
    if (-not $adapter) { Write-Warning "Adapter $g nicht gefunden"; return }
    $idx = $adapter.InterfaceIndex
    $dhcp = Get-ItemPropertyValue -Path $dst -Name EnableDHCP -ErrorAction SilentlyContinue
    if ($dhcp) {
        Set-NetIPInterface -InterfaceIndex $idx -Dhcp Enabled
        Set-DnsClientServerAddress -InterfaceIndex $idx -ResetServerAddresses
    } else {
        $ips  = Get-ItemPropertyValue -Path $dst -Name IPAddress
        $mask = Get-ItemPropertyValue -Path $dst -Name SubnetMask
        $gw   = Get-ItemPropertyValue -Path $dst -Name DefaultGateway
        $dns  = Get-ItemPropertyValue -Path $dst -Name NameServer
        foreach ($store in 'ActiveStore','PersistentStore') {
            Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 -PolicyStore $store | Remove-NetIPAddress -Confirm:$false
            Get-NetRoute     -InterfaceIndex $idx -DestinationPrefix '0.0.0.0/0' -PolicyStore $store | Remove-NetRoute     -Confirm:$false
        }
        function Get-PrefixLength { param($m); return ((($m -split '\.') | ForEach-Object { [Convert]::ToString($_,2).PadLeft(8,'0') }) -join '') -split '' | Where-Object { $_ -eq '1' } | Measure-Object | Select-Object -ExpandProperty Count }
        $pre = Get-PrefixLength -m $mask
        foreach ($ip in @($ips)) { New-NetIPAddress -InterfaceIndex $idx -IPAddress $ip -PrefixLength $pre -DefaultGateway $gw }
        if ($dns) { Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses @($dns) }
    }
    Disable-NetAdapter -Name $adapter.Name -Confirm:$false; Start-Sleep 2; Enable-NetAdapter -Name $adapter.Name -Confirm:$false
    Write-Host "Restore $($adapter.Name) DONEn"
}
Write-Host 'Alle IP-Restores abgeschlossen.'