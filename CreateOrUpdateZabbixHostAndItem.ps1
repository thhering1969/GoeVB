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
        method  = "apiinfo.version" # Überprüfen der API-Version als Test
        params  = @{} # Keine zusätzlichen Parameter für diese Methode
        id      = 1
    } | ConvertTo-Json

    Write-Host "Prüfe, ob das API-Token gültig ist..."

    # Zabbix-API-Aufruf mit dem Token im Header
    try {
        $headers = @{
            Authorization = "Bearer $apiToken"
        }
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body $body -ContentType "application/json" -Headers $headers
        Write-Host "API-Token ist gültig."
    } catch {
        Write-Error "Ungültiges API-Token: $($_.Exception.Message)"
    }
}

# Funktion: Host prüfen
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

    Write-Host "Sende Anfrage an Zabbix-API, um den Host zu überprüfen..."
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
                    groupid = 2  # Standardgruppe für Hosts (z. B. "Linux servers")
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

# Funktion: Alle Items löschen
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

    Write-Host "Sende Anfrage an Zabbix-API, um alle Items des Hosts zu überprüfen..."
    $headers = @{
        Authorization = "Bearer $apiToken"
    }
    $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body $body -ContentType "application/json" -Headers $headers
    
    if ($response.error) {
        throw "Fehler beim Abrufen der Items: $($response.error.data)"
    }

    $itemIds = $response.result | ForEach-Object { $_.itemid }

    if ($itemIds.Count -gt 0) {
        Write-Host "Sende Anfrage an Zabbix-API, um die Items zu löschen..."
        $deleteBody = @{
            jsonrpc = "2.0"
            method  = "item.delete"
            params  = $itemIds
            id = 1
        } | ConvertTo-Json -Depth 10

        $deleteResponse = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body $deleteBody -ContentType "application/json" -Headers $headers

        if ($deleteResponse.error) {
            throw "Fehler beim Löschen der Items: $($deleteResponse.error.data)"
        }

        Write-Host "Items wurden erfolgreich gelöscht."
    }
}

# Funktion: Alle Trigger löschen
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

    Write-Host "Sende Anfrage an Zabbix-API, um alle Trigger des Hosts zu überprüfen..."
    $headers = @{
        Authorization = "Bearer $apiToken"
    }
    $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body $body -ContentType "application/json" -Headers $headers
    
    if ($response.error) {
        throw "Fehler beim Abrufen der Trigger: $($response.error.data)"
    }

    $triggerIds = $response.result | ForEach-Object { $_.triggerid }

    if ($triggerIds.Count -gt 0) {
        Write-Host "Sende Anfrage an Zabbix-API, um die Trigger zu löschen..."
        $deleteBody = @{
            jsonrpc = "2.0"
            method  = "trigger.delete"
            params  = $triggerIds
            id = 1
        } | ConvertTo-Json -Depth 10

        $deleteResponse = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body $deleteBody -ContentType "application/json" -Headers $headers

        if ($deleteResponse.error) {
            throw "Fehler beim Löschen der Trigger: $($deleteResponse.error.data)"
        }

        Write-Host "Trigger wurden erfolgreich gelöscht."
    }
}

# Funktion: Alle Diagramme löschen
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

    Write-Host "Sende Anfrage an Zabbix-API, um alle Diagramme des Hosts zu überprüfen..."
    $headers = @{
        Authorization = "Bearer $apiToken"
    }
    $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body $body -ContentType "application/json" -Headers $headers
    
    if ($response.error) {
        throw "Fehler beim Abrufen der Diagramme: $($response.error.data)"
    }

    $graphIds = $response.result | ForEach-Object { $_.graphid }

    if ($graphIds.Count -gt 0) {
        Write-Host "Sende Anfrage an Zabbix-API, um die Diagramme zu löschen..."
        $deleteBody = @{
            jsonrpc = "2.0"
            method  = "graph.delete"
            params  = $graphIds
            id = 1
        } | ConvertTo-Json -Depth 10

        $deleteResponse = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body $deleteBody -ContentType "application/json" -Headers $headers

        if ($deleteResponse.error) {
            throw "Fehler beim Löschen der Diagramme: $($deleteResponse.error.data)"
        }

        Write-Host "Diagramme wurden erfolgreich gelöscht."
    }
}

# Funktion: Alle Suchläufe löschen
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

    Write-Host "Sende Anfrage an Zabbix-API, um alle Suchläufe des Hosts zu überprüfen..."
    $headers = @{
        Authorization = "Bearer $apiToken"
    }
    $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body $body -ContentType "application/json" -Headers $headers
    
    if ($response.error) {
        throw "Fehler beim Abrufen der Suchläufe: $($response.error.data)"
    }

    $discoveryIds = $response.result | ForEach-Object { $_.itemid }

    if ($discoveryIds.Count -gt 0) {
        Write-Host "Sende Anfrage an Zabbix-API, um die Suchläufe zu löschen..."
        $deleteBody = @{
            jsonrpc = "2.0"
            method  = "discoveryrule.delete"
            params  = $discoveryIds
            id = 1
        } | ConvertTo-Json -Depth 10

        $deleteResponse = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body $deleteBody -ContentType "application/json" -Headers $headers

        if ($deleteResponse.error) {
            throw "Fehler beim Löschen der Suchläufe: $($deleteResponse.error.data)"
        }

        Write-Host "Suchläufe wurden erfolgreich gelöscht."
    }
}

# Ausführung des Skripts
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

# Lösche alle Elemente des Hosts
Delete-ZabbixItems -apiToken $apiToken -hostId $hostId
Delete-ZabbixTriggers -apiToken $apiToken -hostId $hostId
Delete-ZabbixGraphs -apiToken $apiToken -hostId $hostId
Delete-ZabbixDiscoveries -apiToken $apiToken -hostId $hostId
