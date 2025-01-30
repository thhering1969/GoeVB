<#
Version: 1.3
Datum: 29. Januar 2025
Autor: G�VB
Beschreibung: Dieses Skript pr�ft, ob das PowerShell-Modul PSWindowsUpdate bereits installiert ist. Wenn nicht, wird es extrahiert und an den richtigen Speicherort im PowerShell-Modulverzeichnis kopiert. Es wird auch die Anzahl der neuen Befehle angezeigt, wenn das Modul importiert wird. Am Ende werden die verf�gbaren Windows-Updates abgefragt.
#>

$startTime = Get-Date

# Setze die Ausgabe-Codierung f�r Konsolenausgabe auf UTF-8
#[System.Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Definiere Pfade
$zipPath = "C:\Scripts\Zabbix\PSWindowsUpdate-main.zip"  # Pfad zur ZIP-Datei
$extractPath = "C:\Scripts\Zabbix\PSWindowsUpdate"  # Zielordner zum Entpacken
$modulePath = "C:\Program Files\WindowsPowerShell\Modules"  # Systemweiter PowerShell-Modulordner
$moduleDestinationPath = "$modulePath\PSWindowsUpdate"  # Zielmodulpfad

$scriptPath = $MyInvocation.MyCommand.Path


. "$PSScriptRoot\EncodingFunctions.ps1"

 $outputPath = "$scriptPath-converted.ps1"
Convert-ToSBCS -filePath $scriptPath -outputPath $outputPath






# Schritt 1: �berpr�fen, ob der NuGet-Anbieter vorhanden ist

[System.Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$OutputEncoding=[System.Text.Encoding]::UTF8
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

Write-Output "�berpr�fe, ob der NuGet-Anbieter installiert ist..." 


$nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
if (-not $nugetProvider) {
    Write-Host "NuGet-Anbieter nicht gefunden. Installiere NuGet..."
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
} else {
    Write-Host "NuGet-Anbieter bereits installiert."
}

# Schritt 2: �berpr�fen, ob das PSWindowsUpdate-Modul bereits installiert ist
Write-Host "�berpr�fe, ob das PSWindowsUpdate-Modul bereits installiert ist..."

$installedModule = Get-Module -ListAvailable -Name PSWindowsUpdate
if ($installedModule) {
    Write-Host "Das PSWindowsUpdate-Modul ist bereits installiert."
} else {
    Write-Host "Das PSWindowsUpdate-Modul ist nicht installiert. Starte die Installation..."

    # Schritt 3: Installiere das PSWindowsUpdate-Modul, falls nicht vorhanden
    Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser

    # �berpr�fen, ob das Modul erfolgreich installiert wurde
    $installedModule = Get-Module -ListAvailable -Name PSWindowsUpdate
    if ($installedModule) {
        Write-Host "Das PSWindowsUpdate-Modul wurde erfolgreich installiert."
    } else {
        Write-Host "Fehler: Das PSWindowsUpdate-Modul konnte nicht installiert werden."
        exit
    }
}

# Schritt 4: Importiere das PSWindowsUpdate-Modul
if (-not (Get-Module -Name 'PSWindowsUpdate')) {
    Write-Host "Das PSWindowsUpdate-Modul ist nicht geladen. Importiere es jetzt..."
    Import-Module -Name 'PSWindowsUpdate' -Force
}

# Schritt 5: �berpr�fen, ob das Modul erfolgreich geladen wurde
if (Get-Module -Name 'PSWindowsUpdate') {
    Write-Host "Das PSWindowsUpdate-Modul ist jetzt geladen und verf�gbar."

    # Schritt 6: Anzahl neuer Befehle anzeigen
    $cmdletCount = (Get-Command -Module 'PSWindowsUpdate' | Where-Object { $_.CommandType -eq 'Cmdlet' }).Count
    Write-Host "Das Modul PSWindowsUpdate hat $cmdletCount neue Cmdlets geladen."
} else {
    Write-Host "Das PSWindowsUpdate-Modul konnte nicht geladen werden."
}

# Schritt 7: Hole die verf�gbaren Windows-Updates
Write-Host "Abfrage der verf�gbaren Windows-Updates..."
$windowsUpdates = Get-WindowsUpdate

if ($windowsUpdates.Count -gt 0) {
    Write-Host "Es sind $($windowsUpdates.Count) Windows-Updates verf�gbar."
    Write-Output $windowsUpdates.Count
} else {
    Write-Host "Keine Windows-Updates verf�gbar."
    Write-Output 0
}

# Abschlussmeldung
Write-Host "Aktualisierte Scriptversion: 1.3"
# Endzeit erfassen
$endTime = Get-Date
$duration = $endTime - $startTime

# Laufzeit in Minuten und Sekunden formatieren
$minutes = [math]::Floor($duration.TotalSeconds / 60)
$seconds = $duration.TotalSeconds % 60

Write-Host "Scriptlaufzeit: $minutes Minuten und $seconds Sekunden"
