# Startzeit erfassen
$startTime = Get-Date

try {
    # Prüfen, ob das PSWindowsUpdate-Modul bereits geladen oder nur verfügbar ist
    if (Get-Module -Name PSWindowsUpdate) {
        Write-Host "Das Modul 'PSWindowsUpdate' ist bereits geladen."
    } elseif (Get-Module -Name PSWindowsUpdate -ListAvailable) {
        Write-Host "Das Modul 'PSWindowsUpdate' ist auf dem System verfügbar, aber nicht geladen."
        
        # Versuch, das Modul zu laden
        try {
            Import-Module -Name PSWindowsUpdate -ErrorAction Stop
            Write-Host "Das Modul 'PSWindowsUpdate' wurde erfolgreich geladen."
        } catch {
            Write-Error "Fehler beim Laden des Moduls 'PSWindowsUpdate': $_"
        }
    } else {
        Write-Host "Das Modul 'PSWindowsUpdate' ist nicht installiert."
        
        # Optional: Anweisungen zur Installation geben
        #Write-Host "Bitte installieren Sie das Modul mit folgendem Befehl:"
        #Write-Host "Install-Module -Name PSWindowsUpdate -Force"
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
