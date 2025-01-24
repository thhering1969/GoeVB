param (
    [string]$zabbixApiUrl,
    [hashtable]$headers,
    [string]$hostId
)

$body = @{
    jsonrpc = "2.0"
    method  = "hostinterface.get"
    params  = @{ output = "extend"; hostids = $hostId }
    id      = 2
} | ConvertTo-Json -Depth 3

return Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Headers $headers -Body $body
