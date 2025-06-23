# --- Teil 1: Statische IP setzen mit Backup ---
Write-Host '## Teil 1: Statische IP setzen und Backup anlegen' -ForegroundColor Cyan

# (Auswahl des Adapters wie gehabt …)
# … $ifaceIdx, $adapter, $guid etc.

# 1) Prüfen, ob bereits eine IP aus 192.168.116.1–3 konfiguriert ist
$staticBase  = '192.168.116'
$poolIPs     = 1..3 | ForEach-Object { "$staticBase.$_" }
$existingIPs = Get-NetIPAddress -InterfaceIndex $ifaceIdx -AddressFamily IPv4 |
               Select-Object -ExpandProperty IPAddress

if ($existingIPs | Where-Object { $poolIPs -contains $_ }) {
    Write-Host "Auf Schnittstelle $($adapter.Name) ist bereits eine IP aus 192.168.116.1–3 konfiguriert:" `
               -ForegroundColor Yellow
    $existingIPs | Where-Object { $poolIPs -contains $_ } | ForEach-Object { Write-Host "  • $_" -ForegroundColor Yellow }
    Write-Host 'Keine Änderung erforderlich – überspringe Teil 1.' -ForegroundColor Yellow
    return
}

# 2) Backup der aktuellen Konfiguration
Write-Host 'Backup der aktuellen IP-Konfiguration …' -ForegroundColor Cyan
$src       = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
$dstParent = 'HKCU:\Software\NetIPBackup'
$dst       = "$dstParent\$guid"
# (Restlicher Backup-Code wie gehabt …)

# 3) Alte Einstellungen entfernen
Write-Host 'Entferne alte IP- und Gateway-Einträge …' -ForegroundColor Cyan
Set-NetIPInterface -InterfaceIndex $ifaceIdx -Dhcp Disabled
foreach ($store in 'ActiveStore','PersistentStore') {
    Get-NetIPAddress -InterfaceIndex $ifaceIdx -AddressFamily IPv4 -PolicyStore $store | Remove-NetIPAddress -Confirm:$false
    Get-NetRoute     -InterfaceIndex $ifaceIdx -DestinationPrefix '0.0.0.0/0' -PolicyStore $store | Remove-NetRoute -Confirm:$false
}

# 4) Freie IP aus dem Pool ermitteln
$chosen = $null
foreach ($cand in (Get-Random -InputObject $poolIPs -Count $poolIPs.Length)) {
    if (-not (Test-NetConnection -ComputerName $cand -Port 443 -InformationLevel Quiet -ErrorAction SilentlyContinue)) {
        $chosen = $cand; break
    }
}
if (-not $chosen) {
    Write-Error 'Keine freie IP im Bereich .1–.3 gefunden!'
    exit 1
}

# 5) Neue statische IP setzen
New-NetIPAddress -InterfaceIndex $ifaceIdx `
                 -IPAddress $chosen `
                 -PrefixLength 23 `
                 -DefaultGateway "$staticBase.8"
Set-DnsClientServerAddress -InterfaceIndex $ifaceIdx `
                           -ServerAddresses '192.168.116.12','192.168.116.23'
Write-Host "Statische IP $chosen/23 gesetzt." -ForegroundColor Green

# 6) Adapter kurz neu initialisieren
Disable-NetAdapter -Name $adapter.Name -Confirm:$false
Start-Sleep 2
Enable-NetAdapter  -Name $adapter.Name -Confirm:$false
