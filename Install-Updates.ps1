param(
    [string]$vsphereSnapshotStatus
)

# Startzeit des Skripts
$scriptStartTime = Get-Date

$OutputEncoding = [System.Text.Encoding]::UTF8
$logFile = "C:\Scripts\Zabbix\WindowsUpdate.log"

# Ausgabe sammeln
$Output = @()

# Beispielhafte Verarbeitung des übergebenen Werts
$Output += "Der Wert des Makros {`$VSPHERE_SNAPSHOT_STATUS} ist: $vsphereSnapshotStatus"

# Hier kannst du den Wert weiterverarbeiten
$CheckSnapshot = $vsphereSnapshotStatus

# Prüfe, ob das System eine VMware-VM ist
$computerModel = (Get-WmiObject Win32_ComputerSystem).Model
if ($computerModel -notmatch "VMware") {
    $Output += "Das System ist keine VMware-VM, Snapshot-Prüfung wird übersprungen."
    # Da es sich nicht um eine VMware-VM handelt, setzen wir den Status auf "keine VM"
    $CheckSnapshot = "keine VM"
}
else {
    # Regex, um das Datum aus dem Snapshot-Status zu extrahieren (z.B. "11.02.2025")
    $pattern = "\d{2}\.\d{2}\.\d{4}"

    if ($CheckSnapshot -match $pattern) {
        # Extrahiertes Datum
        $snapshotDate = $matches[0]
        
        # Aktuelles Datum
        $currentDate = Get-Date -Format "dd.MM.yyyy"
        
        # Prüfen, ob der Snapshot heute erstellt wurde
        if ($snapshotDate -eq $currentDate) {
            $Output += "Snapshot wurde heute erstellt!"
            $CheckSnapshot = "OK"
        } else {
            $Output += "Snapshot wurde nicht heute ($(Get-Date -Format 'dd.MM.yyyy')) erstellt, sondern am $snapshotDate."
            $CheckSnapshot = "Snapshot veraltet"
        }
    }
    else {
        $Output += "Kein Datum im Snapshot-Status gefunden."
        $CheckSnapshot = "fehlt"
    }
}

# Falls der Snapshot aktuell ist oder das System keine VM ist, Updates ausführen und Ausgabe speichern
if ($CheckSnapshot -eq "OK" -or $CheckSnapshot -eq "keine VM") {
    $Output += "Snapshot ist aktuell oder nicht erforderlich (keine VM)."
    
    # Windows Updates abrufen & installieren
    $updateOutput = Install-WindowsUpdate -AcceptAll -IgnoreReboot -Confirm:$false -Verbose 4>&1 | Format-Table -Wrap -AutoSize | Out-String

    $Output += "Windows Update Ergebnis:"
    $Output += $updateOutput

    # Überprüfen, ob ein Neustart erforderlich ist
    $rebootStatus = Get-WURebootStatus -Silent
    if ($rebootStatus -eq $true) {
        $Output += "Neustart erforderlich: Ja"
    }
    else {
        $Output += "Neustart erforderlich: Nein"
    }

}
elseif ($CheckSnapshot -eq "fehlt") {
    $Output += "Snapshot fehlt"
}
else {
    $Output += "Status: $CheckSnapshot"
}

$scriptEndTime = Get-Date
$duration = $scriptEndTime - $scriptStartTime

$minutes = [math]::Floor($duration.TotalSeconds / 60)
$seconds = $duration.TotalSeconds % 60
$Output += "Scriptlaufzeit: $minutes Minuten und $seconds Sekunden"

# Schreibe den Inhalt in die Log-Datei
$Output -join "`n" | Out-File -FilePath "C:\Scripts\Zabbix\WindowsUpdate.log" -Encoding utf8 -Append

# Letzte Zeile als Rückgabewert für Zabbix
Write-Output ($Output -join "`n")
