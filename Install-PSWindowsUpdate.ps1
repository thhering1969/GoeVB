<#
Version: 1.2
Datum: 11. Dezember 2024
Autor: GöVB
Beschreibung: Dieses Skript prüft, ob das PowerShell-Modul PSWindowsUpdate bereits installiert ist. Wenn nicht, wird es extrahiert und an den richtigen Speicherort im PowerShell-Modulverzeichnis kopiert. Es wird auch die Anzahl der neuen Befehle angezeigt, wenn das Modul importiert wird. Am Ende werden die verfügbaren Windows-Updates abgefragt.
#>



# Setze die Ausgabe-Codierung für Konsolenausgabe auf UTF-8
[System.Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Definiere Pfade
$zipPath = "C:\Scripts\Zabbix\PSWindowsUpdate-main.zip"  # Pfad zur ZIP-Datei
$extractPath = "C:\Scripts\Zabbix\PSWindowsUpdate"  # Zielordner zum Entpacken
$modulePath = "C:\Program Files\WindowsPowerShell\Modules"  # Systemweiter PowerShell-Modulordner
$moduleDestinationPath = "$modulePath\PSWindowsUpdate"  # Zielmodulpfad

# Schritt 1: Überprüfen, ob das PSWindowsUpdate-Modul bereits installiert ist
Write-Host "Überprüfe, ob das PSWindowsUpdate-Modul bereits installiert ist..."

# Überprüfe, ob das Modul bereits installiert (d.h. ob das Verzeichnis existiert)
if (Test-Path -Path $moduleDestinationPath) {
    Write-Host "Das PSWindowsUpdate-Modul ist im Verzeichnis $moduleDestinationPath vorhanden."
} else {
    Write-Host "Das PSWindowsUpdate-Modul ist noch nicht installiert. Fahre mit der Installation fort..."
    
    # Schritt 2: Überprüfen, ob die ZIP-Datei existiert
    Write-Host "Überprüfe, ob die ZIP-Datei existiert..."

    if (-not (Test-Path -Path $zipPath)) {
        Write-Host "Fehler: Die ZIP-Datei wurde nicht gefunden unter $zipPath."
        exit
    }

    Write-Host "ZIP-Datei gefunden: $zipPath"

    # Schritt 3: Entpacke die ZIP-Datei
    Write-Host "Ändern: Entpacke die ZIP-Datei..."

    # Erstelle Zielordner, wenn nicht vorhanden
    if (-not (Test-Path -Path $extractPath)) {
        New-Item -ItemType Directory -Path $extractPath
    }

    # Entpacke die ZIP-Datei
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
    Write-Host "ZIP-Datei erfolgreich entpackt nach $extractPath."

    # Schritt 4: Überprüfen der Ordnerstruktur nach dem Entpacken
    $moduleSourcePath = "$extractPath\PSWindowsUpdate-main"  # Entpackter Ordner

    # Wenn der entpackte Ordner nicht existiert, beende das Skript
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

# Schritt 7: Importiere das PSWindowsUpdate-Modul, wenn es nicht bereits geladen ist
$loadedModule = Get-Module -Name 'PSWindowsUpdate' -ListAvailable
if (-not $loadedModule) {
    Write-Host "Das PSWindowsUpdate-Modul ist nicht geladen. Importiere es jetzt..."
    Import-Module -Name 'PSWindowsUpdate' -Force
}

# Schritt 8: Überprüfen, ob das Modul erfolgreich geladen wurde
$loadedModule = Get-Module -Name 'PSWindowsUpdate'
if ($loadedModule) {
    Write-Host "Das PSWindowsUpdate-Modul ist jetzt geladen und verf$([char]0x00FC)gbar."

    # Schritt 9: Anzeige der Anzahl neuer Befehle
    $cmdlets = Get-Command -Module 'PSWindowsUpdate' | Where-Object { $_.CommandType -eq 'Cmdlet' }
    $cmdletCount = $cmdlets.Count
    Write-Host "Das Modul PSWindowsUpdate hat $cmdletCount neue Cmdlets geladen."
} else {
    Write-Host "Das PSWindowsUpdate-Modul konnte nicht geladen werden."
}

# Schritt 10: Hole die verfügbaren Windows-Updates
Write-Host "Abfrage der verfügbaren Windows-Updates..."
$windowsUpdates = Get-WindowsUpdate

# Falls es Updates gibt, gebe die Anzahl der verfügbaren Updates aus
if ($windowsUpdates.Count -gt 0) {
    Write-Host "Es sind $($windowsUpdates.Count) Windows-Updates verfügbar."
    # Gebe eine Zabbix-freundliche Ausgabe zurück
    Write-Output $windowsUpdates.Count
} else {
    Write-Host "Keine Windows-Updates verfügbar."
    # Gebe eine Zabbix-freundliche Ausgabe zurück
    Write-Output 0
}

# Abschlussmeldung
Write-Host "Aktualisierte Scriptversion: 1.2"
