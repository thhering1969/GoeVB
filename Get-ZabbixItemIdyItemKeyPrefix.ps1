# Get-ZabbixItemIdyItemKeyPrefix.ps1
function Get-ZabbixItemIdbyItemKeyPrefix {
    param (
        [string]$zabbixApiUrl,
        [hashtable]$headers,
        [string]$hostId,
        [string]$itemKeyPrefix
    )

    # Eingabewerte validieren
    if (-not $zabbixApiUrl -or -not $hostId -or -not $itemKeyPrefix) {
        Write-Error "Fehlende notwendige Parameter: Zabbix-API-URL, HostID oder ItemKeyPrefix."
        return $null
    }

    $body = @{
        jsonrpc = "2.0"
        method  = "item.get"
        params  = @{ hostids = $hostId; search = @{ key_ = $itemKeyPrefix }; limit = 1 }
        id      = 3
    } | ConvertTo-Json -Depth 3

    try {
        # Anfrage an Zabbix senden
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Headers $headers -Body $body
        # Überprüfen, ob ein Ergebnis zurückgegeben wurde
        if ($response.result -and $response.result.Count -gt 0) {
            return $response.result[0].itemid
        } else {
            Write-Error "Kein Zabbix-Item mit dem angegebenen Key gefunden."
            return $null
        }
    } catch {
        Write-Error "Fehler beim Abfragen von Zabbix: $_"
        return $null
    }
}
