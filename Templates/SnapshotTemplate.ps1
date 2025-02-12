# Startzeit des Skripts
$scriptStartTime = Get-Date

[System.Console]::OutputEncoding = [System.Text.Encoding]::UTF8


Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -Scope User  -Confirm:$false | out-null




# VMware-Verbindungsdaten
$username = '{username}'
$password = '{password}'
$phase='{phase}'
$vmlist={vmNamesList}
$BypassWednesdayCheck = {BypassWednesdayCheck}  # Wird durch den Wert von BypassWednesdayCheck ersetzt


# VMware-Verbindungsdaten

$currentTime = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$snapshotDescription = "Snapshot vom $(Get-Date -Format 'dd.MM.yyyy')"

# Zabbix API Details
$zabbixServer = "192.168.116.114"
$apiToken = "b910b5ad64ac886ed834e88cb71de707fd6b1e31b5df63fc542e4ed2eb801be4"  # API Token
$zabbixApiUrl = "http://$($zabbixServer):8080/api_jsonrpc.php"

# Header für die Anfrage
$headers = @{
    "Authorization" = "Bearer $apiToken"
    "Content-Type"  = "application/json"
}


function Is-Wednesday-After-Second-Tuesday {
    $currentDate = Get-Date
    $dayOfWeek = $currentDate.DayOfWeek
    $isWednesday = ($dayOfWeek -eq 'Wednesday')

    #Write-Host "Aktuelles Datum: $currentDate"
    #Write-Host "Ist heute Mittwoch? $isWednesday"
    #Write-Host "BypassWednesdayCheck: $BypassWednesdayCheck"

    # Falls es Mittwoch ist und Bypass nicht gesetzt ist
    if ($isWednesday -and -not $BypassWednesdayCheck) {
        $currentMonth = $currentDate.Month
        $currentYear = $currentDate.Year

        # Berechnen des zweiten Dienstags
        $secondTuesday = (1..31 | Where-Object {
            $date = Get-Date -Month $currentMonth -Year $currentYear -Day $_
            $date.DayOfWeek -eq 'Tuesday'
        }) | Select-Object -First 2 | Select-Object -Last 1

        # Sicherstellen, dass der zweite Dienstag gefunden wurde
        if ($secondTuesday -eq $null) {
            Write-Host "Kein zweiter Dienstag im Monat gefunden."
            return $false
        }

        # Berechnen des Mittwochs nach dem zweiten Dienstag
        $wednesdayAfterSecondTuesday = (Get-Date -Month $currentMonth -Year $currentYear -Day $secondTuesday).AddDays(1)

        #Write-Host "Mittwoch nach dem zweiten Dienstag des Monats: $wednesdayAfterSecondTuesday"

        # Überprüfen, ob heute dieser Mittwoch ist
        return ($currentDate.Date -eq $wednesdayAfterSecondTuesday.Date)
    }
    return $false
}



# Funktion: Zabbix HostID anhand des Hostnamens ermitteln
function Get-ZabbixHost {
    param (
        [string]$hostName
    )
    $body = @{
        jsonrpc = "2.0"
        method  = "host.get"
        params  = @{ filter = @{ name = $hostName } }
        id      = 1
    }
    try {
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body ($body | ConvertTo-Json -Depth 10) -Headers $headers
        if ($response.result) {
            return $response.result[0].hostid
        } else {
            Write-Error "Kein Host mit dem Namen '$hostName' gefunden."
            return $null
        }
    } catch {
        Write-Error "Fehler beim Holen des Zabbix-Hosts: $_"
        return $null
    }
}

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

function Update-ZabbixMacro {
    param (
        [string]$hostId,
        [string]$macroName,
        [string]$macroValue
    )
    
    # Hole die aktuellen Makros des Hosts
    $body = @{
        jsonrpc = "2.0"
        method  = "host.get"
        params  = @{
            hostids = $hostId
            selectMacros = "extend"  # Holen aller Makros des Hosts
        }
        id      = 1
    }
    
    try {
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body ($body | ConvertTo-Json -Depth 10) -Headers $headers
        $currentMacros = $response.result[0].macros
    } catch {
        Write-Error "Fehler beim Abrufen der Makros des Hosts: $_"
        return
    }
    
    # Finde das Makro, das aktualisiert werden soll
    $existingMacro = $currentMacros | Where-Object { $_.macro -eq $macroName }
    
    if ($existingMacro) {
        # Wenn das Makro existiert, aktualisiere es
        $existingMacro.value = $macroValue
    } else {
        # Andernfalls erstelle ein neues Makro
        $currentMacros += @{ macro = $macroName; value = $macroValue }
    }

    # Baue die endgültigen Makros für den Update-Request
    $updatedMacros = $currentMacros | ForEach-Object {
        @{
            macro = $_.macro
            value = $_.value
        }
    }
    
    # Update die Makros mit den neuen Werten
    $body = @{
        jsonrpc = "2.0"
        method  = "host.update"
        params  = @{
            hostid = $hostId
            macros  = $updatedMacros
        }
        id      = 1
    }
    
    try {
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body ($body | ConvertTo-Json -Depth 10) -Headers $headers
        Write-Host "Makro erfolgreich aktualisiert: $macroName = $macroValue"
    } catch {
        Write-Error "Fehler beim Aktualisieren des Zabbix-Makros: $_"
    }
}

