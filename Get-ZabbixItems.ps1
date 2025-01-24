param (
    [string]$zabbixApiUrl,
    [hashtable]$headers,
    [string]$hostId,
    [string]$itemKeyPrefix
)

$body = @{
    jsonrpc = "2.0"
    method  = "item.get"
    params  = @{ hostids = $hostId; search = @{ key_ = $itemKeyPrefix }; limit = 1 }
    id      = 3
} | ConvertTo-Json -Depth 3

return Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Headers $headers -Body $body
