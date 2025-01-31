# Startzeit erfassen
$startTime = Get-Date

# Setze die Ausgabe-Codierung für Konsolenausgabe auf UTF-8
$OutputEncoding = [System.Console]::OutputEncoding = [System.Console]::InputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# Importiere das externe Skript, das die Funktion definiert
. "$PSScriptRoot\Write-OutputSafe.ps1"

# Setze den Alias für write-output
New-Alias write-output Write-OutputSafe
New-Alias write-host Write-OutputSafe



try {
    # Prüfen, ob der Befehl 'Get-WindowsUpdate' verfügbar ist
    if (-not (Get-Command -Name Get-WindowsUpdate -ErrorAction SilentlyContinue)) {
        Write-Host "Der Befehl 'Get-WindowsUpdate' ist nicht verfügbar. Stellen Sie sicher, dass das 'PSWindowsUpdate'-Modul installiert ist."
        exit
    }

    # Windows-Updates abrufen
    

    $updates = Get-WindowsUpdate -Verbose 

    if ($updates.Count -eq 0) {
        Write-Host "Keine Updates gefunden."
    } else {
        $updateMessages = @()
        foreach ($update in $updates) {
            $title = $update.Title
            $kb = $update.KBArticleIDs -join ", "
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
