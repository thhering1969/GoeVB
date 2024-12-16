# Zabbix-Server und Host-Details
$zabbixServer = "192.168.116.114"
$zabbixKeySnapshot = "vSphere.Snapshot.Status" # Zabbix-Item-Key für den Snapshot-Status

# Lokaler Hostname ermitteln
$zabbixHost = (Get-WmiObject Win32_ComputerSystem).Name
Write-Host "Lokaler Zabbix-Host: $zabbixHost"

# Funktion: Dynamischer Pfad zu zabbix_get und zabbix_sender ermitteln
function Get-ZabbixPath {
    Write-Host "Versuche, den Pfad für 'zabbix_get' und 'zabbix_sender' dynamisch zu ermitteln..."
    
    # Ermittlung von zabbix_get und zabbix_sender
    $zabbixGetPath = (Get-Command -Name zabbix_get -ErrorAction SilentlyContinue).Source
    if (-not $zabbixGetPath) {
        try {
            $servicePath = Get-WmiObject -Class Win32_Service -Filter "Name='Zabbix Agent 2'" | Select-Object -ExpandProperty PathName
            if ($servicePath -match "-c\s+""([^""]+)""") {
                $configFilePath = $matches[1]
                $zabbixGetPath = Join-Path -Path ($configFilePath -replace "\\[^\\]+$", "") -ChildPath "zabbix_get.exe"
                $zabbixSenderPath = Join-Path -Path ($configFilePath -replace "\\[^\\]+$", "") -ChildPath "zabbix_sender.exe"
                Write-Host "Pfad zu zabbix_get: $zabbixGetPath"
                Write-Host "Pfad zu zabbix_sender: $zabbixSenderPath"
            } else {
                Write-Error "Fehler beim Ermitteln des Servicepfads für Zabbix-Agent: Der Pfad konnte nicht extrahiert werden."
                return $null
            }
        } catch {
            Write-Error "Fehler beim Ermitteln des Servicepfads für Zabbix-Agent: $_"
            return $null
        }
    }

    # Prüfen, ob die ermittelten Pfade existieren
    if (Test-Path $zabbixGetPath -and Test-Path $zabbixSenderPath) {
        Write-Host "Pfad zu zabbix_get und zabbix_sender gefunden."
        return $zabbixGetPath, $zabbixSenderPath
    } else {
        Write-Error "zabbix_get oder zabbix_sender konnten weder über den Systempfad noch über den Agent-Service gefunden werden."
        return $null
    }
}

# Funktion: Erfolgreichen Snapshot prüfen
function Get-LastSuccessfulSnapshot {
    Write-Host "Frage den letzten erfolgreichen Snapshot von Zabbix ab..."

    ($zabbixGetPath, $zabbixSenderPath) = Get-ZabbixPath
    if (-not $zabbixGetPath) {
        Write-Error "zabbix_get Pfad konnte nicht ermittelt werden."
        return $null
    }

    # Befehl zusammenstellen
    $command = "$zabbixGetPath -s $zabbixServer -k $zabbixKeySnapshot -o $zabbixHost"
    Write-Host "Führe aus: $command"

    # Ergebnis abrufen
    try {
        $lastSnapshot = & $zabbixGetPath -s $zabbixServer -k $zabbixKeySnapshot -o $zabbixHost
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

# Funktion: Zabbix-Sender verwenden
function Zabbix-Sender {
    param (
        [string]$Status
    )

    # Sende Daten an den Zabbix-Server
    $command = "$zabbixSenderPath -z $zabbixServer -s $zabbixHost -k $zabbixKeySnapshot -o $Status"
    Write-Host "Sende Daten an Zabbix: $command"
    try {
        & $zabbixSenderPath -z $zabbixServer -s $zabbixHost -k $zabbixKeySnapshot -o $Status
        Write-Host "Daten erfolgreich an Zabbix gesendet: Status='$Status'."
    } catch {
        Write-Error "Fehler beim Senden von Daten an Zabbix: $_"
    }
}

# Hauptablauf
Write-Host "Prüfe, ob ein Snapshot vorhanden ist..."
$snapshotName = Get-LastSuccessfulSnapshot

if ($snapshotName) {
    Write-Host "Snapshot '$snapshotName' ist vorhanden. Führe fort..."
    # Hier könnten zusätzliche Schritte durchgeführt werden, falls der Snapshot vorhanden ist
} else {
    Write-Host "Kein erfolgreicher Snapshot gefunden."
}
