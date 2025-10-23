# WSUS Update Decline Script - Verbesserte Version
# Ablehnen von nicht-x64 Treiber-Updates

# SQL-Verbindungsparameter
$serverName = "vm2wsusdb\sqlexpress2022"
$databaseName = "susdb"
$query = @"
SELECT DISTINCT
    CAST(u.UpdateID AS nvarchar(50)) as UpdateId,
    ISNULL(u.LegacyName, 'Kein Titel') AS Title,
    dfs.OperatingSystem,
    d.Manufacturer,
    d.Provider,
    dfs.HardwareID
FROM 
    dbo.tbDriverFeatureScore dfs
    INNER JOIN dbo.tbRevision r ON dfs.RevisionID = r.RevisionID
    INNER JOIN dbo.tbUpdate u ON r.LocalUpdateID = u.LocalUpdateID
    INNER JOIN dbo.tbDriver d ON dfs.RevisionID = d.RevisionID
WHERE 
    dfs.OperatingSystem NOT LIKE '%amd64%'
    AND r.IsLatestRevision = 1
"@

# Log-Datei erstellen
$logPath = "C:\Scripts\WSUS_Decline_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

# Verbindung zur SQL-Datenbank herstellen
$connectionString = "Server=$serverName;Database=$databaseName;Integrated Security=True;"
$connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)

try {
    $connection.Open()
    Write-Host "Verbinde mit SQL Server: $serverName" -ForegroundColor Green
    Add-Content -Path $logPath -Value "$(Get-Date): Verbindung zu SQL Server $serverName hergestellt"
    
    $command = $connection.CreateCommand()
    $command.CommandText = $query
    $command.CommandTimeout = 300  # 5 Minuten Timeout

    # SQL-Ergebnisse abholen
    $reader = $command.ExecuteReader()

    # WSUS PowerShell Modul laden
    try {
        [reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
        $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer("localhost", $false, 8530)
        Write-Host "Verbinde mit WSUS Server..." -ForegroundColor Green
        Add-Content -Path $logPath -Value "$(Get-Date): Verbindung zu WSUS Server hergestellt"
    }
    catch {
        $errorMsg = "Konnte keine Verbindung zum WSUS Server herstellen: $($_.Exception.Message)"
        Write-Error $errorMsg
        Add-Content -Path $logPath -Value "$(Get-Date): FEHLER - $errorMsg"
        exit 1
    }

    # Ergebnisse durchgehen und Updates ablehnen
    $declinedCount = 0
    $errorCount = 0
    $updatesToProcess = @()

    # Erst alle Updates sammeln
    while ($reader.Read()) {
        $updateInfo = @{
            UpdateId = $reader["UpdateId"]
            Title = $reader["Title"]
            OperatingSystem = $reader["OperatingSystem"]
            Manufacturer = $reader["Manufacturer"]
            Provider = $reader["Provider"]
            HardwareID = $reader["HardwareID"]
        }
        $updatesToProcess += $updateInfo
    }

    $reader.Close()

    Write-Host "Gefundene Updates: $($updatesToProcess.Count)" -ForegroundColor Yellow
    Add-Content -Path $logPath -Value "$(Get-Date): $($updatesToProcess.Count) Updates gefunden"

    if ($updatesToProcess.Count -eq 0) {
        Write-Host "Keine Updates zum Ablehnen gefunden." -ForegroundColor Green
        Add-Content -Path $logPath -Value "$(Get-Date): Keine Updates zum Ablehnen gefunden"
        exit
    }

    # Bestätigung einholen
    Write-Host "`nMöchten Sie $($updatesToProcess.Count) ARM64-Treiber-Updates ablehnen?" -ForegroundColor Yellow
    Write-Host "Dies kann nicht rückgängig gemacht werden!" -ForegroundColor Red
    $confirm = Read-Host "Bestätigen mit 'JA' (Großschreibung)"

    if ($confirm -ne 'JA') {
        Write-Host "Abbruch durch Benutzer." -ForegroundColor Yellow
        Add-Content -Path $logPath -Value "$(Get-Date): Abbruch durch Benutzer"
        exit
    }

    # Jedes Update verarbeiten
    foreach ($updateInfo in $updatesToProcess) {
        try {
            Write-Host "Verarbeite Update: $($updateInfo.UpdateId)" -ForegroundColor Gray
            $update = $wsus.GetUpdate([Guid]$updateInfo.UpdateId)
            $update.Decline()
            
            $logMessage = "Abgelehnt: ID=$($updateInfo.UpdateId), OS=$($updateInfo.OperatingSystem), Hersteller=$($updateInfo.Manufacturer), Hardware=$($updateInfo.HardwareID)"
            Write-Host $logMessage -ForegroundColor Green
            Add-Content -Path $logPath -Value "$(Get-Date): $logMessage"
            
            $declinedCount++
            
            # Kurze Pause um WSUS nicht zu überlasten
            Start-Sleep -Milliseconds 100
        }
        catch {
            $errorMsg = "Fehler bei $($updateInfo.UpdateId): $($_.Exception.Message)"
            Write-Warning $errorMsg
            Add-Content -Path $logPath -Value "$(Get-Date): FEHLER - $errorMsg"
            $errorCount++
        }
    }

    # Zusammenfassung anzeigen
    Write-Host "`nZUSAMMENFASSUNG:" -ForegroundColor Cyan
    Write-Host "Erfolgreich abgelehnt: $declinedCount" -ForegroundColor Green
    Write-Host "Fehler: $errorCount" -ForegroundColor Red
    Write-Host "Gesamt gefunden: $($updatesToProcess.Count)" -ForegroundColor Yellow
    Write-Host "Log-Datei: $logPath" -ForegroundColor Gray
    
    Add-Content -Path $logPath -Value "$(Get-Date): ZUSAMMENFASSUNG - Erfolgreich: $declinedCount, Fehler: $errorCount, Gesamt: $($updatesToProcess.Count)"
}
catch {
    $errorMsg = "Allgemeiner Fehler: $($_.Exception.Message)"
    Write-Error $errorMsg
    Add-Content -Path $logPath -Value "$(Get-Date): ALLGEMEINER FEHLER - $errorMsg"
}
finally {
    if ($connection.State -eq 'Open') {
        $connection.Close()
        Write-Host "SQL Verbindung geschlossen." -ForegroundColor Gray
    }
}
