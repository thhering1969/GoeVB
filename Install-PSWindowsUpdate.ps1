<#
Version: 1.4
Datum: 4. Februar 2025
Autor: GöVB
Beschreibung: 
- Prüft, ob das PSWindowsUpdate-Modul installiert ist. 
- Installiert es über `Install-Module` oder alternativ über eine ZIP-Datei, falls `Install-Module` fehlschlägt.
- Zeigt die Anzahl neuer Cmdlets an und listet verfügbare Updates.
#>

$startTime = Get-Date

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Setze die Ausgabe-Codierung für Konsolenausgabe auf UTF-8
$OutputEncoding = [System.Console]::OutputEncoding = [System.Console]::InputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# Definiere Pfade
$zipPath = "C:\Scripts\Zabbix\PSWindowsUpdate-main.zip"  # ZIP-Datei
$extractPath = "C:\Scripts\Zabbix\PSWindowsUpdate"  # Entpack-Ordner
$modulePath = "C:\Program Files\WindowsPowerShell\Modules"  # PowerShell-Modulpfad
$moduleDestinationPath = "$modulePath\PSWindowsUpdate"  # Zielmodulpfad

# Importiere das externe Skript für Write-OutputSafe
. "$PSScriptRoot\Write-OutputSafe.ps1"
New-Alias write-output Write-OutputSafe
New-Alias write-host Write-OutputSafe



# Prüfen, ob das Modul bereits installiert ist
Write-Host "Überprüfe, ob das PSWindowsUpdate-Modul bereits installiert ist..."
$installedModule = Get-Module -ListAvailable -Name PSWindowsUpdate

if (-not $installedModule) {
    Write-Host "Das PSWindowsUpdate-Modul ist nicht installiert. Starte die Installation..."

    Try {
        Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -ErrorAction Stop
        $installedModule = Get-Module -ListAvailable -Name PSWindowsUpdate
    } Catch {
        Write-Host "Install-Module fehlgeschlagen. Wechsle zur manuellen Installation..."

        # Prüfen, ob ZIP-Datei existiert
        if (Test-Path $zipPath) {
            Write-Host "Entpacke das Modul aus der ZIP-Datei..."
            Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

            # Setze den korrekten Modulpfad
            $unpackedModulePath = "$extractPath\PSWindowsUpdate-main\PSWindowsUpdate"

            if (Test-Path "$unpackedModulePath\PSWindowsUpdate.psd1") {
                Write-Host "Kopiere das Modul in das PowerShell-Modulverzeichnis..."
                Copy-Item -Path $unpackedModulePath -Destination $moduleDestinationPath -Recurse -Force
            } else {
                Write-Host "Fehler: Das entpackte Modulverzeichnis wurde nicht gefunden!"
                exit 1
            }
        } else {
            Write-Host "Fehler: Die ZIP-Datei für PSWindowsUpdate existiert nicht!"
            exit 1
        }
    }
}

# Modul importieren
Write-Host "Das PSWindowsUpdate-Modul ist nicht geladen. Importiere es jetzt..."
Import-Module -Name 'PSWindowsUpdate' -Force

# Testen, ob das Modul erfolgreich geladen wurde
if (Get-Module -Name 'PSWindowsUpdate') {
    Write-Host "Das PSWindowsUpdate-Modul ist jetzt geladen und verfügbar."

    # Anzahl neuer Befehle anzeigen
    $cmdletCount = (Get-Command -Module 'PSWindowsUpdate' | Where-Object { $_.CommandType -eq 'Cmdlet' }).Count
    Write-Host "Das Modul PSWindowsUpdate hat $cmdletCount neue Cmdlets geladen."

    # Verfügbare Updates abrufen
    Write-Host "Abfrage der verfügbaren Windows-Updates..."
    $windowsUpdates = Get-WindowsUpdate -Verbose

    if ($windowsUpdates.Count -gt 0) {
        Write-Host "Es sind $($windowsUpdates.Count) Windows-Updates verfügbar."
        Write-Output $windowsUpdates.Count
    } else {
        Write-Host "Keine Windows-Updates verfügbar."
        Write-Output 0
    }
} else {
    Write-Host "Fehler: Das PSWindowsUpdate-Modul konnte nicht geladen werden."
}

# Abschlussmeldung
Write-Host "Aktualisierte Scriptversion: 1.4"

# Laufzeit erfassen
$endTime = Get-Date
$duration = $endTime - $startTime
$minutes = [math]::Floor($duration.TotalSeconds / 60)
$seconds = $duration.TotalSeconds % 60
Write-Host "Scriptlaufzeit: $minutes Minuten und $seconds Sekunden"
