# Zabbix-Server Details
$zabbixServer = "192.168.116.114"
$apiToken = "b910b5ad64ac886ed834e88cb71de707fd6b1e31b5df63fc542e4ed2eb801be4" # API Token

# URL zur Zabbix-API mit Port
$zabbixApiUrl = "http://$($zabbixServer):8080/api_jsonrpc.php"

# Funktion: Status des Trapper-Items abfragen und max Alter des Snapshots prüfen
function Get-ZabbixTrapperStatus {
    param (
        [string]$hostName,     # Zabbix-Host
        [string]$itemKey,      # Zabbix-Item-Schlüssel
        [int]$maxAgeInHours = 12 # Maximaler Alterswert in Stunden für den Snapshot
    )
    
    # Zabbix API Payload für die Anfrage
    $payload = @{
        jsonrpc = "2.0"
        auth = $apiToken
        method = "item.get"
        params = @{
            output = "extend"
            filter = @{
                key_ = $itemKey
                host = $hostName
            }
        }
        id = 1
    } | ConvertTo-Json
    
    # Zabbix API Request
    try {
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method POST -ContentType "application/json" -Body $payload
        if ($response.result.Count -eq 0) {
            Write-Host "ZBX_NOTSUPPORTED: Unknown metric $itemKey"
        } else {
            $status = $response.result[0].lastvalue
            Write-Host "Letzter erfolgreicher Snapshot: $status"

            # Prüfung des Alters des Snapshots
            if ($null -ne $response.result[0].lastclock) {
                $snapshotTimestamp = [datetime]::FromFileTimeUtc($response.result[0].lastclock)
                $currentTimestamp = [datetime]::UtcNow
                $age = ($currentTimestamp - $snapshotTimestamp).TotalHours

                if ($age > $maxAgeInHours) {
                    Write-Host "Der Snapshot ist älter als $maxAgeInHours Stunden. Zeit zum Handeln!"
                } else {
                    Write-Host "Der Snapshot ist noch nicht älter als $maxAgeInHours Stunden."
                }
            } else {
                Write-Host "Kein gültiges Datum für den Snapshot gefunden."
            }
        }
    } catch {
        Write-Error "Fehler beim Aufrufen der Zabbix-API: $_"
    }
}

# Hauptablauf
$itemKey = "vSphere.Snapshot.Status"  # Ersetze mit dem tatsächlichen Item-Schlüssel
$hostName = "VMWSUSDB"  # Ersetze mit dem tatsächlichen Hostnamen oder der IP-Adresse
Write-Host "Prüfe den Status für das Trapper-Item '$itemKey' auf dem Host '$hostName'..."
Get-ZabbixTrapperStatus -hostName $hostName -itemKey $itemKey
