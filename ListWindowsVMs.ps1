# vCenter Details
$password = 'GoeVB2020,' 
$vCenterServers = @("vc1.mgmt.lan", "vc2.mgmt.lan", "vc3.mgmt.lan", "vc4.mgmt.lan")
$username = 'administrator@vsphere.local'

# Zabbix Details
$zabbixServer = "192.168.116.114"
$apiToken = "b910b5ad64ac886ed834e88cb71de707fd6b1e31b5df63fc542e4ed2eb801be4"  # API Token
$zabbixApiUrl = "http://$($zabbixServer):8080/api_jsonrpc.php"

# Header mit Content-Type auf application/json setzen
$headers = @{
    "Authorization" = "Bearer $apiToken"
    "Content-Type"  = "application/json"
}

# Verbindung zu den vCenter-Servern herstellen
Write-Host "Stelle Verbindung zu vCenter-Servern her..."

foreach ($vCenterServer in $vCenterServers) {
    try {
        Connect-VIServer -Server $vCenterServer -User $username -Password $password -ErrorAction Stop
        Write-Host "Erfolgreich mit vCenter-Server ${vCenterServer} verbunden."
    } catch {
        Write-Error "Fehler beim Verbinden mit vCenter-Server ${vCenterServer}: $_"
        exit 1
    }
}

# VMs abrufen, die Windows ausführen, "itcs" und "test" im Namen ausschließen
Write-Host "Abrufen von VMs, die Windows ausführen und Filter anwenden..."
$WindowsVMs = Get-VM | Get-View -Property @("Name", "Config.GuestFullName", "Guest.GuestFullName", "Guest.IpAddress") | 
    Where-Object { 
        $_.Config.GuestFullName -like "*Windows*" -and 
        $_.Name -notmatch "(?i)(itcs|test)" 
    } | 
    Select-Object -Property Name, 
        @{N="Configured OS";E={$_.Config.GuestFullName}}, 
        @{N="Running OS";E={$_.Guest.GuestFullName}}, 
        @{N="IP Address";E={@($_.Guest.IpAddress)}}

# Debugging-Ausgabe: Zeige alle VMs, die abgerufen wurden
Write-Host "Alle abgerufenen Windows VMs:"

#$WindowsVMs | ForEach-Object { Write-Host "Name: $($_.Name), Configured OS: $($_.'Configured OS'), Running OS: $($_.'Running OS')" }

# Doppelte VMs entfernen
$WindowsVMs = $WindowsVMs | Sort-Object -Property Name -Unique

# Debugging-Ausgabe: Zeige die gefilterten VMs nach Entfernen von Duplikaten
Write-Host "Gefilterte Windows VMs nach Entfernen von Duplikaten:"
$WindowsVMs | ForEach-Object { Write-Host "Name: $($_.Name), Configured OS: $($_.'Configured OS'), Running OS: $($_.'Running OS')" }



# Wenn keine VMs übrig sind, gibt eine Warnung aus
if ($WindowsVMs.Count -eq 0) {
    Write-Host "Warnung: Keine gefilterten Windows VMs gefunden."
} else {
    Write-Host "Gefilterte Windows VMs: $($WindowsVMs.Count)"
}

$VMs=$WindowsVMs

# WindowsVMs in 4 Phasen aufteilen
$phaseCount = 4
$vmGroups = @()
$vmCountPerPhase = [math]::Ceiling($WindowsVMs.Count / $phaseCount)



for ($i = 0; $i -lt $phaseCount; $i++) {
    $vmGroups += ,($WindowsVMs | Select-Object -First $vmCountPerPhase)
    $WindowsVMs = $WindowsVMs | Select-Object -Skip $vmCountPerPhase
}

# Zabbix Host und Items prüfen/erstellen
Write-Host "Prüfe Zabbix-Host..."
$hostName = "WindowsVMs"
$ipAddress = "127.0.0.1"

# Zabbix Host abrufen oder erstellen
function Get-ZabbixHost {
    param (
        [string]$apiToken,
        [string]$hostName
    )
    $body = @{
        jsonrpc = "2.0"
        method  = "host.get"
        params  = @{ filter = @{ host = $hostName } }
        id      = 1
    }
    try {
        Write-Host "Sende Anfrage zum Abrufen des Hosts..."
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body ($body | ConvertTo-Json -Depth 10) -Headers $headers
        Write-Host "Antwort erhalten: $($response | ConvertTo-Json)"
        return $response.result
    } catch {
        Write-Error "Fehler beim Abrufen des Hosts: $_"
        Write-Error "Response Status Code: $($_.Exception.Response.StatusCode)"
        Write-Error "Response Content: $($_.Exception.Response.Content)"
    }
}

