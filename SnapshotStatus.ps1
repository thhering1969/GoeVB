# Zabbix API Details
$zabbixServer = "192.168.116.114"
$apiToken = "b910b5ad64ac886ed834e88cb71de707fd6b1e31b5df63fc542e4ed2eb801be4"  # API Token
$zabbixApiUrl = "http://$($zabbixServer):8080/api_jsonrpc.php"

# Header für die Anfrage
$headers = @{
    "Authorization" = "Bearer $apiToken"
    "Content-Type"  = "application/json"
}

# Hostname des Hosts, dessen HostID ermittelt werden soll
$zabbixHost = (Get-WmiObject Win32_ComputerSystem).Name

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

    # Korrekte Berechnung des Unix-Zeitstempels in Sekunden
    $timestamp = [System.DateTimeOffset]::Now.ToUnixTimeSeconds()

    # Body für die Anfrage an Zabbix
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
        # Anfrage an Zabbix senden
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body ($body | ConvertTo-Json -Depth 10) -Headers $headers
        Write-Host "Daten erfolgreich an Zabbix gesendet: ItemID = $itemId, Wert = $value"
        
        # Ausgabe der Antwort von Zabbix für Debugging
        Write-Host "Antwort von Zabbix: $($response | ConvertTo-Json -Depth 10)"
    } catch {
        Write-Error "Fehler beim Senden von Daten an Zabbix: $_"
    }
}

# Hauptablauf

Write-Host "Ermittle die HostID für den Host '$zabbixHost'..."
$hostId = Get-ZabbixHost -hostName $zabbixHost

if ($hostId) {
    Write-Host "HostID für '$zabbixHost': $hostId"
} else {
    Write-Host "Host konnte nicht ermittelt werden."
    exit
}

Write-Host "Ermittle die ItemID für das Item mit dem Key 'vSphere.Snapshot.Status'..."
$itemKey = "vSphere.Snapshot.Status"
$itemId = Get-ZabbixItemId -hostId $hostId -itemKey $itemKey

if ($itemId) {
    Write-Host "ItemID für '$itemKey' auf Host '$zabbixHost': $itemId"
} else {
    Write-Host "ItemID konnte nicht ermittelt werden."
    exit
}

# Daten an Zabbix senden (Testdaten)
$testValue = "Snapshot erfolgreich"
Push-ZabbixData -itemId $itemId -value $testValue
