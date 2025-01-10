# Variablen
$serviceName = "Zabbix Agent 2"
$zabbix_server = "192.168.116.114"  # IP-Adresse des Zabbix-Servers
$zabbix_key = "windows.updates.sender"  # Trapper Key im Zabbix
$zabbix_host =[System.Environment]::GetEnvironmentVariable('COMPUTERNAME') # Hostname wie in Zabbix konfiguriert

# Zabbix Sender Pfad ermitteln
$service = Get-WmiObject -Class Win32_Service -Filter "Name = '$serviceName'"
if ($null -eq $service) {
    Write-Error "Der Dienst '$serviceName' konnte nicht gefunden werden."
    exit 1
}

$servicePath = $service.PathName
if ($servicePath -match "-c\s+""([^""]+)""") {
    $configFilePath = $matches[1]
    $zabbix_sender_path = Join-Path -Path ($configFilePath -replace "\\[^\\]+$", "") -ChildPath "zabbix_sender.exe"

    if (-not (Test-Path $zabbix_sender_path)) {
        Write-Error "Die Datei 'zabbix_sender.exe' konnte nicht gefunden werden. Ermittelter Pfad: $zabbix_sender_path"
        exit 1
    }
} else {
    Write-Error "Der Dienstpfad oder die Konfigurationsdatei konnte nicht ermittelt werden. Pfad: $servicePath"
    exit 1
}

# Windows-Updates abrufen
try {
    Import-Module PSWindowsUpdate -ErrorAction Stop
    $updates = (Get-WindowsUpdate).GetEnumerator() | Select-Object -Property Title, KB, Size, LastDeploymentChangeTime

    if ($updates.Count -eq 0) {
        Write-Host "Keine Updates gefunden."
        & $zabbix_sender_path -z $zabbix_server -s $zabbix_host -k $zabbix_key -o "Keine Updates gefunden"
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
        $response = & $zabbix_sender_path -z $zabbix_server -s $zabbix_host -k $zabbix_key -o "$aggregatedMessage"
        Write-Host "Response: $response"
    }
} catch {
    Write-Error "Fehler beim Abrufen der Windows-Updates: $_"
    & $zabbix_sender_path -z $zabbix_server -s $zabbix_host -k $zabbix_key -o "Fehler beim Abrufen der Updates"
}
