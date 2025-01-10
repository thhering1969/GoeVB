# Variablen definieren
$vCenterServer = "vc3.mgmt.lan"
$username = 'administrator@vsphere.local'
$password = 'GoeVB2020,' 
$currentTime = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$snapshotDescription = "Snapshot vom $(Get-Date -Format 'dd.MM.yyyy')"

# Zabbix-Variablen
$zabbixServer = "192.168.116.114" # IP-Adresse des Zabbix-Servers
$zabbixKeySnapshot = "vSphere.Snapshot.Status" # Zabbix-Item-Key f�r Snapshot-Status

# Testkonfiguration (setze dies auskommentiert, um mit mehreren VMs zu arbeiten)
$testSingleVMName = "VMWSUSDB" # Setze den VM-Name hier, um nur diesen zu testen. Ansonsten lass leer, um alle VMs zu verwenden.

# Funktion: PowerCLI-Modul pr�fen und installieren
function Check-And-Install-PowerCLI {
    Write-Host "Pr�fe, ob VMware.PowerCLI installiert ist..."
    if (-not (Get-Module -ListAvailable -Name VMware.PowerCLI)) {
        Write-Host "VMware.PowerCLI ist nicht installiert. Installation wird gestartet..."
        try {
            Install-Module -Name VMware.PowerCLI -Scope CurrentUser -Force
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
    Write-Host "Importiere VMware.PowerCLI-Modul..."
    try {
        Import-Module VMware.PowerCLI -ErrorAction Stop | Out-Null
        Write-Host "VMware.PowerCLI wurde erfolgreich importiert."
    } catch {
        Write-Error "Fehler beim Importieren des VMware.PowerCLI-Moduls: $_"
        exit 1
    }
}

# Funktion: Snapshot erstellen
function Create-Snapshot {
    Write-Host "Erstelle Snapshot..."

    # Verbindung zu vCenter herstellen
    Connect-VIServer -Server $vCenterServer -User $username -Password $password -ErrorAction Stop

    try {
        # VM-Informationen abrufen
        $vms = Get-VM | Get-View -Property @("Name", "Config.GuestFullName", "Guest.GuestFullName", "Guest.IpAddress") | 
                Select-Object -Property Name, 
                    @{N="Configured OS";E={$_.Config.GuestFullName}},
                    @{N="Running OS";E={$_.Guest.GuestFullName}},
                    @{N="IP Address";E={@($_.Guest.IpAddress)}} |
                Sort-Object -Property Name

        # Wenn nur ein spezieller VM-Name gesetzt ist, l�uft der Snapshot-Prozess nur f�r diesen VM
        if ($testSingleVMName) {
            $vms = $vms | Where-Object { $_.Name -eq $testSingleVMName }
        } else {
            # Nur Windows-VMs, wenn kein spezieller Name gesetzt ist
            $vms = $vms | Where-Object { $_."Running OS" -match "Microsoft Windows" }
        }

        foreach ($vm in $vms) {
            $vmName = $vm.Name
            # K�rze den Snapshot-Namen weiter
            $snapshotName = "$($vmName.Substring(0, [Math]::Min($vmName.Length, 10)))-WUpdate-$currentTime"
            $snapshotName = $snapshotName.Substring(0, [Math]::Min($snapshotName.Length, 80))

            Write-Host "Erstelle Snapshot '$snapshotName' f�r VM '$vmName'..."
            New-Snapshot -VM (Get-VM -Name $vmName) -Name $snapshotName -Description $snapshotDescription
            Write-Host "Snapshot f�r VM '$vmName' erfolgreich erstellt."

            # �berpr�fe, ob der Snapshot erfolgreich war
            $status = "Success"

            # Zabbix-Sender verwenden, dynamisch basierend auf VM-Name
            $zabbixHost = $vmName
            if ($status -eq "Success") {
                # Status zur�ck an Zabbix senden
                $updateStatus = "Snapshot erfolgreich erstellt"
            } else {
                Write-Host "Snapshot-Erstellung fehlgeschlagen."
            }
            Zabbix-Sender -Status $updateStatus
        }

        return $status
    } catch {
        Write-Error "Fehler beim Erstellen der Snapshots: $_"
        return "Failed"
    } finally {
        # Verbindung zu vCenter trennen
        Disconnect-VIServer -Server $vCenterServer -Confirm:$false
        Write-Host "Verbindung zum vCenter Server getrennt."
    }
}

# Funktion: Zabbix-Sender verwenden
function Zabbix-Sender {
    param (
        [string]$Status
    )
    $currentTime = Get-Date -Format "dd.MM.yy-HH:mm"

    # �berpr�fung, ob das Betriebssystem Windows ist
    if ((uname -s) -eq "Linux") {
        $zabbixSenderPath = $(which zabbix_sender)
        if (-not $zabbixSenderPath) {
            Write-Error "Fehler: zabbix_sender konnte nicht gefunden werden. �berpr�fen Sie, ob es installiert ist."
            exit 1
        }
    } else {
        # Pfad zum zabbix_sender ermitteln
        $servicePath = Get-WmiObject -Class Win32_Service -Filter "Name='Zabbix Agent 2'" | Select-Object -ExpandProperty PathName
        if ($servicePath -match "zabbix_agent2.exe") {
            # Entfernen von `zabbix_agent2.exe` und allem danach
            $zabbixSenderPath = ($servicePath -replace "zabbix_agent2.exe\s+.*", "") + "zabbix_sender.exe"
        } else {
            Write-Error "Fehler beim Ermitteln des Servicepfads f�r Zabbix-Agent: Der Pfad konnte nicht extrahiert werden."
            exit 1
        }
    }

    # Sende Daten an den Zabbix-Server
    $command = "$zabbixSenderPath -z $zabbixServer -s $zabbixHost -k $zabbixKeySnapshot -o '$Status ($currentTime)'"
    Write-Host "Sende Daten an Zabbix: $command"
    try {
        & $zabbixSenderPath -z $zabbixServer -s $zabbixHost -k $zabbixKeySnapshot -o "$Status ($currentTime)"
        Write-Host "Daten erfolgreich an Zabbix gesendet: Status='$Status'."
    } catch {
        Write-Error "Fehler beim Senden von Daten an Zabbix: $_"
    }
}

# Hauptskript
Write-Host "Starte Snapshot-Erstellung..."
Check-And-Install-PowerCLI
Import-PowerCLI
$status = Create-Snapshot
Write-Host "Snapshot-Erstellungsstatus: $status"

# Nur fortfahren, wenn der Snapshot erfolgreich war
if ($status -eq "Success") {
    # Weitere Schritte...
}

Write-Host "Skript abgeschlossen."
