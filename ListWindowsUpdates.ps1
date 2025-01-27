# Startzeit erfassen
$startTime = Get-Date

try {
    # Prüfen, ob das Modul geladen oder nur verfügbar ist
    if (-not (Get-Module -Name PSWindowsUpdate)) {
        if (Get-Module -Name PSWindowsUpdate -ListAvailable) {
            Write-Host "Das Modul 'PSWindowsUpdate' ist verfügbar, aber nicht geladen. Lade es jetzt..."
            Import-Module -Name PSWindowsUpdate -Force -ErrorAction Stop
        } else {
            Write-Host "Das Modul 'PSWindowsUpdate' ist nicht installiert."
            exit
        }
    } else {
        Write-Host "Das Modul 'PSWindowsUpdate' ist bereits geladen."
    }

    # Windows-Updates abrufen
    $updates = (Get-WindowsUpdate).GetEnumerator() | Select-Object -Property Title, KB, Size, LastDeploymentChangeTime

    if ($updates.Count -eq 0) {
        Write-Host "Keine Updates gefunden."
    } else {
        $updateMessages = @()
        foreach ($update in $updates) {
            $title = $update.Title
            $kb = $update.KB
            $size = $update.Size
            $date = $update.LastDeploymentChangeTime

            # Nachricht für Zabbix formatieren
            $message = "Title: $title; KB: $kb; Size: $size MB; Date: $date"
            $updateMessages += $message
        }

        # Daten an Zabbix senden
        $aggregatedMessage = $updateMessages -join "`n"
        Write-Host "Updates gefunden:`n$aggregatedMessage"
    }

} catch {
    Write-Error "Fehler beim Abrufen der Windows-Updates: $_"
}

# Endzeit erfassen
$endTime = Get-Date
$duration = $endTime - $startTime

# Laufzeit in Minuten und Sekunden formatieren
$minutes = [math]::Floor($duration.TotalSeconds / 60)
$seconds = $duration.TotalSeconds % 60

Write-Host "Scriptlaufzeit: $minutes Minuten und $seconds Sekunden"
