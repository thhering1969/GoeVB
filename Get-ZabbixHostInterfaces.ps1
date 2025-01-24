function Get-ZabbixHostInterfaces {
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

    try {
        # Anfrage an Zabbix senden
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Headers $headers -Body $body
        # Rückgabe der Antwort
        return $response.result
    } catch {
        Write-Error "Fehler beim Abfragen der Host-Interfaces von Zabbix: $_"
        return $null
    }
}
