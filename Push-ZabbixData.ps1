# Funktion: Daten an Zabbix mit history.push senden
function Push-ZabbixData {
    param (
        [string]$itemId,
        [string]$value
    )

    # Korrekte Berechnung des Unix-Zeitstempels in Sekunden
    $timestamp = [System.DateTimeOffset]::Now.ToUnixTimeSeconds()

    # Body für die Anfrage an Zabbix
    $body = @{
        jsonrpc = "2.0"
        method  = "history.push"
        params  = @(
            @{
                itemid = $itemId
                clock  = $timestamp
                value  = $value
            }
        )
        id      = 1
    }

    try {
        # Anfrage an Zabbix senden
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body ($body | ConvertTo-Json -Depth 10) -Headers $headers
        Write-Host "Daten erfolgreich an Zabbix gesendet: ItemID = $itemId, Wert = $value"
        
        # Ausgabe der Antwort von Zabbix für Debugging
        Write-Host "Antwort von Zabbix: $($response | ConvertTo-Json -Depth 10)"
    } catch {
        Write-Error "Fehler beim Senden von Daten an Zabbix: $_"
    }
}
