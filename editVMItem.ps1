# Zabbix Server-Konfiguration
$zabbixServer = "192.168.116.114"  # Deine Zabbix-Server-Adresse
$apiToken = "b910b5ad64ac886ed834e88cb71de707fd6b1e31b5df63fc542e4ed2eb801be4"  # API-Token
$zabbixApiUrl = "http://$($zabbixServer):8080/api_jsonrpc.php"

# Header für API-Anfragen
$headers = @{
    "Content-Type" = "application/json"
    "Authorization" = "Bearer $apiToken"
}

# Zabbix API-Funktion: Host-Abfrage
function Get-ZabbixHost {
    param (
        [string]$hostName
    )
    $body = @{
        jsonrpc = "2.0"
        method = "host.get"
        params = @{
            filter = @{
                name = $hostName
            }
        }
        id = 1
    } | ConvertTo-Json

    return Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Headers $headers -Body $body
}

# Zabbix API-Funktion: Interface-Abfrage
function Get-ZabbixHostInterfaces {
    param (
        [string]$hostId
    )
    $body = @{
        jsonrpc = "2.0"
        method = "hostinterface.get"
        params = @{
            output  = "extend"
            hostids = $hostId
        }
        id = 2
    } | ConvertTo-Json

    return Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Headers $headers -Body $body
}

# Zabbix API-Funktion: Item-Abfrage
function Get-ZabbixItems {
    param (
        [string]$hostId,
        [string]$itemKeyPrefix
    )
    $body = @{
        jsonrpc = "2.0"
        method = "item.get"
        params = @{
            hostids = $hostId
            search = @{
                key_ = $itemKeyPrefix
            }
            limit = 1  # Nur das erste Item zurückgeben
        }
        id = 3
    } | ConvertTo-Json

    return Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Headers $headers -Body $body
}

# Funktion zur Ausgabe der Interface-Details
function Display-Interfaces {
    param (
        [array]$interfaces
    )
    $interfaces | ForEach-Object {
        Write-Host "Interface-ID: $($_.interfaceid), IP: $($_.ip), DNS: $($_.dns), Type: $($_.type)"
    }
}

# Zabbix API-Funktion: Item-Erstellung
function Create-ZabbixItem {
    param (
        [string]$hostId,
        [int]$interfaceId,
        [string]$name,
        [string]$itemkey,
        [string]$delay,
        [int]$timeout = 30,
        [int]$history = 3600,
        [int]$trends = 0,
        [int]$type = 0  # Zabbix Agent
    )
    $body = @{
        jsonrpc = "2.0"
        method = "item.create"
        params = @{
            name        = $name
            key_        = $itemkey
            hostid      = $hostId
            type        = $type  # Zabbix Agent
            value_type  = 4  # Text
            interfaceid = $interfaceId
            delay       = $delay
            timeout     = $timeout
            history     = $history
            trends      = $trends
        }
        id = 4
    } | ConvertTo-Json

    return Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Headers $headers -Body $body
}

# Hauptlogik
$hostName = "WindowsVMs"  # Festgelegter Hostname
$itemKeyPrefix = "WUPhase"

# Hole den Host mit dem angegebenen Namen und erhalte die Host-ID
$hostResponse = Get-ZabbixHost -hostName $hostName
$hostItem = $hostResponse.result[0]

if ($null -eq $hostItem) {
    Write-Host "Host mit dem Namen '$hostName' wurde nicht gefunden."
    exit
}

$hostId = $hostItem.hostid
Write-Host "Gefundene Host-ID: $hostId"

# Hole alle Interfaces des Hosts und gebe deren Interface-ID aus
$interfacesResponse = Get-ZabbixHostInterfaces -hostId $hostId
if ($null -eq $interfacesResponse.result) {
    Write-Host "Keine Interfaces für den Host '$hostName' gefunden."
    exit
}

Write-Host "Verfügbare Interfaces für Host '$hostName':"
Display-Interfaces $interfacesResponse.result

# Hole die Items des Hosts basierend auf dem Item-Präfix
$itemsResponse = Get-ZabbixItems -hostId $hostId -itemKeyPrefix $itemKeyPrefix
$item = $itemsResponse.result[0]

if ($null -eq $item) {
    Write-Host "Kein Item mit dem Schlüssel '$itemKeyPrefix' für den Host '$hostName' gefunden."
    exit
}

Write-Host "Gefundenes Item:"
Write-Host "Name: $($item.name)"
Write-Host "Key: $($item.key_)"
Write-Host "Host-ID: $($item.hostid)"
Write-Host "Item-ID: $($item.itemid)"

# Extrahiere den Hostnamen aus dem Item-Name (z. B. 'MDC1')
$hostNameFromItem = $item.name
Write-Host "Der Hostname aus dem Item-Name: $hostNameFromItem"

# Hole den Host basierend auf dem Hostnamen aus dem Item-Name
$hostFromItemResponse = Get-ZabbixHost -hostname $hostNameFromItem
$hostFromItem = $hostFromItemResponse.result[0]

if ($null -eq $hostFromItem) {
    Write-Host "Kein Host mit dem Namen '$hostNameFromItem' gefunden."
    exit
}

$hostIdFromItem = $hostFromItem.hostid
Write-Host "Gefundene Host-ID basierend auf Item-Name: $hostIdFromItem"
Write-Host "Gefundener Host basierend auf Item-Name: $($hostFromItem.host)"

# Hole alle Interfaces des Hosts basierend auf dem Hostnamen aus Item-Name
$interfacesFromItemResponse = Get-ZabbixHostInterfaces -hostId $hostIdFromItem
if ($null -eq $interfacesFromItemResponse.result) {
    Write-Host "Keine Interfaces für den Host '$($hostFromItem.host)' gefunden."
    exit
}

Write-Host "Verfügbare Interfaces für Host '$($hostFromItem.host)':"
$interfaceId = $interfacesFromItemResponse.result[0].interfaceid
Write-Host "Verwendete Interface-ID: $interfaceId"


# Zabbix-Item erstellen
$itemName = "Execute PowerShell Test"
# Achte darauf, dass der system.run-Befehl korrekt formatiert ist
$itemKey = "system.run[powershell -NoProfile -Command Write-Host ""test""]"
$delay = "0;md8-14wd3h9m15"
$timeout = 30
$history = 3600
$trends = 0
$type = 0  # Zabbix Agent

Write-Host "Erstelle ein neues Zabbix-Item mit benutzerdefiniertem Delay..."
$itemCreateResponse = Create-ZabbixItem -hostId $hostIdFromItem -interfaceId $interfaceId -name $itemName -itemkey $itemKey -delay $delay


# Überprüfen, ob Fehler aufgetreten sind
if ($itemCreateResponse.error) {
    Write-Host "Fehler bei der Erstellung des Items: $($itemCreateResponse.error.data)"
    exit
}

Write-Host "Zabbix-Item erfolgreich erstellt:"
Write-Host "Name: $itemName"
Write-Host "Key: $itemKey"
Write-Host "Delay: $delay"
Write-Host "Timeout: $timeout"
Write-Host "History: $history"
Write-Host "Trends: $trends"
Write-Host "Type: $type"
