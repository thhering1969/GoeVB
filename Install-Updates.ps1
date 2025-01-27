param(
    [string]$vsphereSnapshotStatus
)

# Beispielhafte Verarbeitung des übergebenen Werts
Write-Host "Der Wert des Makros {`$VSPHERE_SNAPSHOT_STATUS} ist: $vsphereSnapshotStatus"

# Hier kannst du den Wert weiterverarbeiten, z.B. in einer Variablen speichern
$CheckSnapshot = $vsphereSnapshotStatus

# Regex, um das Datum aus dem Status zu extrahieren (z.B. "27.01.2025")
$pattern = "\d{2}\.\d{2}\.\d{4}"

if ($CheckSnapshot -match $pattern) {
    # Extrahiertes Datum im Format "dd.MM.yyyy"
    $snapshotDate = $matches[0]
    
    # Das aktuelle Datum im gleichen Format
    $currentDate = Get-Date -Format "dd.MM.yyyy"
    
    # Überprüfen, ob das Datum des Snapshots heute ist
    if ($snapshotDate -eq $currentDate) {
        Write-Host "Snapshot wurde heute erstellt!"
        $CheckSnapshot="OK"
    } else {
        Write-Host "Snapshot wurde nicht heute erstellt, sondern am $snapshotDate."
	$CheckSnapshot="veraltet"
    }
} else {
    Write-Host "Kein Datum im Snapshot-Status gefunden."
    $CheckSnapshot="fehlt"
}

# Weitere Verarbeitung je nach Status
if ( $CheckSnapshot -eq "OK") {
    Write-Host "Snapshot ist aktiv."
    Get-WindowsUpdate -AcceptAll -Install

} elseif ($myVar -eq "fehlt") {
    Write-Host "Snapshot fehlt"
} else {
    Write-Host "Unbekannter Status: $CheckSnapshot"
}