# Funktion: Daten an Zabbix mit history.push senden
function Push-ZabbixData {
    param (
        [string]$itemId,
        [string]$value
    )
    $timestamp = [System.DateTimeOffset]::Now.ToUnixTimeSeconds()
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
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body ($body | ConvertTo-Json -Depth 10) -Headers $headers
        #Write-Host "Daten erfolgreich an Zabbix gesendet: ItemID = $itemId, Wert = $value"
    } catch {
        Write-Error "Fehler beim Senden von Daten an Zabbix: $_"
    }
}

function Update-ZabbixItemPreprocessing {
    param (
        [string]$ZabbixUrl,        # Die URL des Zabbix-Servers
        [string]$AuthToken,        # Dein Authentifizierungstoken
        
        [string]$Regex             # Der Regex-Ausdruck
    )
    $itemKey = "WUPhase$phase-$vmName"
    $hostName = "WindowsVMs" 
   
    # HostID für den Host "WindowsVMs" holen
    $hostId = Get-ZabbixHost -hostName $hostName
    if ($hostId) {
        # ItemID für den Key der aktuellen Phase holen
        $itemId = Get-ZabbixItemId -hostId $hostId -itemKey $itemKey

    # JSON-Body für den API-Aufruf
    $Body = @{
        jsonrpc   = "2.0"
        method    = "item.update"
        params    = @{
            itemid      = $ItemId
            preprocessing = @(
                @{
                    type         = 5  
                    params       =  $RegEx
                    error_handler = 0  # Keine Fehlerbehandlung
                }
            )
        }
        
        id        = 1
    } 

    try {
        # API-Aufruf durchführen
        $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body ($body | ConvertTo-Json -Depth 10) -Headers $headers


        # Antwort anzeigen
        return $response
    } catch {
        Write-Error "Fehler beim Update des Zabbix-Items: $_"
    }
}
}

# Funktion: Snapshot erstellen
function Create-Snapshot {
    param (
        [string]$vCenterServer,
        [string]$username,
        [string]$password,
        [string]$vmName,
        [string]$snapshotDescription
    )
    try {
        Connect-VIServer -Server $vCenterServer -User $username -Password $password -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "Fehler bei der Verbindung zu vCenter: $vCenterServer f$($ue)r VM: $vmName" -ForegroundColor Red
        return $false
    }
    try {
        $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
        if ($vm -and $vm.PowerState -eq 'PoweredOn') {
            #New-Snapshot -VM $vm -Name "Phase $phase $(Get-Date -Format 'dd.MM.yyyy HH:mm')" -Description $snapshotDescription | Out-Null
            Write-Host "Snapshot erfolgreich für VM $vmName auf $vCenterServer."
            return $true
        } elseif ($vm) {
            Write-Host "VM $vmName ist nicht eingeschaltet. Kein Snapshot erstellt."
            return $false
        } else {
            Write-Host "VM $vmName wurde auf $vCenterServer nicht gefunden. Kein Snapshot erstellt."
            return $false
        }
    } catch {
        Write-Host "Fehler beim Erstellen des Snapshots für VM $vmName auf $($vCenterServer): $($_.Exception.Message)"
        return $false
    }
}

# Funktion: Beschreibung eines Zabbix Items ï¿½ndern
function Update-ZabbixItemDescription {
    param (
        [string]$newDescription,
        [string]$vmName
    )
    $hostName = "WindowsVMs"  # Der Hostname bleibt immer gleich
    $itemKey = "WUPhase$phase-$vmName"
    
    # HostID für den Host "WindowsVMs" holen
    $hostId = Get-ZabbixHost -hostName $hostName
    if ($hostId) {
        # ItemID für den Key der aktuellen Phase holen
        $itemId = Get-ZabbixItemId -hostId $hostId -itemKey $itemKey
        if ($itemId) {
            $body = @{
                jsonrpc = "2.0"
                method  = "item.update"
                params  = @{
                    itemid      = $itemId
                    description = $newDescription
                }
                id = 1
            }
            try {
                $response = Invoke-RestMethod -Uri $zabbixApiUrl -Method Post -Body ($body | ConvertTo-Json -Depth 10) -Headers $headers
                #Write-Host "Item-Beschreibung erfolgreich aktualisiert: $newDescription"
            } catch {
                Write-Error "Fehler beim Aktualisieren der Item-Beschreibung: $_"
            }
        }
    }
}

