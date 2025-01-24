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
