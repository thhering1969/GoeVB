# VMware-Verbindungsdaten
$username = '{username}'
$password = '{password}'
$phase='{phase}'
$vmlist={vmNamesList}
$BypassWednesdayCheck = {BypassWednesdayCheck}  # Wird durch den Wert von BypassWednesdayCheck ersetzt


# VMware-Verbindungsdaten

$currentTime = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$snapshotDescription = "Snapshot vom $(Get-Date -Format 'dd.MM.yyyy')"

# Setzen der Variable BypassWednesdayCheck
$BypassWednesdayCheck = $True  # Wird durch den Wert von BypassWednesdayCheck ersetzt

# Zabbix API Details
$zabbixServer = "192.168.116.114"
$apiToken = "b910b5ad64ac886ed834e88cb71de707fd6b1e31b5df63fc542e4ed2eb801be4"  # API Token
$zabbixApiUrl = "http://$($zabbixServer):8080/api_jsonrpc.php"

# Header für die Anfrage
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

# Funktion: Snapshot erstellen
function Create-Snapshot {
    param (
        [string]$vCenterServer,
        [string]$username,
        [string]$password,
        [string]$vmName,
        [string]$snapshotDescription
    )
    try {
        Connect-VIServer -Server $vCenterServer -User $username -Password $password -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "Fehler bei der Verbindung zu vCenter: $vCenterServer für VM: $vmName" -ForegroundColor Red
        return $false
    }
    try {
        $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
        if ($vm -and $vm.PowerState -eq 'PoweredOn') {
            New-Snapshot -VM $vm -Name "Phase $phase $(Get-Date -Format 'dd.MM.yyyy HH:mm')" -Description $snapshotDescription | Out-Null
            Write-Host "Snapshot erfolgreich für VM $vmName auf $vCenterServer."
            return $true
        } elseif ($vm) {
            Write-Host "VM $vmName ist nicht eingeschaltet. Kein Snapshot erstellt."
            return $false
        } else {
            Write-Host "VM $vmName wurde auf $vCenterServer nicht gefunden. Kein Snapshot erstellt."
            return $false
        }
    } catch {
        Write-Host "Fehler beim Erstellen des Snapshots für VM $vmName auf $($vCenterServer): $($_.Exception.Message)"
        return $false
    }
}

# Funktion: Beschreibung eines Zabbix Items ändern
function Update-ZabbixItemDescription {
    param (
        [string]$newDescription,
        [string]$vmName
    )
    $hostName = "WindowsVMs"  # Der Hostname bleibt immer gleich
    $itemKey = "WUPhase1-$vmName"
    
    # HostID für den Host "WindowsVMs" holen
    $hostId = Get-ZabbixHost -hostName $hostName
    if ($hostId) {
        # ItemID für den Key "WUPhase1-$vmName" holen
        $itemId = Get-ZabbixItemId -hostId $hostId -itemKey $itemKey
        if ($itemId) {
            $body = @{
                jsonrpc = "2.0"
                method  = "item.update"
                params  = @{
                    itemid      = $itemId
                    description = $newDescription
                }
                id = 1
            }
            try {
                $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body ($body | ConvertTo-Json -Depth 10) -Headers $headers
                Write-Host "Item-Beschreibung erfolgreich aktualisiert: $newDescription"
            } catch {
                Write-Error "Fehler beim Aktualisieren der Item-Beschreibung: $_"
            }
        }
    }
}


# Liste der VMs für Phase 1
$vmNamesList = $vmlist

# Liste der vCenter-Server für Phase 1
$vCenterServers = @(
    'vc1.mgmt.lan',
    'vc2.mgmt.lan',
    'vc3.mgmt.lan',
    'vc4.mgmt.lan'
)

# Snapshots für alle VMs erstellen
foreach ($vmName in $vmNamesList) {
    Write-Host "Starte Verarbeitung für VM: $vmName" -ForegroundColor Yellow

    $snapshotCreated = $false

    foreach ($vCenterServer in $vCenterServers) {
        Write-Host "Verbinde mit vCenter: $vCenterServer für VM: $vmName" -ForegroundColor Cyan
        if (Create-Snapshot -vCenterServer $vCenterServer -username $username -password $password -vmName $vmName -snapshotDescription $snapshotDescription) {
            $snapshotCreated = $true

            
            $hostId = Get-ZabbixHost -hostName $vmName


            if ($hostId) {
                Write-Host "HostID für 'WindowsVMs': $hostId"
            } else {
                Write-Host "Host konnte nicht ermittelt werden."
                exit
            }

            # Der ursprüngliche Teil bleibt unverändert:
            $itemKey = "vSphere.Snapshot.Status"
            $itemId = Get-ZabbixItemId -hostId $hostId -itemKey $itemKey

            if ($itemId) {
                Write-Host "ItemID für '$itemKey' auf Host '$vmName': $itemId"
            } else {
                Write-Host "ItemID konnte nicht ermittelt werden."
                exit
            }

            $Value = "Snapshot Phase $phase WU erfolgreich"
            Push-ZabbixData -itemId $itemId -value $Value

            # Optional: Wenn der Snapshot erfolgreich war, die Zabbix-Beschreibung aktualisieren
            $newDescription = "Snapshot für Phase $phase WU am $(Get-Date -Format 'dd.MM.yyyy') um $(Get-Date -Format 'HH:mm') erfolgreich"
            Update-ZabbixItemDescription -newDescription $newDescription -vmName $vmName

            break
        }
    }

    if (-not $snapshotCreated) {
        Write-Host "Snapshot konnte für VM $vmName nicht erstellt werden." -ForegroundColor Red
    }
}

