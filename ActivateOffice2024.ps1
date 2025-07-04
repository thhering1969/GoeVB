# CombinedScript.ps1
#---------------------------------------------------------------
# Setzt eine statische IP (aus 192.168.116.1–3 per 3-fachem Ping-Test mit Fehlerbehandlung), 
# aktiviert Office per MAK online und stellt die IP-Konfiguration 
# wieder her (nur, wenn Teil 1 gelaufen ist).
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

# Flag, ob wir Teil 1 (IP-Änderung + Backup/Restore) überspringen
$skipToActivation = $false

# --- Teil 1: Statische IP setzen mit optionalem Backup/Restore ---
Write-Host '## Teil 1: Statische IP setzen und Backup anlegen' -ForegroundColor Cyan

# Adapter ermitteln
$netCfg = Get-NetIPConfiguration `
    | Where-Object { $_.IPv4DefaultGateway.NextHop } `
    | Where-Object { -not (Get-NetAdapter -InterfaceIndex $_.InterfaceIndex).Virtual } `
    | Select-Object -First 1
if (-not $netCfg) {
    $netCfg = Get-NetAdapter `
        | Where-Object { $_.Status -eq 'Up' -and -not $_.Virtual } `
        | Select-Object -First 1
    Write-Host 'Kein Gateway-Adapter gefunden, verwende ersten physischen Up-Adapter' -ForegroundColor Yellow
} else {
    Write-Host 'Gefundener physischer Adapter via DefaultGateway' -ForegroundColor Green
}
$ifaceIdx = $netCfg.InterfaceIndex
$adapter  = Get-NetAdapter -InterfaceIndex $ifaceIdx
Write-Host "Adapter: $($adapter.Name) (Index $ifaceIdx)"

# Prüfen, ob bereits eine IP aus 192.168.116.1–3 konfiguriert ist
$staticBase  = '192.168.116'
$poolIPs     = 1..3 | ForEach-Object { "$staticBase.$_" }
$existingIPs = (Get-NetIPAddress -InterfaceIndex $ifaceIdx -AddressFamily IPv4 -ErrorAction SilentlyContinue) |
               Select-Object -ExpandProperty IPAddress

if ($existingIPs | Where-Object { $poolIPs -contains $_ }) {
    Write-Host 'IP aus dem Pool bereits konfiguriert – überspringe Teil 1 (inkl. Backup/Restore).' -ForegroundColor Yellow
    ($existingIPs | Where-Object { $poolIPs -contains $_ }) |
        ForEach-Object { Write-Host "  • $_" -ForegroundColor Yellow }
    $skipToActivation = $true
}

if (-not $skipToActivation) {
    # --- Backup der aktuellen Konfiguration ---
    Write-Host 'Backup der aktuellen IP-Konfiguration …' -ForegroundColor Cyan
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
    Write-Host 'Backup abgeschlossen.' -ForegroundColor Green

    # DHCP deaktivieren und alte Einträge entfernen
    Write-Host 'Deaktiviere DHCP und lösche alte IP-/Gateway-Einträge …' -ForegroundColor Cyan
    Set-NetIPInterface -InterfaceIndex $ifaceIdx -Dhcp Disabled
    foreach ($store in 'ActiveStore','PersistentStore') {
        Get-NetIPAddress -InterfaceIndex $ifaceIdx -AddressFamily IPv4 -PolicyStore $store `
            -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        Get-NetRoute -InterfaceIndex $ifaceIdx -DestinationPrefix '0.0.0.0/0' -PolicyStore $store `
            -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
    }

    # Auswahl einer freien IP per 3-fachem Ping-Test mit Fehlerbehandlung
    Write-Host 'Suche freie IP aus 192.168.116.1–3 per Ping…' -ForegroundColor Cyan
    $chosen = $null
    foreach ($cand in (Get-Random -InputObject $poolIPs -Count $poolIPs.Length)) {
        $responded = $false
        try {
            $responded = Test-Connection -ComputerName $cand -Count 3 -Quiet -ErrorAction Stop
        } catch {
            $responded = $false
        }
        if (-not $responded) {
            $chosen = $cand
            break
        }
    }
    if (-not $chosen) {
        Write-Error 'Keine freie IP im Bereich .1–.3 gefunden!'
        exit 1
    }

    # Neue statische IP setzen
    Write-Host "Setze statische IP $chosen/23…" -ForegroundColor Cyan
    New-NetIPAddress -InterfaceIndex $ifaceIdx `
                     -IPAddress $chosen `
                     -PrefixLength 23 `
                     -DefaultGateway "$staticBase.8"
    Set-DnsClientServerAddress -InterfaceIndex $ifaceIdx `
                               -ServerAddresses '192.168.116.12','192.168.116.23'
    Write-Host "Statische IP $chosen/23 gesetzt." -ForegroundColor Green

    # Adapter kurz neu initialisieren
    Disable-NetAdapter -Name $adapter.Name -Confirm:$false
    Start-Sleep 2
    Enable-NetAdapter  -Name $adapter.Name -Confirm:$false
}

# --- Teil 2: Office-Aktivierung (immer) ---
Write-Host '## Teil 2: Office aktivieren' -ForegroundColor Cyan
$paths = @(
    "$env:ProgramFiles\Microsoft Office",
    "$env:ProgramFiles(x86)\Microsoft Office"
)
$osppFile = $paths |
    ForEach-Object { Get-ChildItem -Path $_ -Recurse -Filter ospp.vbs -ErrorAction SilentlyContinue } |
    Select-Object -First 1
if (-not $osppFile) {
    Write-Error 'ospp.vbs nicht gefunden. Bitte Pfad prüfen!'
    exit 1
}
$officePath = $osppFile.DirectoryName
Push-Location $officePath

# Korrigierte do…while-Schleife mit ordentlicher TotalSeconds-Auswertung
Write-Host 'Warte auf TCP Port 443 von activation.sls.microsoft.com (max. 60 s)...' -NoNewline
$startTime = Get-Date
do {
    $result = Test-NetConnection -ComputerName 'activation.sls.microsoft.com' -Port 443
    if ($result.TcpTestSucceeded) {
        Write-Host ' OK' -ForegroundColor Green
        break
    }
    Start-Sleep -Seconds 5
} while (((Get-Date) - $startTime).TotalSeconds -lt 60)

if (-not $result.TcpTestSucceeded) {
    Write-Error 'Timeout: Aktivierungs-Server nicht erreichbar.'
    exit 1
}

Write-Host 'Starte Online-Aktivierung' -ForegroundColor Cyan
cscript ospp.vbs /act
cscript ospp.vbs /dstatus
Pop-Location

# --- Teil 3: IP-Restore aus Backup (nur wenn Teil 1 gelaufen ist) ---
if (-not $skipToActivation) {
    Write-Host '## Teil 3: IP-Restore aus Backup' -ForegroundColor Cyan
    $backupRoot = 'HKCU:\Software\NetIPBackup'
    if (-not (Test-Path $backupRoot)) {
        Write-Warning 'Kein IP-Backup gefunden.'
        exit 0
    }
    Get-ChildItem -Path $backupRoot | ForEach-Object {
        $g   = $_.PSChildName
        $dst = "$backupRoot\$g"
        Write-Host "Restore GUID $g"
        $adapterRestore = Get-NetAdapter | Where-Object InterfaceGuid -EQ $g
        if (-not $adapterRestore) {
            Write-Warning "Adapter $g nicht gefunden"
            return
        }
        $idx  = $adapterRestore.InterfaceIndex
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
                Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 -PolicyStore $store `
                    -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
                Get-NetRoute -InterfaceIndex $idx -DestinationPrefix '0.0.0.0/0' -PolicyStore $store `
                    -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
            }
            function Get-PrefixLength { param($m)
                return ((($m -split '\.') |
                         ForEach-Object { [Convert]::ToString($_,2).PadLeft(8,'0') }) -join '').
                       ToCharArray() | Where-Object { $_ -eq '1' } | Measure-Object |
                       Select-Object -ExpandProperty Count
            }
            $pre = Get-PrefixLength -m $mask
            foreach ($ip in @($ips)) {
                New-NetIPAddress -InterfaceIndex $idx -IPAddress $ip -PrefixLength $pre -DefaultGateway $gw
            }
            if ($dns) {
                Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses @($dns)
            }
        }
        Disable-NetAdapter -Name $adapterRestore.Name -Confirm:$false
        Start-Sleep 2
        Enable-NetAdapter  -Name $adapterRestore.Name -Confirm:$false
        Write-Host "Restore $($adapterRestore.Name) DONE`n"
    }
}

Write-Host 'Scriptende.' -ForegroundColor Cyan
