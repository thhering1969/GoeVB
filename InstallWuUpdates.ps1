# Zabbix-Server und Host-Details
$zabbixServer = "192.168.20.32"
$itemKey = "vSphere.Snapshot.LastSuccessful"

# Lokaler Hostname ermitteln
$zabbixHost = (Get-WmiObject Win32_ComputerSystem).Name
Write-Host "Lokaler Zabbix-Host: $zabbixHost"

# Funktion: Dynamischer Pfad zu zabbix_get ermitteln
function Get-ZabbixGetPath {
    Write-Host "Versuche, den Pfad für 'zabbix_get' dynamisch zu ermitteln..."
    $zabbixGetPath = (Get-Command -Name zabbix_get -ErrorAction SilentlyContinue).Source

    if (-not $zabbixGetPath) {
        try {
            # Fallback: Servicepfad des Zabbix-Agent ermitteln
            $servicePath = Get-WmiObject -Class Win32_Service -Filter "Name='Zabbix Agent 2'" | Select-Object -ExpandProperty PathName
            if ($servicePath -match "-c\s+""([^""]+)""") {
                $configFilePath = $matches[1]
                $zabbixGetPath = Join-Path -Path ($configFilePath -replace "\\[^\\]+$", "") -ChildPath "zabbix_get.exe"
                Write-Host "zabbix_get wurde aus dem Agent-Service-Pfad ermittelt: $zabbixGetPath"
            } else {
                Write-Error "Fehler beim Ermitteln des Servicepfads für Zabbix-Agent: Der Pfad konnte nicht extrahiert werden."
                return $null
            }
        } catch {
            Write-Error "Fehler beim Ermitteln des Servicepfads für Zabbix-Agent: $_"
            return $null
        }
    }

    # Prüfen, ob der ermittelte Pfad existiert
    if (Test-Path $zabbixGetPath) {
        Write-Host "Pfad zu zabbix_get gefunden: $zabbixGetPath"
        return $zabbixGetPath
    } else {
        Write-Error "zabbix_get konnte weder über den Systempfad noch über den Agent-Service gefunden werden."
        return $null
    }
}

# Funktion: Erfolgreichen Snapshot prüfen
function Get-LastSuccessfulSnapshot {
    Write-Host "Frage den letzten erfolgreichen Snapshot von Zabbix ab..."

    $zabbixGetPath = Get-ZabbixGetPath
    if (-not $zabbixGetPath) {
        Write-Error "zabbix_get Pfad konnte nicht ermittelt werden."
        return $null
    }

    # Befehl zusammenstellen
    $command = "$zabbixGetPath -s $zabbixServer -k $itemKey -o $zabbixHost"
    Write-Host "Führe aus: $command"

    # Ergebnis abrufen
    try {
        $lastSnapshot = & $zabbixGetPath -s $zabbixServer -k $itemKey -o $zabbixHost
        if ($lastSnapshot) {
            Write-Host "Letzter erfolgreicher Snapshot: $lastSnapshot"
            return $lastSnapshot
        } else {
            Write-Error "Kein erfolgreicher Snapshot gefunden!"
            return $null
        }
    } catch {
        Write-Error "Fehler beim Abrufen des letzten erfolgreichen Snapshots: $_"
        return $null
    }
}

# Hauptablauf
Write-Host "Prüfe, ob ein Snapshot vorhanden ist..."
$snapshotName = Get-LastSuccessfulSnapshot

if ($snapshotName) {
    Write-Host "Snapshot '$snapshotName' ist vorhanden. Füh
