# Startzeit des Skripts
$scriptStartTime = Get-Date

Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -Scope User  -Confirm:$false | out-null

# VMware-Verbindungsdaten
$username = '{username}'
$password = '{password}'
$phase='{phase}'
$vmlist={vmNamesList}
$BypassWednesdayCheck = {BypassWednesdayCheck}  # Wird durch den Wert von BypassWednesdayCheck ersetzt

# VMware-Verbindungsdaten
$currentTime = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$snapshotDescription = "Snapshot vom $(Get-Date -Format 'dd.MM.yyyy')"

# Zabbix API Details
$zabbixServer = "192.168.116.114"
$apiToken = "b910b5ad64ac886ed834e88cb71de707fd6b1e31b5df63fc542e4ed2eb801be4"  # API Token
$zabbixApiUrl = "http://$($zabbixServer):8080/api_jsonrpc.php"
# Header f�r die Anfrage
$headers = @{
    "Authorization" = "Bearer $apiToken"
    "Content-Type"  = "application/json"
}

# Funktion: Zabbix HostID anhand des Hostnamens ermitteln
function Get-ZabbixHost {
    param (
        [string]$hostName
    )
    $body = @{
        jsonrpc = "2.0"
        method  = "host.get"
        params  = @{ filter = @{ name = $hostName } }
        id      = 1
    }
    try {
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body ($body | ConvertTo-Json -Depth 10) -Headers $headers
        if ($response.result) {
            return $response.result[0].hostid
        } else {
            Write-Error "Kein Host mit dem Namen '$hostName' gefunden."
            return $null
        }
    } catch {
        Write-Error "Fehler beim Holen des Zabbix-Hosts: $_"
        return $null
    }
}

# Funktion: Zabbix ItemID anhand des Item-Keys ermitteln
function Get-ZabbixItemId {
    param (
        [string]$hostId,
        [string]$itemKey
    )
    $body = @{
        jsonrpc = "2.0"
        method  = "item.get"
        params  = @{
            hostids = $hostId
            filter  = @{ key_ = $itemKey }
        }
        id      = 1
    }
    try {
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body ($body | ConvertTo-Json -Depth 10) -Headers $headers
        if ($response.result) {
            return $response.result[0].itemid
        } else {
            Write-Error "Kein Item mit dem Key '$itemKey' gefunden."
            return $null
        }
    } catch {
        Write-Error "Fehler beim Holen des Zabbix-Items: $_"
        return $null
    }
}

# Funktion: Zabbix Makro aktualisieren
function Update-ZabbixMacro {
    param (
        [string]$hostId,
        [string]$macroName,
        [string]$macroValue
    )
    $body = @{
        jsonrpc = "2.0"
        method  = "host.update"
        params  = @{
            hostid = $hostId
            macros  = @(
                @{
                    macro = $macroName
                    value = $macroValue
                }
            )
        }
        id      = 1
    }
    try {
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body ($body | ConvertTo-Json -Depth 10) -Headers $headers
        Write-Host "Makro erfolgreich aktualisiert: $macroName = $macroValue"
    } catch {
        Write-Error "Fehler beim Aktualisieren des Zabbix-Makros: $_"
    }
}

# Funktion: Daten an Zabbix mit history.push senden
function Push-ZabbixData {
    param (
        [string]$itemId,
        [string]$value
    )
    $timestamp = [System.DateTimeOffset]::Now.ToUnixTimeSeconds()
    $body = @{
        jsonrpc = "2.0"
        method  = "history.push"
        params  = @(
            @{
                itemid = $itemId
                clock  = $timestamp
                value  = $value
            }
        )
        id      = 1
    }
    try {
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body ($body | ConvertTo-Json -Depth 10) -Headers $headers
        Write-Host "Daten erfolgreich an Zabbix gesendet: ItemID = $itemId, Wert = $value"
    } catch {
        Write-Error "Fehler beim Senden von Daten an Zabbix: $_"
    }
}

# Überprüfe, ob heute Mittwoch nach dem zweiten Dienstag des Monats ist
if ((Is-Wednesday-After-Second-Tuesday) -or $BypassWednesdayCheck) {
    Write-Host "Snapshot wird erstellt." 
} else {
    Write-Host "Heute ist nicht der Mittwoch nach dem zweiten Dienstag des Monats und BypassWednesdayCheck ist nicht gesetzt. Snapshot wird NICHT erstellt."
    Exit
}

# Liste der VMs f�r Phase 1
$vmNamesList = $vmlist

# Erstelle Snapshots für alle VMs
foreach ($vmName in $vmNamesList) {
    $hostId = Get-ZabbixHost -hostName $vmName
    if ($hostId) {
        $itemKey = "vSphere.Snapshot.Status"
        $itemId = Get-ZabbixItemId -hostId $hostId -itemKey $itemKey

        if ($itemId) {
            $Value = "Snapshot Phase $phase WU erfolgreich"
            Push-ZabbixData -itemId $itemId -value $Value

            # Update das Makro für den Host in Zabbix
            $macroName = "SNAPSHOT_STATUS"
            $macroValue = "Snapshot für VM $vmName in Phase $phase erfolgreich erstellt."
            Update-ZabbixMacro -hostId $hostId -macroName $macroName -macroValue $macroValue
        }
    }
}

# Gesamtdauer des Skripts
$scriptEndTime = Get-Date
$totalDuration = $scriptEndTime - $scriptStartTime
Write-Host "Gesamtdauer des Skripts: $($totalDuration.TotalSeconds) Sekunden" -ForegroundColor Cyan
