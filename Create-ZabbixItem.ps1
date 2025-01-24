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

return Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Headers $headers -Body $body