if ((Is-Wednesday-After-Second-Tuesday) -or $BypassWednesdayCheck) {
    if (Is-Wednesday-After-Second-Tuesday) {
       # Write-Host "Snapshot wird erstellt, da heute der Mittwoch nach dem zweiten Dienstag des Monats ist."
    } elseif ($BypassWednesdayCheck) {
       # Write-Host "Snapshot wird erstellt, da BypassWednesdayCheck aktiv ist."
    }
} else {
    Write-Host "Heute ist nicht der Mittwoch nach dem zweiten Dienstag des Monats und BypassWednesdayCheck ist nicht gesetzt. Snapshot wird NICHT erstellt."
    Exit
}


# Liste der VMs für Phase 
$vmNamesList = $vmlist

# Liste der vCenter-Server fï¿½r Phase 
$vCenterServers = @(
    'vc1.mgmt.lan',
    'vc2.mgmt.lan',
    'vc3.mgmt.lan',
    'vc4.mgmt.lan'
)

# Snapshots für alle VMs erstellen
foreach ($vmName in $vmNamesList) {
    Write-Host "Starte Verarbeitung für VM: $vmName" -ForegroundColor Yellow

    $snapshotCreated = $false

    foreach ($vCenterServer in $vCenterServers) {
        Write-Host "Verbinde mit vCenter: $vCenterServer für VM: $vmName" -ForegroundColor Cyan
        if (Create-Snapshot -vCenterServer $vCenterServer -username $username -password $password -vmName $vmName -snapshotDescription $snapshotDescription) {
            $snapshotCreated = $true

            
            $hostId = Get-ZabbixHost -hostName $vmName


            if ($hostId) {
              
            } else {
                Write-Host "Host konnte nicht ermittelt werden."
                
            }

            # Der ursprüngliche Teil bleibt unverändert:
            $itemKey = "vSphere.Snapshot.Status"
            $itemId = Get-ZabbixItemId -hostId $hostId -itemKey $itemKey

            if ($itemId) {
                #Write-Host "ItemID für '$itemKey' auf Host '$vmName': $itemId"
            } else {
                Write-Host "ItemID konnte nicht ermittelt werden."
                
            }

            $Value = "Snapshot Phase $phase WU erfolgreich"
            Push-ZabbixData -itemId $itemId -value $Value
            # Update das Makro für den Host in Zabbix
            $macroName = "{`$VSPHERE_SNAPSHOT_STATUS}"
            $macroValue = "Snapshot für VM $vmName in Phase $phase erfolgreich am $(Get-Date -Format 'dd.MM.yyyy') erstellt."
            write-host $hostId $macroName
            Update-ZabbixMacro -hostId $hostId -macroName $macroName -macroValue $macroValue

            # Optional: Wenn der Snapshot erfolgreich war, die Zabbix-Beschreibung aktualisieren
            $newDescription = "Snapshot für Phase $phase WU am $(Get-Date -Format 'dd.MM.yyyy') um $(Get-Date -Format 'HH:mm') erfolgreich"
            Update-ZabbixItemDescription -newDescription $newDescription -vmName $vmName
	    $Regex = ".*Snapshot erfolgreich f.r VM $vmName auf \S+\.\S+.*"+[char]10+"\0"

	
	    $response = Update-ZabbixItemPreprocessing -ZabbixUrl $zabbixApiUrl -AuthToken $apiToken -Regex $Regex

		# Antwort anzeigen
	    #Write-Host "Antwort von Zabbix: $($response | ConvertTo-Json -Depth 4)"

            break
        }
    }

    if (-not $snapshotCreated) {
        Write-Host "Snapshot konnte für VM $vmName nicht erstellt werden." -ForegroundColor Red
    }
}

# Gesamtdauer des Skripts
$scriptEndTime = Get-Date
$totalDuration = $scriptEndTime - $scriptStartTime
Write-Host "Gesamtdauer des Skripts: $($totalDuration.TotalSeconds) Sekunden" -ForegroundColor Cyan



