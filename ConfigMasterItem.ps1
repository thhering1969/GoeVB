# Zabbix API Details
$zabbixServer = "192.168.116.114"
$apiToken = "b910b5ad64ac886ed834e88cb71de707fd6b1e31b5df63fc542e4ed2eb801be4"  # API Token
$zabbixApiUrl = "http://$($zabbixServer):8080/api_jsonrpc.php"

# Header f�r die Anfrage
$headers = @{
    "Authorization" = "Bearer $apiToken"
    "Content-Type"  = "application/json"
}

# Hostname des Master-Items
$hostName = "WindowsVMs"
$masterItemNamePattern = "windows.vms.Phase_"  # Flexibles Anpassungsmuster f�r Phasen

# Funktion: Abrufen der Zabbix-Host-ID
function Get-ZabbixItems {
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
        return $response.result[0].hostid
    } catch {
        Write-Error "Fehler beim Aktualisieren des Zabbix-Items $($itemId): $($_)"

    }
}
# Hostinterface abrufen
function Get-HostInterface {
    param (
        [string]$zabbixApiUrl,
        [string]$apiToken,
        [string]$hostId
    )

    $body = @{
        jsonrpc = "2.0"
        method  = "hostinterface.get"
        params  = @{
            output  = "extend"
            hostids = $hostId
        }
        
        id   = 1
    }

   #write-host $zabbixApiUrl $apiToken $hostId



    try {
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body ($body | ConvertTo-Json -Depth 10) -Headers $headers
        if ($response.result.Count -gt 0) {
            return $response.result[0].interfaceid
        } else {
            Write-Error "Keine Host-Interface-ID f�r Host-ID $hostId gefunden."
            return $null
        }
    } catch {
        Write-Error "Fehler beim Abrufen der Host-Interface-ID: $($_.Exception.Message)"
        return $null
    }
}

function Update-ZabbixItem {
    param (
        [string]$hostId,        # Zabbix-Host-ID
        [string]$itemId,        # Item-ID, die aktualisiert werden soll
        [string]$itemName,      # Neuer Item-Name
        [string]$newScriptPath, # Pfad zum neuen Skript
                $delay =  "0;md9-15wd3h9" ,       # Delay in Sekunden (Standardwert: 60)
        [int]$timeout = 30,     # Timeout in Sekunden (Standardwert: 30)
        [int]$history = 3600,     
        [int]$trends = 0,      # Trends in Tagen (Standardwert: 180)
        [int]$type = 0 
    )

    # Konstruktion des system.run-Befehls
    $escapedScriptPath = $newScriptPath.Replace("'", "''") # Escape f�r einfache Anf�hrungszeichen
    $systemRunKey = "system.run['pwsh -NoProfile -ExecutionPolicy Bypass -File $escapedScriptPath',nowait]"

    # Hole die Interface-ID vom Host
    $interfaceId = Get-HostInterface -zabbixApiUrl $zabbixApiUrl -hostId $hostId
    if (-not $interfaceId) {
        Write-Error "Abbruch: Keine g�ltige Interface-ID gefunden."
        return
    }
    
    #Write-Host "Interface-ID: $($interfaceId)"
    
    # Update-Body f�r die Zabbix-API
    $updateBody = @{
        jsonrpc = "2.0"
        method  = "item.update"
        params  = @{
            itemid        = $itemId
            key_          = $systemRunKey
            name          = $itemName
            interfaceid   = $interfaceId   # Hier die Interface-ID einf�gen
            delay         = $delay          # Delay (update_interval ersetzt durch delay)
            timeout       = $timeout        # Timeout
            history       = $history        # Verlauf in Tagen
            trends        = $trends         # Trends in Tagen
            type          = $type    
        }
        
        id      = 3
    }
    $interfaceid
    
    try {
    # JSON-Konvertierung und API-Anfrage
    $jsonBody = $updateBody | ConvertTo-Json -Depth 10 -Compress
    $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body $jsonBody -Headers $headers
    Write-Host "Zabbix-Item mit ID $($itemId) erfolgreich aktualisiert. Neues Skript: $($newScriptPath)"
    
    # Weitere Ausgabe der API-Antwort
    Write-Host "Zabbix-API Antwort: $($response | ConvertTo-Json -Depth 10)"
} catch {
    Write-Error "Fehler beim Aktualisieren des Zabbix-Items $($itemId): $($_.Exception.Message)"
}

}
# Funktion: Abrufen der Zabbix-Items basierend auf dem Host
function Get-ItemDescription {
    param (
        [string]$apiToken,
        [string]$hostId,
        [string]$itemNamePattern
    )

    $body = @{
        jsonrpc = "2.0"
        method  = "item.get"
        params  = @{
            hostids = $hostId
            search = @{
                key_ = $itemNamePattern
            }
        }
        id      = 1
    }
    
    try {
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body ($body | ConvertTo-Json -Depth 10) -Headers $headers
        return $response.result
    } catch {
        Write-Error "Fehler beim Abrufen der Items: $_"
    }
}

