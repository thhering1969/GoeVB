<#
Decline-NonX64-And-Beta-Updates - robust, mit Klassifikations-Mapping und Sampling
Testen Sie immer zuerst mit -WhatIf
#>

param(
    [switch]$WhatIf = $true,
    [string[]]$Classifications = @("All"),    # akzeptierte Werte werden gemappt
    [int]$MaxUpdates = 0,                     # >0 = nur erstes N (Sampling), 0 = keine Begrenzung
    [string]$AmbiguousCsv = ".\Ambiguous-Updates.csv",
    [switch]$VerboseOutput = $true
)

function Map-Classification {
    param([string]$input)
    if (-not $input) { return "All" }
    switch -Wildcard ($input.ToLower()) {
        { $_ -match '^(security|securityupdates|securityupdate)$' } { return "Security" }
        { $_ -match '^(critical)$' } { return "Critical" }
        { $_ -match '^(wsus)$' } { return "WSUS" }
        default { return "All" }
    }
}

try {
    Import-Module UpdateServices -ErrorAction Stop
} catch {
    Write-Error ('UpdateServices-Module konnte nicht geladen werden: {0}' -f $_.Exception.Message)
    exit 1
}

# Regex (vorkompiliert)
$keepRegex = [regex]::new('(?i)\b(x64|amd64|64-?bit|x86_64)\b')
$nonX64Regex = [regex]::new('(?i)\b(x86|32-?bit|ia64|itanium|arm64|armv7|armv6|arm)\b')
# NEU: Regex für Beta, Preview und Insider Updates
$betaRegex = [regex]::new('(?i)\b(preview|beta|insider|evaluation|pre-release|prerelease)\b')

$allUpdates = @()
foreach ($c in $Classifications) {
    $mapped = Map-Classification -input $c
    if ($VerboseOutput) { Write-Host ("Mapping: '{0}' -> '{1}'" -f $c, $mapped) }
    try {
        $fetched = Get-WsusUpdate -Classification $mapped -Approval AnyExceptDeclined -Status Any
        if ($fetched) {
            if ($MaxUpdates -gt 0) {
                $allUpdates += $fetched | Select-Object -First $MaxUpdates
            } else {
                $allUpdates += $fetched
            }
        }
    } catch {
        Write-Warning ('Fehler beim Abruf der Classification {0}: {1}' -f $mapped, $_.Exception.Message)
    }
}

Write-Host ('Gefundene Updates insgesamt (nach Fetch): {0}' -f $allUpdates.Count)

# Schnelles In-Memory-Filtern
$toDecline = $allUpdates.Where({
    $t = $_.Title
    if (-not $t) { $false } else {
        # Ist es ein Beta/Preview Update?
        $isBeta = $betaRegex.IsMatch($t)
        # Ist es explizit eine falsche Architektur (und nicht x64)?
        $isExplicitNonX64 = (-not $keepRegex.IsMatch($t)) -and $nonX64Regex.IsMatch($t)
        
        # Ablehnen, wenn Beta ODER falsche Architektur
        $isBeta -or $isExplicitNonX64
    }
}, 'Default')

$ambiguous = $allUpdates.Where({
    $t = $_.Title
    if (-not $t) { $true } else {
        $isBeta = $betaRegex.IsMatch($t)
        $isExplicitX64 = $keepRegex.IsMatch($t)
        $isExplicitNonX64 = $nonX64Regex.IsMatch($t)
        
        # Ambigue ist es nur, wenn es KEIN Beta ist, KEIN x64 und KEIN Non-x64
        (-not $isBeta) -and (-not $isExplicitX64) -and (-not $isExplicitNonX64)
    }
}, 'Default')

Write-Host ('Decline-Kandidaten (Non-x64 oder Beta): {0}, Ambiguous: {1}' -f $toDecline.Count, $ambiguous.Count)

if ($ambiguous.Count -gt 0) {
    $ambiguous | Select-Object @{N='Title';E={$_.Title}}, @{N='Kb';E={($_.KbArticleIds -join ',')}}, @{N='Id';E={$_.UpdateId.Guid}}, @{N='Arrival';E={$_.ArrivalDate}} |
        Export-Csv -Path $AmbiguousCsv -NoTypeInformation -Encoding UTF8
    Write-Host ('Ambigue Einträge gespeichert in: {0}' -f $AmbiguousCsv)
}

if ($toDecline.Count -eq 0) {
    Write-Host 'Keine expliziten non-x64-Updates oder Beta-Updates zum Ablehnen gefunden.'
    exit 0
}

Write-Host ('Beginne Ablehnen von {0} Updates (WhatIf={1})' -f $toDecline.Count, $WhatIf.IsPresent)

foreach ($u in $toDecline) {
    $kb = ($u.KbArticleIds -join ',')
    $title = $u.Title
    
    # Kurze Info, warum es abgelehnt wird (fürs Log)
    if ($betaRegex.IsMatch($title)) {
        $reason = "[BETA/PREVIEW]"
    } else {
        $reason = "[NON-X64]"
    }
    
    $msg = 'Ablehnen {0}: {1} (KB: {2})' -f $reason, $title, $kb

    if ($WhatIf) {
        Write-Host ('[WhatIf] {0}' -f $msg)
        Deny-WsusUpdate -Update $u -WhatIf
    } else {
        Write-Host $msg -ForegroundColor Yellow
        try {
            Deny-WsusUpdate -Update $u -Confirm:$false
        } catch {
            Write-Warning ('Fehler beim Ablehnen: {0}' -f $_.Exception.Message)
        }
    }
}
