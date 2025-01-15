<#
Version: 1.2
Datum: 11. Dezember 2024
Autor: GöVB
Beschreibung: Dieses Skript prüft, ob das PowerShell-Modul PSWindowsUpdate bereits installiert ist. Wenn nicht, wird es extrahiert und an den richtigen Speicherort im PowerShell-Modulverzeichnis kopiert. Es wird auch die Anzahl der neuen Befehle angezeigt, wenn das Modul importiert wird. Am Ende werden die verfügbaren Windows-Updates abgefragt und an Zabbix gesendet.
#>

# Setze Codepage auf UTF-8
chcp 65001
$OutputEncoding = [System.Text.Encoding]::UTF8
[console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Definiere Pfade
$zipPath = "C:\Scripts\Zabbix\PSWindowsUpdate-main.zip" # Pfad zur ZIP-Datei
$extractPath = "C:\Scripts\Zabbix\PSWindowsUpdate"  # Zielordner zum Entpacken
$modulePath = "C:\Program Files\WindowsPowerShell\Modules"  # Systemweiter PowerShell-Modulordner
$moduleDestinationPath = "$modulePath\PSWindowsUpdate"  # Zielmodulpfad

# Variablen für Zabbix
$serviceName = "Zabbix Agent 2"
$zabbix_server = "192.168.116.114"  # IP-Adresse des Zabbix-Servers
$zabbix_key = "windows.updates.sender"  # Trapper Key im Zabbix

# Schritt 1: Überprüfen, ob das PSWindowsUpdate-Modul bereits installiert ist
Write-Host "$([char]0x00DC)berpr$([char]0x00FC)fe, ob das PSWindowsUpdate-Modul bereits installiert ist..."
if (Test-Path -Path $moduleDestinationPath) {
    Write-Host "Das PSWindowsUpdate-Modul ist im Verzeichnis $moduleDestinationPath vorhanden."
} else {
    Write-Host "Das PSWindowsUpdate-Modul ist noch nicht installiert. Fahre mit der Installation fort..."

    # Schritt 2: Überprüfen, ob die ZIP-Datei existiert
    Write-Host "$([char]0x00DC)berpr$([char]0x00FC)fe, ob die ZIP-Datei existiert..."
    if (-not (Test-Path -Path $zipPath)) {
        Write-Host "Fehler: Die ZIP-Datei wurde nicht gefunden unter $zipPath."
        exit
    }
    Write-Host "ZIP-Datei gefunden: $zipPath"

    # Schritt 3: Entpacke die ZIP-Datei
    Write-Host "$([char]0x00C4)ndern: Entpacke die ZIP-Datei..."
    if (-not (Test-Path -Path $extractPath)) {
        New-Item -ItemType Directory -Path $extractPath
    }
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
    Write-Host "ZIP-Datei erfolgreich entpackt nach $extractPath."

    # Schritt 4: Überprüfen der Ordnerstruktur nach dem Entpacken
    $moduleSourcePath = "$extractPath\PSWindowsUpdate-main"
    if (-not (Test-Path -Path $moduleSourcePath)) {
        Write-Host "Fehler: Der Ordner 'PSWindowsUpdate-main' wurde nicht gefunden."
        exit
    }
    Write-Host "Entpackter Ordner gefunden: $moduleSourcePath"

    # Schritt 5: Zielordner für das Modul erstellen, falls er nicht existiert
    if (-not (Test-Path -Path $moduleDestinationPath)) {
        New-Item -ItemType Directory -Path $moduleDestinationPath
    }

    # Schritt 6: Verschiebe die entpackten Dateien in das PowerShell-Modul-Verzeichnis
    Write-Host "Verschiebe Dateien nach $moduleDestinationPath..."
    $sourceFiles = Get-ChildItem -Path $moduleSourcePath
    foreach ($file in $sourceFiles) {
        Write-Host "Verschiebe Datei: $($file.Name)"
        Move-Item -Path $file.FullName -Destination $moduleDestinationPath -Force
    }
    Write-Host "Dateien erfolgreich nach $moduleDestinationPath verschoben."
}

# Schritt 7: Importiere das PSWindowsUpdate-Modul
$loadedModule = Get-Module -Name 'PSWindowsUpdate' -ListAvailable
if (-not $loadedModule) {
    Write-Host "Das PSWindowsUpdate-Modul ist nicht geladen. Importiere es jetzt..."
    Import-Module -Name 'PSWindowsUpdate' -Force
}

# Schritt 8: Überprüfen, ob das Modul erfolgreich geladen wurde
$loadedModule = Get-Module -Name 'PSWindowsUpdate'
if ($loadedModule) {
    Write-Host "Das PSWindowsUpdate-Modul ist jetzt geladen und verf$([char]0x00FC)gbar."
    $cmdlets = Get-Command -Module 'PSWindowsUpdate' | Where-Object { $_.CommandType -eq 'Cmdlet' }
    $cmdletCount = $cmdlets.Count
    Write-Host "Das Modul PSWindowsUpdate hat $cmdletCount neue Cmdlets geladen."
} else {
    Write-Host "Das PSWindowsUpdate-Modul konnte nicht geladen werden."
}

# Zabbix Sender Pfad ermitteln
$service = Get-WmiObject -Class Win32_Service -Filter "Name = '$serviceName'"
if ($null -eq $service) {
    Write-Error "Der Dienst '$serviceName' konnte nicht gefunden werden."
    exit 1
}

$servicePath = $service.PathName
if ($servicePath -match "-c\s+""([^""]+)""") {
    $configFilePath = $matches[1]
    
    # Zabbix-Konfigurationspfad und zabbix_sender.exe-Pfad zusammenbauen
    $zabbix_config_path = Join-Path -Path ($configFilePath -replace "\\[^\\]+$", "") -ChildPath "zabbix_agent2.conf"
    if (-not (Test-Path $zabbix_config_path)) {
        Write-Error "Die Konfigurationsdatei 'zabbix_agent2.conf' konnte nicht gefunden werden. Ermittelter Pfad: $zabbix_config_path"
        exit 1
    }

    # zabbix_sender.exe Pfad ermitteln
    $zabbix_sender_path = Join-Path -Path ($configFilePath -replace "\\[^\\]+$", "") -ChildPath "zabbix_sender.exe"
    if (-not (Test-Path $zabbix_sender_path)) {
        Write-Error "Die Datei 'zabbix_sender.exe' konnte nicht gefunden werden. Ermittelter Pfad: $zabbix_sender_path"
        exit 1
    }
} else {
    Write-Error "Der Dienstpfad oder die Konfigurationsdatei konnte nicht ermittelt werden. Pfad: $servicePath"
    exit 1
}

# Hostname aus der Zabbix-Agent-Konfigurationsdatei extrahieren
$zabbix_host = (Select-String -Path $zabbix_config_path -Pattern '^Hostname=').Line.Split('=')[1].Trim()

# Windows-Updates abrufen
try {
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

            $message = "Title: $title; KB: $kb; Size: $size MB; Date: $date"
            $updateMessages += $message
        }
        $aggregatedMessage = $updateMessages -join "`n"
        $response = & $zabbix_sender_path -z $zabbix_server -s $zabbix_host -k $zabbix_key -o "$aggregatedMessage"
        Write-Host "Host: $zabbix_host  Response: $response"
    }
} catch {
    Write-Error "Fehler beim Abrufen der Windows-Updates: $_"
    & $zabbix_sender_path -z $zabbix_server -s $zabbix_host -k $zabbix_key -o "Fehler beim Abrufen der Updates"
}
