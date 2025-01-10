# Zabbix API Details
$zabbixServer = "192.168.116.114"
$apiToken = "b910b5ad64ac886ed834e88cb71de707fd6b1e31b5df63fc542e4ed2eb801be4"  # API Token
$zabbixApiUrl = "http://$($zabbixServer):8080/api_jsonrpc.php"

# Header für die Anfrage
$headers = @{
    "Authorization" = "Bearer $apiToken"
    "Content-Type"  = "application/json"
}

# Hostname des Master-Items
$hostName = "WindowsVMs"
$masterItemNamePattern = "Phase"  # Flexibles Anpassungsmuster für Phasen

# VMware-Verbindungsdaten
$username = 'administrator@vsphere.local'
$password = 'ff,'  # Passwort
$currentTime = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$snapshotDescription = "Snapshot vom $(Get-Date -Format 'dd.MM.yyyy')"

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

# Funktion: Erstellen der Snapshot-Skripte für jede Phase
function Create-SnapshotScripts {
    $snapshotScriptPathBase = "/usr/share/powershell/CreateSnapshot_Phase"

    # Zabbix Host-ID abrufen
    $hostId = Get-ZabbixItems -apiToken $apiToken -hostName $hostName
    if (-not $hostId) {
        Write-Error "Host nicht gefunden!"
        return
    }

    # Items für Phase 1-4 abrufen (mit flexiblerem Suchmuster)
    $items = Get-ItemDescription -apiToken $apiToken -hostId $hostId -itemNamePattern $masterItemNamePattern

    if ($items.Count -eq 0) {
        Write-Error "Keine Zabbix-Items gefunden, die dem Muster 'Phase' entsprechen. Verfügbare Items:"
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

    # Initialisierung der Hash-Tabelle für VMs nach Phasen
    $vmNamesByPhase = @{
        1 = @()
        2 = @()
        3 = @()
        4 = @()
    }

    # Extrahieren der VM-Namen aus den Beschreibungen der Items für jede Phase
    foreach ($item in $items) {
        $description = $item.description
        if ($description) {
            Write-Host "Verarbeite Item: $($item.name) mit Beschreibung: $description"
            $phaseNumber = if ($item.name -match "Phase (\d+)") { $matches[1] }
            if ($phaseNumber) {
                Write-Host "Schlüssel für Phase $phaseNumber vorhanden, VMs hinzufügen."
                # Extrahieren der VMs direkt aus der Beschreibung
                $extractedVMs = $description -split '\r?\n' | Where-Object { $_.Trim() -ne ""  -and $_ -notlike "*Windows VMs in Phase*"}

                # Hinzufügen der extrahierten VMs zur entsprechenden Phase
                if ($vmNamesByPhase.Keys -contains $phaseNumber) {
                    $vmNamesByPhase[$phaseNumber] += $extractedVMs
                    Write-Host "Aktualisierte VM-Liste für Phase $($phaseNumber): $($vmNamesByPhase[$phaseNumber] -join ', ')"  # Debugging-Ausgabe für die aktualisierte Liste
                }
            } else {
                Write-Warning "Phase für Item: $($item.name) konnte nicht extrahiert werden."
            }
        } else {
            Write-Warning "Keine Beschreibung für Item: $($item.name)"
        }
    }

    # Debugging-Ausgabe der Hash-Tabelle $vmNamesByPhase
    Write-Host "VMs nach Phasen:"
    $vmNamesByPhase.GetEnumerator() | ForEach-Object {
        Write-Host "Phase $($_.Key): $($_.Value -join ', ')"
    }

    # Skriptinhalt für jede Phase erstellen
    $vmNamesByPhase.GetEnumerator() | ForEach-Object {
        $phase = $_.Key
        $vmNames = $_.Value

        # Sicherstellen, dass VM-Namen in den Skripten eingefügt werden
        if ($vmNames.Count -gt 0) {
            # Erstelle die Liste der VMs im PowerShell-Skript
            $vmNamesList = $vmNames -join "','"
            $vmNamesList = "('$vmNamesList')"  # Formatierung der Liste für das PowerShell-Skript

            $scriptContent = @"
# VMware-Verbindungsdaten
`$username = '$username'
`$password = '$password'
`$currentTime = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
`$snapshotDescription = "Snapshot vom `$(Get-Date -Format 'dd.MM.yyyy')" 

function Create-Snapshot {
    param (
        [string]`$vCenterServer,
        [string]`$username,
        [string]`$password,
        [string]`$vmName,
        [string]`$snapshotDescription
    )

    # Verbindung zu vCenter herstellen
    try {
        Connect-VIServer -Server `$vCenterServer -User `$username -Password `$password -ErrorAction Stop
    } catch {
        Write-Host "Fehler bei der Verbindung zu vCenter\: `$vCenterServer"
        return `$false
    }

    # Überprüfen, ob die VM existiert
    try {
        `$vm = Get-VM -Name `$vmName -ErrorAction Stop
        if (`$vm) {
            # Snapshot erstellen
            New-Snapshot -VM `$vm -Name "Phase $phase `$(Get-Date -Format 'dd.MM.yyyy HH:mm')" -Description `$snapshotDescription
            Write-Host "Snapshot erfolgreich für VM `$vmName auf `$vCenterServer."
            return `$true
        } else {
            Write-Host "VM `$vmName wurde auf `$vCenterServer nicht gefunden. Kein Snapshot erstellt."
            return `$false
        }
    } catch {
        Write-Host "Fehler beim Erstellen des Snapshots für VM `$vmName auf `$vCenterServer\: `$(`$_.Exception.Message)"
        return `$false
    }
}

# Liste der VMs für Phase $phase
`$vmNamesList = @$vmNamesList

# Liste der vCenter-Server für Phase $phase
`$vCenterServers = @(
    'vc1.mgmt.lan', 
    'vc2.mgmt.lan', 
    'vc3.mgmt.lan', 
    'vc4.mgmt.lan'
)

# Snapshots für alle VMs der Phase $phase erstellen
foreach (`$vmName in `$vmNamesList) {
    Write-Host "Erstelle Snapshot für VM: `$vmName"

    `$snapshotCreated = `$false

    foreach (`$vCenterServer in `$vCenterServers) {
        if (Create-Snapshot -vCenterServer `$vCenterServer -username `$username -password `$password -vmName `$vmName -snapshotDescription `$snapshotDescription) {
            `$snapshotCreated = `$true
            break  # Beende die Schleife, wenn der Snapshot erfolgreich erstellt wurde
        }
    }

    if (-not `$snapshotCreated) {
        Write-Host "Snapshot konnte für VM `$vmName nicht erstellt werden."
    }
}
"@

            # Speichern des Skripts für die jeweilige Phase
            $snapshotScriptPath = "$snapshotScriptPathBase$phase.ps1"
            $scriptContent | Set-Content -Path $snapshotScriptPath
            Write-Host "Snapshot-Skript für Phase $($phase) gespeichert unter: $snapshotScriptPath"
        }
    }
}

# Hauptaufruf der Funktion
Create-SnapshotScripts
