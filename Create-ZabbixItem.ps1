function Create-ZabbixItem {
    param (
        [string]$zabbixApiUrl,
        [hashtable]$headers,
        [string]$hostId,
        [int]$interfaceId,
        [string]$name,
        [string]$itemKey,
        [string]$delay,
        [int]$timeout = 30,
        [int]$history = 3600,
        [int]$trends = 0,
        [int]$type = 0
    )

    $body = @{
        jsonrpc = "2.0"
        method  = "item.create"
        params  = @{
            name        = $name
            key_        = $itemKey
            hostid      = $hostId
            type        = $type
            value_type  = 4
            interfaceid = $interfaceId
            delay       = $delay
            timeout     = $timeout
            history     = $history
            trends      = $trends
        }
        id      = 4
    } | ConvertTo-Json -Depth 3

    try {
        # Anfrage an Zabbix senden
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Headers $headers -Body $body
        # Rückgabe der Antwort
        return $response.result
    } catch {
        Write-Error "Fehler beim Erstellen des Zabbix-Items: $_"
        return $null
    }
}
