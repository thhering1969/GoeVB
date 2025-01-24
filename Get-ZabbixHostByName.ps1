function Get-ZabbixHostByName {
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

    try {
        # Anfrage an Zabbix senden
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Headers $headers -Body $body
        # Überprüfen, ob ein Ergebnis zurückgegeben wurde
        if ($response.result -and $response.result.Count -gt 0) {
            return $response.result[0]
        } else {
            Write-Error "Kein Host mit dem Namen '$hostName' gefunden."
            return $null
        }
    } catch {
        Write-Error "Fehler beim Abfragen von Zabbix: $_"
        return $null
    }
}
