# Zabbix-Server Details
$zabbixServer = "192.168.116.114"
$apiToken = "b910b5ad64ac886ed834e88cb71de707fd6b1e31b5df63fc542e4ed2eb801be4" # API Token
$zabbixApiUrl = "http://$($zabbixServer):8080/api_jsonrpc.php"

# Funktion: API-Token validieren
function Test-ZabbixToken {
    param (
        [string]$apiToken
    )
    $body = @{
        jsonrpc = "2.0"
        method  = "apiinfo.version" # �berpr�fen der API-Version als Test
        params  = @{} # Keine zus�tzlichen Parameter f�r diese Methode
        id      = 1
    } | ConvertTo-Json

    Write-Host "Pr�fe, ob das API-Token g�ltig ist..."

    # Zabbix-API-Aufruf mit dem Token im Header
    try {
        $headers = @{
            Authorization = "Bearer $apiToken"
        }
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body $body -ContentType "application/json" -Headers $headers
        Write-Host "API-Token ist g�ltig."
    } catch {
        Write-Error "Ung�ltiges API-Token: $($_.Exception.Message)"
    }
}

# Funktion: Host pr�fen
function Get-ZabbixHost {
    param (
        [string]$apiToken,
        [string]$hostName
    )
    $body = @{
        jsonrpc = "2.0"
        method  = "host.get"
        params  = @{
            filter = @{
                host = $hostName
            }
        }
        id   = 1
    } | ConvertTo-Json -Depth 10

    Write-Host "Sende Anfrage an Zabbix-API, um den Host zu �berpr�fen..."
    $headers = @{
        Authorization = "Bearer $apiToken"
    }
    $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body $body -ContentType "application/json" -Headers $headers
    if ($response.error) {
        throw "Fehler beim Abrufen des Hosts: $($response.error.data)"
    }
    return $response.result
}

# Funktion: Host erstellen
function Create-ZabbixHost {
    param (
        [string]$apiToken,
        [string]$hostName,
        [string]$ipAddress
    )

    $body = @{
        jsonrpc = "2.0"
        method  = "host.create"
        params  = @{
            host = $hostName
            interfaces = @(
                @{
                    type = 1
                    main = 1
                    useip = 1
                    ip = $ipAddress
                    dns = ""
                    port = "10050"
                }
            )
            groups = @(
                @{
                    groupid = 2  # Standardgruppe f�r Hosts (z. B. "Linux servers")
                }
            )
            tags = @(
                @{
                    tag = "type"
                    value = "Windows"
                }
            )
        }
        id   = 1
    } | ConvertTo-Json -Depth 10

    Write-Host "Sende Anfrage an Zabbix-API, um den Host zu erstellen..."
    $headers = @{
        Authorization = "Bearer $apiToken"
    }
    $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body $body -ContentType "application/json" -Headers $headers
    
    if ($response.error) {
        throw "Fehler beim Erstellen des Hosts: $($response.error.data)"
    }

    Write-Host "Host wurde erfolgreich erstellt: $hostName"
    return $response.result.hostids[0]
}

# Funktion: Alle Items l�schen
function Delete-ZabbixItems {
    param (
        [string]$apiToken,
        [string]$hostId
    )

    $body = @{
        jsonrpc = "2.0"
        method  = "item.get"
        params  = @{
            hostids = $hostId
        }
        id = 1
    } | ConvertTo-Json -Depth 10

    Write-Host "Sende Anfrage an Zabbix-API, um alle Items des Hosts zu �berpr�fen..."
    $headers = @{
        Authorization = "Bearer $apiToken"
    }
    $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body $body -ContentType "application/json" -Headers $headers
    
    if ($response.error) {
        throw "Fehler beim Abrufen der Items: $($response.error.data)"
    }

    $itemIds = $response.result | ForEach-Object { $_.itemid }

    if ($itemIds.Count -gt 0) {
        Write-Host "Sende Anfrage an Zabbix-API, um die Items zu l�schen..."
        $deleteBody = @{
            jsonrpc = "2.0"
            method  = "item.delete"
            params  = $itemIds
            id = 1
        } | ConvertTo-Json -Depth 10

        $deleteResponse = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body $deleteBody -ContentType "application/json" -Headers $headers

        if ($deleteResponse.error) {
            throw "Fehler beim L�schen der Items: $($deleteResponse.error.data)"
        }

        Write-Host "Items wurden erfolgreich gel�scht."
    }
}

