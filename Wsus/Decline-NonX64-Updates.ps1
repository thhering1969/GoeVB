<#
.SYNOPSIS
    Hybrid-WSUS-Decline V4: Jetzt mit dem korrekten Microsoft-Spaltennamen 'DefaultTitle'
#>

param(
    [string]$ServerInstance = "VM2WSUSDB\SQLEXPRESS2022",
    [string]$Database = "SUSDB",
    [switch]$WhatIf = $true 
)

# 1. Verbindung zum WSUS-Dienst
Write-Host "[1/4] Verbinde mit WSUS-API..." -ForegroundColor Cyan
$wsus = Get-WsusServer

# 2. SQL-Abfrage (Der magische Spaltenname ist 'DefaultTitle')
Write-Host "[2/4] SQL-Abfrage: Lade Update-Titel aus der Datenbank..." -ForegroundColor Cyan
$SQLQuery = "SELECT UpdateId, DefaultTitle FROM public_views.vUpdate WHERE IsDeclined = 0"

try {
    $allUpdates = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -Query $SQLQuery -TrustServerCertificate -ErrorAction Stop
} catch {
    Write-Error "SQL-Abfrage fehlgeschlagen: $($_.Exception.Message)"
    exit
}

Write-Host "--> SQL hat $($allUpdates.Count) aktive Updates gemeldet." -ForegroundColor Green

# 3. Filterung im RAM
Write-Host "[3/4] Filtere auf x86, ARM, Preview, Beta..." -ForegroundColor Cyan
$regex = "(?i)\b(x86|32-bit|Preview|Beta|Insider|Itanium|ARM|ARM64|Pre-Release)\b"

# Wir greifen auf DefaultTitle zu!
$toDecline = $allUpdates | Where-Object { $_.DefaultTitle -match $regex }

Write-Host "--> Treffer gefunden: $($toDecline.Count)" -ForegroundColor Yellow

if ($toDecline.Count -eq 0) {
    Write-Host "Keine passenden Updates zum Ablehnen gefunden." -ForegroundColor Green
    exit
}

# 4. Gezieltes Ablehnen
Write-Host "[4/4] Starte Ablehnung (Modus: $(if($WhatIf){'VORSCHAU'}else{'ECHT'}))" -ForegroundColor Cyan
$count = 0
$total = $toDecline.Count

foreach ($item in $toDecline) {
    $count++
    $percent = [int](($count / $total) * 100)
    
    Write-Progress -Activity "Lehne Updates ab" -Status "Update $count von $total ($percent%)" -PercentComplete $percent -CurrentOperation "$($item.DefaultTitle)"

    if ($WhatIf) {
        Write-Host "[WhatIf] Würde ablehnen: $($item.DefaultTitle)" -ForegroundColor Gray
    } else {
        try {
            $u = $wsus.GetUpdate([Guid]$item.UpdateId)
            $u.Decline()
            Write-Host "ABGELEHNT: $($item.DefaultTitle)" -ForegroundColor Yellow
        } catch {
            Write-Warning "Fehler bei Update $($item.UpdateId): $($_.Exception.Message)"
        }
    }
}

Write-Progress -Activity "Lehne Updates ab" -Completed
Write-Host "`n--- FERTIG ---" -ForegroundColor Green