# Zabbix API Details
$zabbixServer = "192.168.116.114"
$apiToken = "b910b5ad64ac886ed834e88cb71de707fd6b1e31b5df63fc542e4ed2eb801be4"  # API Token
$zabbixApiUrl = "http://$($zabbixServer):8080/api_jsonrpc.php"

# Header f�r die Anfrage
$headers = @{
    "Authorization" = "Bearer $apiToken"
    "Content-Type"  = "application/json"
}

# Hostname des Master-Items
$hostName = "WindowsVMs"
$masterItemNamePattern = "Phase"  # Flexibles Anpassungsmuster f�r Phasen

# VMware-Verbindungsdaten
$username = 'administrator@vsphere.local'
$password = 'ff,'  # Passwort
$currentTime = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$snapshotDescription = "Snapshot vom $(Get-Date -Format 'dd.MM.yyyy')"

# Ersetzen der Variablen f�r BypassWednesdayCheck
$BypassWednesdayCheck = $true  # Beispielwert (�ndern je nach Bedarf)

# Funktion: Abrufen des Zabbix-Items
function Get-ZabbixItems {
    param (
        [string]$apiToken,
        [string]$hostName
    )
    
    $body = @{
        jsonrpc = "2.0"
        method  = "host.get"
        params  = @{ filter = @{ host = $hostName } }
        id      = 1
    }
    try {
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body ($body | ConvertTo-Json -Depth 10) -Headers $headers
        return $response.result[0].hostid
    } catch {
        Write-Error "Fehler beim Abrufen des Hosts: $_"
    }
}

function Get-ItemDescription {
    param (
        [string]$apiToken,
        [string]$hostId,
        [string]$itemNamePattern
    )

    $body = @{
        jsonrpc = "2.0"
        method  = "item.get"
        params  = @{
            hostids = $hostId
            search = @{
                name = $itemNamePattern
            }
        }
        id      = 1
    }
    try {
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body ($body | ConvertTo-Json -Depth 10) -Headers $headers
        return $response.result
    } catch {
        Write-Error "Fehler beim Abrufen der Items: $_"
    }
}

# Funktion: Erstellen der Snapshot-Skripte f�r jede Phase
function Create-SnapshotScripts {
    $templatePath = "/usr/share/powershell/Templates/SnapshotTemplate.ps1"

    # Zabbix Host-ID abrufen
    $hostId = Get-ZabbixItems -apiToken $apiToken -hostName $hostName
    if (-not $hostId) {
        Write-Error "Host nicht gefunden!"
        return
    }

    # Items f�r Phase 1-4 abrufen (mit flexiblerem Suchmuster)
    $items = Get-ItemDescription -apiToken $apiToken -hostId $hostId -itemNamePattern $masterItemNamePattern

    if ($items.Count -eq 0) {
        Write-Error "Keine Zabbix-Items gefunden, die dem Muster 'Phase' entsprechen. Verf�gbare Items:"
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body (@{
            jsonrpc = "2.0"
            method  = "item.get"
            params  = @{
                hostids = $hostId
            }
            id      = 1
        } | ConvertTo-Json -Depth 10) -Headers $headers
        Write-Host "Gefundene Items: $($response.result | ForEach-Object { $_.name })"
        return
    }

    # Initialisierung der Hash-Tabelle f�r VMs nach Phasen
    $vmNamesByPhase = @{
        1 = @()
        2 = @()
        3 = @()
        4 = @()
    }

    # Extrahieren der VM-Namen aus den Beschreibungen der Items f�r jede Phase
    foreach ($item in $items) {
        $description = $item.description
        if ($description) {
            Write-Host "Verarbeite Item: $($item.name) mit Beschreibung: $description"
            $phaseNumber = if ($item.name -match "Phase (\d+)") { $matches[1] }
            if ($phaseNumber) {
                Write-Host "Schl�ssel f�r Phase $phaseNumber vorhanden, VMs hinzuf�gen."
                # Extrahieren der VMs direkt aus der Beschreibung
                $extractedVMs = $description -split '\r?\n' | Where-Object { $_.Trim() -ne ""  -and $_ -notlike "*Windows VMs in Phase*"}

                # Hinzuf�gen der extrahierten VMs zur entsprechenden Phase
                if ($vmNamesByPhase.Keys -contains $phaseNumber) {
                    $vmNamesByPhase[$phaseNumber] += $extractedVMs
                    Write-Host "Aktualisierte VM-Liste f�r Phase $($phaseNumber): $($vmNamesByPhase[$phaseNumber] -join ', ')"  # Debugging-Ausgabe f�r die aktualisierte Liste
                }
            } else {
                Write-Warning "Phase f�r Item: $($item.name) konnte nicht extrahiert werden."
            }
        } else {
            Write-Warning "Keine Beschreibung f�r Item: $($item.name)"
        }
    }

    # Debugging-Ausgabe der Hash-Tabelle $vmNamesByPhase
    Write-Host "VMs nach Phasen:"
    $vmNamesByPhase.GetEnumerator() | ForEach-Object {
        Write-Host "Phase $($_.Key): $($_.Value -join ', ')"
    }

    # Skriptinhalt f�r jede Phase erstellen
    $vmNamesByPhase.GetEnumerator() | ForEach-Object {
        $phase = $_.Key
        $vmNames = $_.Value

        # Sicherstellen, dass VM-Namen in den Skripten eingef�gt werden
        if ($vmNames.Count -gt 0) {
            # Erstelle die Liste der VMs im PowerShell-Skript
            $vmNamesList = $vmNames -join "','"
            $vmNamesList = "('$vmNamesList')"  # Formatierung der Liste f�r das PowerShell-Skript

            # Template-Inhalt aus der externen Datei lesen und mit den Parametern f�llen
            $scriptContent = Get-Content -Path $templatePath -Raw
            $scriptContent = $scriptContent -replace '{phase}', $phase
            $scriptContent = $scriptContent -replace '{vmNamesList}', $vmNamesList
            $scriptContent = $scriptContent -replace '{snapshotDescription}', $snapshotDescription
            $scriptContent = $scriptContent -replace '{username}', $username
            $scriptContent = $scriptContent -replace '{password}', $password
            $scriptContent = $scriptContent -replace '{BypassWednesdayCheck}',("$"+$BypassWednesdayCheck.ToString())


            # Speichern des Skripts f�r die jeweilige Phase
            $snapshotScriptPath = "/usr/share/powershell/CreateSnapshot_Phase$phase.ps1"
            $scriptContent | Set-Content -Path $snapshotScriptPath
            Write-Host "Snapshot-Skript f�r Phase $($phase) gespeichert unter: $snapshotScriptPath"
        }
    }
}

# Hauptaufruf der Funktion
Create-SnapshotScripts
