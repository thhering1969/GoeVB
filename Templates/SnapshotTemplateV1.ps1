# VMware-Verbindungsdaten
$username = '{username}'
$password = '{password}'
$currentTime = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$snapshotDescription = "Snapshot vom $(Get-Date -Format 'dd.MM.yyyy')"

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
