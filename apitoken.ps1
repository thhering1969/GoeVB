
$apiToken = "b910b5ad64ac886ed834e88cb71de707fd6b1e31b5df63fc542e4ed2eb801be4"
# API-Server-URL und Token
$zabbixServer = "192.168.116.114"

$zabbixApiUrl = "http://$($zabbixServer):8080/api_jsonrpc.php"

# Funktion: Teste das API-Token
function Test-ZabbixToken {
    param (
        [string]$apiToken
    )
    $body = @{
        jsonrpc = "2.0"
        method  = "apiinfo.version" # �berpr�fen der API-Version als Test
        params  = @{} # Keine zus�tzlichen Parameter f�r diese Methode
        id      = 1
    } | ConvertTo-Json

    Write-Host "Pr�fe, ob das API-Token g�ltig ist..."

    # Zabbix-API-Aufruf mit dem Token im Header
    try {
        $headers = @{
            Authorization = "Bearer $apiToken"
        }
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body $body -ContentType "application/json" -Headers $headers
        Write-Host "API-Token ist g�ltig."
    } catch {
        Write-Error "Ung�ltiges API-Token: $($_.Exception.Message)"
    }
}

# Teste das API-Token
Test-ZabbixToken -apiToken $apiToken

# Host �berpr�fen
$hostName = "WindowsVMs"
$body = @{
    jsonrpc = "2.0"
    method  = "host.get"
    params  = @{
        filter = @{
            host = $hostName
        }
    }
    id   = 1
} | ConvertTo-Json

$headers = @{
    Authorization = "Bearer $apiToken"
}

$response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body $body -ContentType "application/json" -Headers $headers

if ($response.error) {
    Write-Host "Fehler: $($response.error.data)"
} else {
    Write-Host "Host-Informationen: $($response.result)"
}
