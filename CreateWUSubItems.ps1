# Zabbix API Details
$zabbixServer = "192.168.116.114"
$apiToken = "b910b5ad64ac886ed834e88cb71de707fd6b1e31b5df63fc542e4ed2eb801be4"  # API Token
$zabbixApiUrl = "http://$($zabbixServer):8080/api_jsonrpc.php"

# Header f�r die Anfrage
$headers = @{
    "Authorization" = "Bearer $apiToken"
    "Content-Type"  = "application/json"
}

# Hostname
$hostName = "WindowsVMs"

# Funktion zum Abrufen des Zabbix Hosts
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
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body ($body | ConvertTo-Json -Depth 10) -Headers $headers
        return $response.result
    } catch {
        Write-Error "Fehler beim Abrufen des Hosts: $_"
    }
}

# Funktion zum Abrufen von Items eines Hosts
function Get-ZabbixItems {
    param (
        [string]$apiToken,
        [string]$hostId
    )
    $body = @{
        jsonrpc = "2.0"
        method  = "item.get"
        params  = @{ hostids = $hostId }
        id      = 1
    }
    try {
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body ($body | ConvertTo-Json -Depth 10) -Headers $headers
        return $response.result
    } catch {
        Write-Error "Fehler beim Abrufen der Items: $_"
    }
}

# Funktion zum Erstellen eines Abh�ngigen Items
function Create-DependentItem {
    param (
        [string]$apiToken,
        [string]$hostId,
        [string]$masterItemId,
        [string]$phaseNumber,
        [string]$vmName
    )

    # Format des Phase-Namens f�r den Key (z.B. WUPhase1-TN_Data2)
    $key = "WUPhase$phaseNumber-$vmName"
    
    # Body f�r das Erstellen eines abh�ngigen Items
    $body = @{
        jsonrpc = "2.0"
        method  = "item.create"
        params  = @{
            hostid          = $hostId
            name            = "$vmName"  # Nur der Name der VM, kein Phase-Text mehr
            key_            = $key   # Key, der f�r das Subitem einzigartig sein muss
            type            = 18                   # Dependent item type
            master_itemid   = $masterItemId       # ID des Master-Items
            value_type      = 4                    # Text/String (Text) als Datentyp
        }
        id = 1
    }

    Write-Host "Sende Anfrage zum Erstellen eines abh�ngigen Items f�r VM: $vmName"
    Write-Host ($body | ConvertTo-Json -Depth 10)

    try {
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body ($body | ConvertTo-Json -Depth 10) -Headers $headers
        if ($response.result) {
            Write-Host "Abh�ngiges Item erfolgreich erstellt: $vmName"
        } else {
            Write-Host "Fehler beim Erstellen des abh�ngigen Items: $($response.error.message)"
        }
    } catch {
        Write-Error "Fehler beim Erstellen des abh�ngigen Items: $_"
    }
}

# Funktion zum Extrahieren der VM-Namen aus der Beschreibung des Master-Items
function Extract-VMsFromMasterItem {
    param (
        [string]$description
    )

    # Suche nach den VM-Namen
    $vmNames = @()

    # Bereinige die Beschreibung, entferne �berfl�ssige Leerzeichen und Zeilenumbr�che
    $description = $description -replace "\r|\n", " "  # Entferne Zeilenumbr�che
    $description = $description.Trim()                 # Entferne f�hrende und nachfolgende Leerzeichen

    # Extrahiere den Text nach "Windows VMs in Phase X:" und hol dir die VM-Namen
    if ($description -match "Windows VMs in Phase \d:(.*)") {
        # Den extrahierten Text f�r VM-Namen durch neue Zeilen trennen
        $vmList = $matches[1] -split "\s+"  # Trenne den Text in einzelne W�rter (Zeilenumbr�che und Leerzeichen werden zu einem Space)
        
        # Entferne alle leeren Eintr�ge
        $vmNames = $vmList | Where-Object { $_.Trim() -ne "" }
    }

    return $vmNames
}

# Abrufen des Hosts und der Items
$existingHost = Get-ZabbixHost -apiToken $apiToken -hostName $hostName
if (-not $existingHost) {
    Write-Error "Host nicht gefunden!"
    exit 1
}

$hostId = $existingHost[0].hostid

# Abrufen der Items des Hosts
$items = Get-ZabbixItems -apiToken $apiToken -hostId $hostId
Write-Host "Anzahl der Items des Hosts: $($items.Count)"

# Suche nach den Master-Items (z.B. Phase 1 bis Phase 9)
$masterItems = $items | Where-Object { $_.name -match "Phase [1-9]" }

if ($masterItems.Count -gt 0) {
    foreach ($masterItem in $masterItems) {
        $masterItemId = $masterItem.itemid
        Write-Host "Gefundenes Master-Item: $($masterItem.name) mit ID: $masterItemId"

        # Abrufen der Beschreibung des Master-Items aus Zabbix
        $bodyDescription = @{
            jsonrpc = "2.0"
            method  = "item.get"
            params  = @{
                itemids = $masterItemId
            }
            id = 1
        }

        try {
            $descriptionResponse = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body ($bodyDescription | ConvertTo-Json -Depth 10) -Headers $headers
            $masterItemDescription = $descriptionResponse.result[0].description
        } catch {
            Write-Error "Fehler beim Abrufen der Beschreibung des Master-Items: $_"
            continue
        }

        # Extrahieren der VM-Namen
        $vmNames = Extract-VMsFromMasterItem -description $masterItemDescription
        Write-Host "Gefundene VMs: $($vmNames -join ', ')"

        # Extrahieren der Phase-Nummer aus dem Master-Item-Name
        if ($masterItem.name -match "Phase (\d)") {
            $phaseNumber = $matches[1]
        } else {
            Write-Host "Fehler beim Extrahieren der Phase-Nummer aus dem Master-Item-Namen"
            continue
        }

        # F�r jede VM ein abh�ngiges Item erstellen
        foreach ($vmName in $vmNames) {
            Create-DependentItem -apiToken $apiToken -hostId $hostId -masterItemId $masterItemId -phaseNumber $phaseNumber -vmName $vmName
        }
    }
} else {
    Write-Error "Keine Master-Items f�r Phase 1 bis Phase 9 gefunden!"
}