# Funktion: Alle Trigger l�schen
function Delete-ZabbixTriggers {
    param (
        [string]$apiToken,
        [string]$hostId
    )

    $body = @{
        jsonrpc = "2.0"
        method  = "trigger.get"
        params  = @{
            hostids = $hostId
        }
        id = 1
    } | ConvertTo-Json -Depth 10

    Write-Host "Sende Anfrage an Zabbix-API, um alle Trigger des Hosts zu �berpr�fen..."
    $headers = @{
        Authorization = "Bearer $apiToken"
    }
    $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body $body -ContentType "application/json" -Headers $headers
    
    if ($response.error) {
        throw "Fehler beim Abrufen der Trigger: $($response.error.data)"
    }

    $triggerIds = $response.result | ForEach-Object { $_.triggerid }

    if ($triggerIds.Count -gt 0) {
        Write-Host "Sende Anfrage an Zabbix-API, um die Trigger zu l�schen..."
        $deleteBody = @{
            jsonrpc = "2.0"
            method  = "trigger.delete"
            params  = $triggerIds
            id = 1
        } | ConvertTo-Json -Depth 10

        $deleteResponse = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body $deleteBody -ContentType "application/json" -Headers $headers

        if ($deleteResponse.error) {
            throw "Fehler beim L�schen der Trigger: $($deleteResponse.error.data)"
        }

        Write-Host "Trigger wurden erfolgreich gel�scht."
    }
}

# Funktion: Alle Diagramme l�schen
function Delete-ZabbixGraphs {
    param (
        [string]$apiToken,
        [string]$hostId
    )

    $body = @{
        jsonrpc = "2.0"
        method  = "graph.get"
        params  = @{
            hostids = $hostId
        }
        id = 1
    } | ConvertTo-Json -Depth 10

    Write-Host "Sende Anfrage an Zabbix-API, um alle Diagramme des Hosts zu �berpr�fen..."
    $headers = @{
        Authorization = "Bearer $apiToken"
    }
    $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body $body -ContentType "application/json" -Headers $headers
    
    if ($response.error) {
        throw "Fehler beim Abrufen der Diagramme: $($response.error.data)"
    }

    $graphIds = $response.result | ForEach-Object { $_.graphid }

    if ($graphIds.Count -gt 0) {
        Write-Host "Sende Anfrage an Zabbix-API, um die Diagramme zu l�schen..."
        $deleteBody = @{
            jsonrpc = "2.0"
            method  = "graph.delete"
            params  = $graphIds
            id = 1
        } | ConvertTo-Json -Depth 10

        $deleteResponse = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body $deleteBody -ContentType "application/json" -Headers $headers

        if ($deleteResponse.error) {
            throw "Fehler beim L�schen der Diagramme: $($deleteResponse.error.data)"
        }

        Write-Host "Diagramme wurden erfolgreich gel�scht."
    }
}

# Funktion: Alle Suchl�ufe l�schen
function Delete-ZabbixDiscoveries {
    param (
        [string]$apiToken,
        [string]$hostId
    )

    $body = @{
        jsonrpc = "2.0"
        method  = "discoveryrule.get"
        params  = @{
            hostids = $hostId
        }
        id = 1
    } | ConvertTo-Json -Depth 10

    Write-Host "Sende Anfrage an Zabbix-API, um alle Suchl�ufe des Hosts zu �berpr�fen..."
    $headers = @{
        Authorization = "Bearer $apiToken"
    }
    $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body $body -ContentType "application/json" -Headers $headers
    
    if ($response.error) {
        throw "Fehler beim Abrufen der Suchl�ufe: $($response.error.data)"
    }

    $discoveryIds = $response.result | ForEach-Object { $_.itemid }

    if ($discoveryIds.Count -gt 0) {
        Write-Host "Sende Anfrage an Zabbix-API, um die Suchl�ufe zu l�schen..."
        $deleteBody = @{
            jsonrpc = "2.0"
            method  = "discoveryrule.delete"
            params  = $discoveryIds
            id = 1
        } | ConvertTo-Json -Depth 10

        $deleteResponse = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body $deleteBody -ContentType "application/json" -Headers $headers

        if ($deleteResponse.error) {
            throw "Fehler beim L�schen der Suchl�ufe: $($deleteResponse.error.data)"
        }

        Write-Host "Suchl�ufe wurden erfolgreich gel�scht."
    }
}

# Ausf�hrung des Skripts
Test-ZabbixToken -apiToken $apiToken

# Hostname und IP-Adresse des Hosts
$hostName = "WindowsVMs"
$ipAddress = "192.168.116.114"

# Versuche, den Host zu erhalten
$hostInfo = Get-ZabbixHost -apiToken $apiToken -hostName $hostName

# Wenn der Host nicht existiert, erstelle ihn
if (-not $hostInfo) {
    Write-Host "Host nicht gefunden. Erstelle neuen Host: $hostName"
    $hostId = Create-ZabbixHost -apiToken $apiToken -hostName $hostName -ipAddress $ipAddress
} else {
    $hostId = $hostInfo[0].hostid
    Write-Host "Host gefunden: $hostName"
}

# L�sche alle Elemente des Hosts
Delete-ZabbixItems -apiToken $apiToken -hostId $hostId
Delete-ZabbixTriggers -apiToken $apiToken -hostId $hostId
Delete-ZabbixGraphs -apiToken $apiToken -hostId $hostId
Delete-ZabbixDiscoveries -apiToken $apiToken -hostId $hostId
