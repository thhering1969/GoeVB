param (
    [string]$zabbixApiUrl,
    [hashtable]$headers,
    [string]$hostName
)

$body = @{
    jsonrpc = "2.0"
    method  = "host.get"
    params  = @{ filter = @{ name = $hostName } }
    id      = 1
} | ConvertTo-Json -Depth 3

return Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Headers $headers -Body $body
