# Variablen definieren
$vCenterServer = "vc2.firma.local"
$username = 'administrator@vsphere.local'
$password = 'f34150A012,#'
$currentTime = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$snapshotDescription = "Snapshot vom $(Get-Date -Format 'dd.MM.yyyy')"

# Zabbix-Variablen
$zabbixServer = "192.168.20.32" # IP-Adresse des Zabbix-Servers
$zabbixKeySnapshot = "vSphere.Snapshot.Status" # Zabbix-Item-Key für Snapshot-Status
$zabbixKeyInstallStatus = "vSphere.WindowsUpdate.Status" # Zabbix-Item-Key für Windows Update-Status

# Funktion: PowerCLI-Modul prüfen und installieren
function Check-And-Install-PowerCLI {
    Write-Host "Prüfe, ob VMware.PowerCLI installiert ist..."
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
        Import-Module VMware.PowerCLI -ErrorAction Stop
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
        $vms = Get-VM | Sort | 
            Get-View -Property @("Name", "Config.GuestFullName", "Guest.GuestFullName", "Guest.IpAddress") | 
            Select-Object -Property Name, 
                @{N="Configured OS";E={$_.Config.GuestFullName}},
                @{N="Running OS";E={$_.Guest.GuestFullName}},
                @{N="IP Address";E={@($_.Guest.IpAddress)}}

        # Windows-VMs filtern
        $windowsVMs = $vms | Where-Object { $_."Running OS" -match "Microsoft Windows" }

        if ($windowsVMs.Count -eq 0) {
            Write-Error "Keine Windows-VMs gefunden."
            return "Failed"
        }

        foreach ($vm in $windowsVMs) {
            $vmName = $vm.Name
            # Kürze den Snapshot-Namen weiter
            $snapshotName = "$($vmName.Substring(0, [Math]::Min($vmName.Length, 10)))-WUpdate-$currentTime"
            $snapshotName = $snapshotName.Substring(0, [Math]::Min($snapshotName.Length, 80))

            Write-Host "Erstelle Snapshot '$snapshotName' für VM '$vmName'..."
            New-Snapshot -VM (Get-VM -Name $vmName) -Name $snapshotName -Description $snapshotDescription
            Write-Host "Snapshot für VM '$vmName' erfolgreich erstellt."

            # Überprüfe, ob der Snapshot erfolgreich war
            $status = "Success"

            # Zabbix-Sender verwenden, dynamisch basierend auf VM-Name
            $zabbixHost = $vmName
            Zabbix-Sender -Status $status
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

    # Pfad zum zabbix_sender ermitteln
    $zabbixSenderPath = (Get-Command -Name zabbix_sender -ErrorAction SilentlyContinue).Source
    if (-not $zabbixSenderPath) {
        # Fallback: Servicepfad ermitteln
        try {
            $servicePath = Get-WmiObject -Class Win32_Service -Filter "Name='Zabbix Agent 2'" | Select-Object -ExpandProperty PathName
            if ($servicePath -match "-c\s+""([^""]+)""") {
                $configFilePath = $matches[1]
                $zabbixSenderPath = Join-Path -Path ($configFilePath -replace "\\[^\\]+$", "") -ChildPath "zabbix_sender.exe"
                Write-Host "Zabbix-Sender wurde aus dem Agent-Service-Pfad ermittelt: $zabbixSenderPath"
            } else {
                Write-Error "Fehler beim Ermitteln des Servicepfads für Zabbix-Agent: Der Pfad konnte nicht extrahiert werden."
                exit 1
            }
        } catch {
            Write-Error "Fehler beim Ermitteln des Servicepfads für Zabbix-Agent: $_"
            exit 1
        }
    }

    # Sende Daten an den Zabbix-Server
    $command = "$zabbixSenderPath -z $zabbixServer -s $zabbixHost -k $zabbixKeySnapshot -o $Status"
    Write-Host "Sende Daten an Zabbix: $command"
    try {
        & $zabbixSenderPath -z $zabbixServer -s $zabbixHost -k $zabbixKeySnapshot -o $Status
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
    # Status zurück an Zabbix senden
    $updateStatus = "Snapshot erfolgreich erstellt"
    $zabbixHost = (Get-ComputerInfo -Property HostName).HostName
    Zabbix-Sender -Status $updateStatus
} else {
    Write-Host "Snapshot-Erstellung fehlgeschlagen."
}
Write-Host "Skript abgeschlossen."