# VMware-Verbindungsdaten
$username = '{username}'
$password = '{password}'
$currentTime = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$snapshotDescription = "Snapshot vom $(Get-Date -Format 'dd.MM.yyyy')"

# Setzen der Variable BypassWednesdayCheck
$BypassWednesdayCheck = {BypassWednesdayCheck}  # Wird durch den Wert von BypassWednesdayCheck ersetzt

# Funktion: Überprüfen, ob heute der Mittwoch nach dem zweiten Dienstag des Monats ist
function Is-Wednesday-After-Second-Tuesday {
    $currentDate = Get-Date
    $dayOfWeek = $currentDate.DayOfWeek
    $isWednesday = ($dayOfWeek -eq 'Wednesday')

    Write-Host "Aktuelles Datum: $currentDate"
    Write-Host "Ist heute Mittwoch? $isWednesday"
    Write-Host "BypassWednesdayCheck: $BypassWednesdayCheck"

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

        Write-Host "Mittwoch nach dem zweiten Dienstag des Monats: $wednesdayAfterSecondTuesday"

        # Überprüfen, ob heute dieser Mittwoch ist
        return ($currentDate.Date -eq $wednesdayAfterSecondTuesday.Date)
    }
    return $false
}

# Überprüfen, ob der Snapshot erstellt werden soll (wenn Mittwoch nach dem zweiten Dienstag oder Bypass aktiv ist)
if ((Is-Wednesday-After-Second-Tuesday) -or $BypassWednesdayCheck) {
    if (Is-Wednesday-After-Second-Tuesday) {
        Write-Host "Snapshot wird erstellt, da heute der Mittwoch nach dem zweiten Dienstag des Monats ist."
    } elseif ($BypassWednesdayCheck) {
        Write-Host "Snapshot wird erstellt, da BypassWednesdayCheck aktiv ist."
    }
} else {
    Write-Host "Heute ist nicht der Mittwoch nach dem zweiten Dienstag des Monats und BypassWednesdayCheck ist nicht gesetzt. Snapshot wird NICHT erstellt."
}

function Create-Snapshot {
    param (
        [string]$vCenterServer,
        [string]$username,
        [string]$password,
        [string]$vmName,
        [string]$snapshotDescription
    )

    # Verbindung zu vCenter herstellen
    try {
        Connect-VIServer -Server $vCenterServer -User $username -Password $password -ErrorAction Stop | out-null
    } catch {
        Write-Host "Fehler bei der Verbindung zu vCenter: $($vCenterServer)"
        return $false
    }

    # Überprüfen, ob die VM existiert und eingeschaltet ist
    try {
        $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
        if ($vm -and $vm.PowerState -eq 'PoweredOn') {
            # Snapshot erstellen
            New-Snapshot -VM $vm -Name "Phase {phase} $(Get-Date -Format 'dd.MM.yyyy HH:mm')" -Description $snapshotDescription | out-null
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

# Liste der VMs für Phase {phase}
$vmNamesList = {vmNamesList}

# Liste der vCenter-Server für Phase {phase}
$vCenterServers = @(
    'vc1.mgmt.lan',
    'vc2.mgmt.lan',
    'vc3.mgmt.lan',
    'vc4.mgmt.lan'
)

# Snapshots für alle VMs der Phase {phase} erstellen
foreach ($vmName in $vmNamesList) {
    Write-Host "Erstelle Snapshot für VM: $vmName"

    $snapshotCreated = $false

    foreach ($vCenterServer in $vCenterServers) {
        if (Create-Snapshot -vCenterServer $vCenterServer -username $username -password $password -vmName $vmName -snapshotDescription $snapshotDescription) {
            $snapshotCreated = $true
            break  # Beende die Schleife, wenn der Snapshot erfolgreich erstellt wurde
        }
    }

    if (-not $snapshotCreated) {
        Write-Host "Snapshot konnte für VM $vmName nicht erstellt werden."
    }
}
