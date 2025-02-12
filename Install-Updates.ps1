param(
    [string]$vsphereSnapshotStatus
)

$OutputEncoding = [System.Text.Encoding]::UTF8
$logFile = "C:\Scripts\Zabbix\WindowsUpdate.log"

# Ausgabe sammeln
$Output = @()

# Beispielhafte Verarbeitung des übergebenen Werts
$Output += "Der Wert des Makros {`$VSPHERE_SNAPSHOT_STATUS} ist: $vsphereSnapshotStatus"

# Hier kannst du den Wert weiterverarbeiten
$CheckSnapshot = $vsphereSnapshotStatus

# Regex, um das Datum aus dem Status zu extrahieren (z.B. "11.02.2025")
$pattern = "\d{2}\.\d{2}\.\d{4}"

if ($CheckSnapshot -match $pattern) {
    # Extrahiertes Datum
    $snapshotDate = $matches[0]
    
    # Aktuelles Datum
    $currentDate = Get-Date -Format "dd.MM.yyyy"
    
    # Prüfen, ob Snapshot heute erstellt wurde
    if ($snapshotDate -eq $currentDate) {
        $Output += "Snapshot wurde heute erstellt!"
        $CheckSnapshot = "OK"
    } else {
        $Output += "Snapshot wurde nicht heute ($(Get-Date -Format 'dd.MM.yyyy')) erstellt, sondern am $snapshotDate."
        $CheckSnapshot = "Snapshot veraltet"
    }
} else {
    $Output += "Kein Datum im Snapshot-Status gefunden."
    $CheckSnapshot = "Snapshot fehlt"
}

# Falls der Snapshot aktuell ist, Updates ausführen und Ausgabe speichern
if ($CheckSnapshot -eq "OK") {
    $Output += "Snapshot ist aktiv."
    
    # Windows Updates abrufen & installieren
    $updateOutput = Get-WindowsUpdate -AcceptAll -Install -IgnoreReboot -Verbose 4>&1 | Out-String

    $Output += "Windows Update Ergebnis:"
    $Output += $updateOutput

} elseif ($CheckSnapshot -eq "fehlt") {
    $Output += "Snapshot fehlt"
} else {
    $Output += "Status: $CheckSnapshot"
}



# Schreibe den Inhalt in die Datei
$Output -join "`n" | Out-File -FilePath "C:\Scripts\Zabbix\WindowsUpdate.log" -Encoding utf8 -Append







# Letzte Zeile als Rückgabewert für Zabbix
Write-Output ($Output -join "`n")