function Create-ZabbixHost {
    param (
        [string]$apiToken,
        [string]$hostName,
        [string]$ipAddress
    )
    $body = @{
        jsonrpc = "2.0"
        method  = "host.create"
        params  = @{
            host      = $hostName
            interfaces = @(@{
                type = 1; main = 1; useip = 1; ip = $ipAddress; dns = ""; port = "10050"
            })
            groups = @(@{ groupid = 2 })  # "Linux servers" group
        }
        id = 1
    }
    try {
        Write-Host "Sende Anfrage zum Erstellen des Hosts..."
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body ($body | ConvertTo-Json -Depth 10) -Headers $headers
        Write-Host "Antwort erhalten: $($response | ConvertTo-Json)"
        Write-Host "Host wurde erfolgreich erstellt: $hostName"
    } catch {
        Write-Error "Fehler beim Erstellen des Hosts: $_"
        Write-Error "Response Status Code: $($_.Exception.Response.StatusCode)"
        Write-Error "Response Content: $($_.Exception.Response.Content)"
    }
}

$existingHost = Get-ZabbixHost -apiToken $apiToken -hostName $hostName
if (-not $existingHost) {
    Write-Host "Host nicht gefunden, erstelle Host $hostName..."
    Create-ZabbixHost -apiToken $apiToken -hostName $hostName -ipAddress $ipAddress
    $existingHost = Get-ZabbixHost -apiToken $apiToken -hostName $hostName
}

if ($existingHost -and $existingHost.Count -gt 0) {
    $hostId = $existingHost[0].hostid
} else {
    Write-Error "Konnte den Zabbix-Host nicht erstellen oder abrufen."
    exit 1
}

# Löschen vorhandener Items
function Delete-ZabbixItems {
    param ([string]$apiToken, [string]$hostId)
    $body = @{
        jsonrpc = "2.0"
        method  = "item.get"
        params  = @{ hostids = $hostId }
        id      = 1
    }
    try {
        Write-Host "Lösche vorhandene Items..."
        $items = (Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body ($body | ConvertTo-Json -Depth 10) -Headers $headers).result
        foreach ($item in $items) {
            $deleteBody = @{
                jsonrpc = "2.0"
                method  = "item.delete"
                params  = @($item.itemid)
                id      = 1
            }
            Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body ($deleteBody | ConvertTo-Json -Depth 10) -Headers $headers
        }
    } catch {
        Write-Error "Fehler beim Löschen der Items: $_"
        Write-Error "Response Status Code: $($_.Exception.Response.StatusCode)"
        Write-Error "Response Content: $($_.Exception.Response.Content)"
    }
}
Delete-ZabbixItems -apiToken $apiToken -hostId $hostId

# Items erstellen
function Create-ZabbixItem {
    param ([string]$apiToken, [string]$hostId, [string]$phaseName, [array]$vmNames)
    $body = @{
        jsonrpc = "2.0"
        method  = "item.create"
        params  = @{
            name        = "$phaseName - Windows VMs"
            key_        = "windows.vms.$($phaseName -replace ' ', '_')"
            hostid      = $hostId
            type        = 2  # Simple check
            value_type  = 4  # String
            delay       = 0
            description = "Windows VMs in ${phaseName}:`n" + ($vmNames -join "`n")
        }
        id = 1
    }
    try {
        Write-Host "Erstelle Zabbix Item für $phaseName..."
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body ($body | ConvertTo-Json -Depth 10) -Headers $headers
        Write-Host "Antwort erhalten: $($response | ConvertTo-Json)"
        Write-Host "Item wurde erfolgreich erstellt: $phaseName"
    } catch {
        Write-Error "Fehler beim Erstellen des Items: $_"
        Write-Error "Response Status Code: $($_.Exception.Response.StatusCode)"
        Write-Error "Response Content: $($_.Exception.Response.Content)"
    }
}

$phaseNames = @("Phase 1", "Phase 2", "Phase 3", "Phase 4")
for ($i = 0; $i -lt $phaseCount; $i++) {
    Create-ZabbixItem -apiToken $apiToken -hostId $hostId -phaseName $phaseNames[$i] -vmNames ($vmGroups[$i].Name)
}

# Alle gefilterten Windows VMs und ihre Anzahl anzeigen
Write-Host "Liste aller gefilterten Windows VMs:"
$VMs | ForEach-Object { Write-Host $_.Name }

# Ermittel die Anzahl der Windows VMs und gebe sie aus
Write-Host "Anzahl der gefilterten Windows VMs: $($VMs.Count)"

Write-Host "Skript abgeschlossen."