# Funktion: Erstellen der Snapshot-Skripte f�r jede Phase und Speicherung der itemid
function Create-SnapshotScripts {
    $snapshotScriptPathBase = "/usr/share/powershell/CreateSnapshot_Phase"
    
    # Zabbix Host-ID abrufen
    $hostId = Get-ZabbixItems -apiToken $apiToken -hostName $hostName
    if (-not $hostId) {
        Write-Error "Host nicht gefunden!"
        return
    }

    # Items f�r Phase 1-4 abrufen (mit flexiblerem Suchmuster)
    $items = Get-ItemDescription -apiToken $apiToken -hostId $hostId -itemNamePattern $masterItemNamePattern
    if ($items.Count -eq 0) {
        Write-Error "Keine Zabbix-Items gefunden, die dem Muster 'windows.vms.Phase_' entsprechen."
        return
    }

    # Hash-Tabelle f�r die Speicherung der itemid
    $phaseItemIds = @{}
    $phaseItemName = @{}


    # Initialisierung der Hash-Tabelle f�r VMs nach Phasen
    $vmNamesByPhase = @{
        1 = @()
        2 = @()
        3 = @()
        4 = @()
    }

    # Extrahieren der VM-Namen aus den Beschreibungen der Items f�r jede Phase
    foreach ($item in $items) {
        $description = $item.description
        if ($description) {
            Write-Host "Verarbeite Item: $($item.key_) mit Beschreibung: $description"
            
            # Extrahiere die Phase aus dem item.key_
            if ($item.key_ -match "windows.vms.Phase_(\d+)") {
                $phaseNumber = $matches[1]
                Write-Host "Phase $phaseNumber gefunden."
                
                # Speichern der itemid f�r diese Phase in der Hash-Tabelle
                $phaseItemIds[$phaseNumber] = $item.itemid
	        $phaseItemName[$phaseNumber] =$item.name

                # Extrahieren der VMs direkt aus der Beschreibung
                $extractedVMs = $description -split '\r?\n' | Where-Object { $_.Trim() -ne ""  -and $_ -notlike "*Windows VMs in Phase*"}

                # Hinzuf�gen der extrahierten VMs zur entsprechenden Phase
                if ($vmNamesByPhase.Keys -contains $phaseNumber) {
                    $vmNamesByPhase[$phaseNumber] += $extractedVMs
                    Write-Host "Aktualisierte VM-Liste f�r Phase $($phaseNumber): $($vmNamesByPhase[$phaseNumber] -join ', ')"  # Debugging-Ausgabe f�r die aktualisierte Liste
                }
            } else {
                Write-Warning "Phase f�r Item: $($item.key_) konnte nicht extrahiert werden."
            }
        } else {
            Write-Warning "Keine Beschreibung f�r Item: $($item.key_)"
        }
    }

    # Ausgabe der gespeicherten itemids f�r jede Phase
    Write-Host "Gespeicherte itemids f�r jede Phase:"
    $phaseItemIds.GetEnumerator() | ForEach-Object {
        Write-Host "Phase $($_.Key): $($_.Value)"
    }

    # Skriptinhalt f�r jede Phase erstellen
    $vmNamesByPhase.GetEnumerator() | ForEach-Object {
        $phase = $_.Key
        $vmNames = $_.Value

        # Sicherstellen, dass VM-Namen in den Skripten eingef�gt werden
        if ($vmNames.Count -gt 0) {
            # Erstelle die Liste der VMs im PowerShell-Skript
            $vmNamesList = $vmNames -join "','"
            $vmNamesList = "('$vmNamesList')"  # Formatierung der Liste f�r das PowerShell-Skript

            $scriptContent = @"
# VMware-Verbindungsdaten
`$username = 'administrator@vsphere.local'
`$password = 'ff,' 
`$currentTime = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss' 
`$snapshotDescription = 'Snapshot vom $(Get-Date -Format 'dd.MM.yyyy')' 

# Setzen der Variable BypassWednesdayCheck innerhalb des Skriptinhalts
`$BypassWednesdayCheck = `$false  # Dies k�nnte auch aus der �bergeordneten Funktion �bergeben werden

# Funktion: �berpr�fen, ob heute der dritte Mittwoch des Monats ist
function Is-Third-Wednesday {
    `$currentDate = Get-Date
    `$dayOfWeek = `$currentDate.DayOfWeek
    `$isWednesday = (`$dayOfWeek -eq 'Wednesday')

    Write-Host "Aktuelles Datum: `$currentDate"
    Write-Host "Ist heute Mittwoch? `$isWednesday"
    Write-Host "BypassWednesdayCheck: `$BypassWednesdayCheck"

    # Falls es Mittwoch ist und Bypass nicht gesetzt ist
    if (`$isWednesday -and -not `$BypassWednesdayCheck) {
        `$currentMonth = `$currentDate.Month
        `$currentYear = `$currentDate.Year

        # Berechnen des dritten Mittwochs
        `$thirdWednesday = (1..31 | Where-Object {
            (`$_.ToString() | Get-Date -Month `$currentMonth -Year `$currentYear -Day `$_.ToString()).DayOfWeek -eq 'Wednesday'
        }) | Where-Object { 
            `$_.ToString() -le 31 
        } | Select-Object -Skip 2 -First 1

        Write-Host "Dritter Mittwoch des Monats: `$thirdWednesday"

        # �berpr�fen, ob heute der dritte Mittwoch ist
        return (`$currentDate.Day -eq `$thirdWednesday)
    }
    return `$false
}

# �berpr�fen, ob der Snapshot erstellt werden soll (wenn dritter Mittwoch oder Bypass aktiv ist)
if ((Is-Third-Wednesday) -or `$BypassWednesdayCheck) {
    if (Is-Third-Wednesday) {
        Write-Host "Snapshot wird erstellt, da heute der dritte Mittwoch des Monats ist."
    } elseif (`$BypassWednesdayCheck) {
        Write-Host "Snapshot wird erstellt, da BypassWednesdayCheck aktiv ist."
    }
} else {
    Write-Host "Heute ist nicht der dritte Mittwoch des Monats und BypassWednesdayCheck ist nicht gesetzt. Snapshot wird NICHT erstellt."
}

function Create-Snapshot {
    param (
        [string]`$vCenterServer,
        [string]`$username,
        [string]`$password,
        [string]`$vmName,
        [string]`$snapshotDescription
    )

    # Verbindung zu vCenter herstellen
    try {
        Connect-VIServer -Server `$vCenterServer -User `$username -Password `$password -ErrorAction Stop | out-null
    } catch {
        Write-Host "Fehler bei der Verbindung zu vCenter: `$($vCenterServer)"
        return `$false
    }

    # �berpr�fen, ob die VM existiert und eingeschaltet ist
    try {
        `$vm = Get-VM -Name `$vmName -ErrorAction SilentlyContinue
        if (`$vm -and `$vm.PowerState -eq 'PoweredOn') {
            # Snapshot erstellen
            New-Snapshot -VM `$vm -Name `$snapshotDescription -Description `$snapshotDescription -Memory -Quiesce
            Write-Host "Snapshot f�r VM `$vmName wurde erfolgreich erstellt."
        } else {
            Write-Host "VM `$vmName ist nicht eingeschaltet oder nicht vorhanden."
        }
    } catch {
        Write-Host "Fehler bei der Snapshot-Erstellung f�r VM `$(`$vmName):"
    }
}
"@

            # Speichern des Skripts f�r die jeweilige Phase
            $snapshotScriptPath = "$snapshotScriptPathBase$phase.ps1"
            $scriptContent | Set-Content -Path $snapshotScriptPath
            chmod +x $snapshotScriptPath

            Write-Host "Snapshot-Skript f�r Phase $($phase) gespeichert unter: $snapshotScriptPath"
	    #Write-Host "Die itemid f�r Phase $($phase) ist: $($phaseItemIds[$phase])"
	  # Write-Host "Der itemname f�r Phase $($phase) ist: $($phaseItemName[$phase])"
           Update-ZabbixItem -hostId $hostId -itemId $phaseItemIds[$phase] -itemName $phaseItemName[$phase] -newScriptPath $snapshotScriptPath

        }
    }
}

# Aufruf der Funktion zum Erstellen der Snapshot-Skripte
Create-SnapshotScripts
#windows.vms.Phase_