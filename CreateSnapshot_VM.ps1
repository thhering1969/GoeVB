param (
    [string]$vmName  # Der VM-Name als Parameter
)

# Startzeit des Skripts
$scriptStartTime = Get-Date

# Setze die Ausgabe-Codierung für Konsolenausgabe auf UTF-8
$OutputEncoding = [System.Console]::OutputEncoding = [System.Console]::InputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# Importiere das externe Skript f r Write-OutputSafe
#. "$PSScriptRoot\Write-OutputSafe.ps1"
#New-Alias write-output Write-OutputSafe
#New-Alias write-host Write-OutputSafe

. "$PSScriptRoot\Update-ZabbixMacro.ps1"
. "$PSScriptRoot\Get-ZabbixHostByName.ps1"



# VMware-Verbindungsdaten
$username = 'administrator@vsphere.local'
$password = 'GoeVB2020,'
$env:PowerCLI_SkipWelcome = "True"
#Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Scope User -Confirm:$false -WarningAction SilentlyContinue | out-null
$env:SUPPRESS_BANNER = $true


$BypassWednesdayCheck = $True  # Wird durch den Wert von BypassWednesdayCheck ersetzt

$currentTime = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$snapshotDescription = "WU Snapshot vom $(Get-Date -Format 'dd.MM.yyyy')"

# Zabbix API Details
$zabbixServer = "192.168.116.114"
$apiToken = "b910b5ad64ac886ed834e88cb71de707fd6b1e31b5df63fc542e4ed2eb801be4"  # API Token
$zabbixApiUrl = "http://$($zabbixServer):8080/api_jsonrpc.php"
# Header f r die Anfrage
$headers = @{
    "Authorization" = "Bearer $apiToken"
    "Content-Type"  = "application/json"
}

# Funktion: PowerCLI-Modul prüfen und installieren
function Check-And-Install-PowerCLI {
    Write-Host "Prüfe, ob VMware.PowerCLI installiert ist..."
    

    if (-not (Get-Module -ListAvailable -Name VMware.PowerCLI)) {
        Write-Host "VMware.PowerCLI ist nicht installiert. Installation wird gestartet..."
        try {
            Install-Module -Name VMware.PowerCLI -Scope CurrentUser -Force | out-null
            Write-Host "VMware.PowerCLI wurde erfolgreich installiert."
        } catch {
            Write-Error "Fehler bei der Installation des VMware.PowerCLI-Moduls: $_"
            exit 1
        }
    } else {
        Write-Host "VMware.PowerCLI ist bereits installiert."
    }
}

# Funktion: PowerCLI-Modul importieren
function Import-PowerCLI {
    Write-Host "Importiere VMware PowerCLI Core-Module..."

    try {
        # Direkt die benötigten Kernmodule importieren, ohne die Begrüßungsnachricht
        Import-Module VMware.VimAutomation.Core -ErrorAction Stop | Out-Null
        
        Write-Host "VMware PowerCLI Core-Module wurden erfolgreich importiert."
    } catch {
        Write-Error "Fehler beim Importieren der VMware PowerCLI Core-Module: $_"
        exit 1
    }
}

function Is-Wednesday-After-Second-Tuesday {
    $currentDate = Get-Date
    $dayOfWeek = $currentDate.DayOfWeek
    $isWednesday = ($dayOfWeek -eq 'Wednesday')

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

        # Überprüfen, ob heute dieser Mittwoch ist
        return ($currentDate.Date -eq $wednesdayAfterSecondTuesday.Date)
    }
    return $false
}

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
        Write-Host "Fehler bei der Verbindung zu vCenter: $vCenterServer f r VM: $vmName" -ForegroundColor Red
        return $false
    }
    try {
        $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
        if ($vm -and $vm.PowerState -eq 'PoweredOn') {
            
           New-Snapshot -VM $vm -Name "WU Snapshot $(Get-Date -Format 'dd.MM.yyyy HH:mm')" -Description $snapshotDescription | Out-Null
           
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

if ((Is-Wednesday-After-Second-Tuesday) -or $BypassWednesdayCheck) {
    if (Is-Wednesday-After-Second-Tuesday) {
       # Snapshot wird erstellt, wenn heute der Mittwoch nach dem zweiten Dienstag des Monats ist.
    } elseif ($BypassWednesdayCheck) {
       # Snapshot wird erstellt, da BypassWednesdayCheck aktiv ist.
    }
} else {
    Write-Host "Heute ist nicht der Mittwoch nach dem zweiten Dienstag des Monats und BypassWednesdayCheck ist nicht gesetzt. Snapshot wird NICHT erstellt."
    Exit
}

# Zabbix gibt hier den VM-Namen aus, der als Parameter  bergeben wird
$vmName = $vmName

$vCenterServers = @(
    'vc1.mgmt.lan',
    'vc2.mgmt.lan',
    'vc3.mgmt.lan',
    'vc4.mgmt.lan'
)

# Snapshot f r die VM erstellen
foreach ($vCenterServer in $vCenterServers) {
    Write-Host "Starte Verarbeitung für VM: $vmName auf vCenter: $vCenterServer" -ForegroundColor Yellow
    $snapshotCreated = $false

    if (Create-Snapshot -vCenterServer $vCenterServer -username $username -password $password -vmName $vmName -snapshotDescription $snapshotDescription) {
        $snapshotCreated = $true
        $hostid = (Get-ZabbixHostByName -hostname $vmname).hostid
        $macroName = "{`$VSPHERE_SNAPSHOT_STATUS}"
        $macroValue = "WU Snapshot VM $vmName  erfolgreich am $(Get-Date -Format 'dd.MM.yyyy') erstellt."
        
        Update-ZabbixMacro -hostId $hostId -macroName $macroName -macroValue $macroValue

        break
    }

    if (-not $snapshotCreated) {
        Write-Host "Snapshot konnte für VM $vmName auf vCenter $vCenterServer nicht erstellt werden." -ForegroundColor Red
    }
}

# Gesamtdauer des Skripts
$scriptEndTime = Get-Date
$totalDuration = $scriptEndTime - $scriptStartTime
Write-Host "Gesamtdauer des Skripts: $($totalDuration.TotalSeconds) Sekunden" -ForegroundColor Cyan