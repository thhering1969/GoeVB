# PostOffice_HKLM.ps1 – Vollständige Endversion mit durchgehendem Logging (HKLM statt HKCU)
# -----------------------------------------------------------------
# Setzt eine statische IP, aktiviert Office per MAK online
# und stellt die IP-Konfiguration wieder her (falls Backup vorhanden).
# Eigenes Logging — schreibt in \\vmbaramundi.goevb.de\logs$
# Usage: powershell.exe -NoProfile -ExecutionPolicy Bypass -File PostOffice_HKLM.ps1 [-KeepFlags]

param (
    [switch]$KeepFlags
)

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level = 'INFO'
    )
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Message"
    switch ($Level) {
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'DEBUG' { Write-Host $line -ForegroundColor Cyan }
        default { Write-Host $line }
    }
    # Lokales und Netzwerk-Logging
    try {
        if ($global:localLogFile) { Add-Content -Path $global:localLogFile -Value $line -ErrorAction Stop }
        if ($global:networkLogFile -and $global:networkLoggingEnabled) { 
            Add-Content -Path $global:networkLogFile -Value $line -ErrorAction Stop 
        }
    }
    catch {
        # Falls Netzwerklaufwerk nicht verfügbar, nur lokal loggen
        if ($global:localLogFile) { Add-Content -Path $global:localLogFile -Value $line }
    }
}

$ErrorActionPreference = 'SilentlyContinue'
$global:networkLoggingEnabled = $true  # Steuert das Netzwerk-Logging
Trap {
    Write-Log "GLOBAL ERROR in Zeile $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" 'ERROR'
    Continue
}

# Logging-Setup
$logRoot   = '\\vmbaramundi.goevb.de\logs$'
$localDir  = "$env:ProgramData\Baramundi"
$baseFile  = Join-Path $localDir 'PostOffice_logbase.txt'
$flagFile  = Join-Path $localDir 'PostOffice_part1_done.flag'
# PC-Name ermitteln
$pcName = $env:COMPUTERNAME

# Lokales Logging sicherstellen
if (-not (Test-Path $localDir)) { New-Item -Path $localDir -ItemType Directory -Force | Out-Null }

if ((-not $KeepFlags) -and (Test-Path $baseFile)) {
    $oldBase = Get-Content -Path $baseFile
    $oldLog  = Join-Path $logRoot "$oldBase.log"
    if (Test-Path $oldLog) {
        if ((Get-Date) - (Get-Item $oldLog).LastWriteTime -gt [TimeSpan]::FromMinutes(3)) {
            Remove-Item -Path $baseFile -ErrorAction SilentlyContinue
        }
    } else {
        Write-Log "Alte Logdatei $oldLog fehlt, überspringe Cleanup" 'WARN'
    }
}

if (Test-Path $baseFile) {
    $logBase = Get-Content -Path $baseFile
} else {
    $logBase = "PostOffice_${pcName}_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Set-Content -Path $baseFile -Value $logBase -Force
}

# Lokale und Netzwerk-Logdateien
$global:localLogFile = Join-Path $localDir "$logBase.log"
$global:networkLogFile = Join-Path $logRoot "$logBase.log"

# Sicherstellen, dass lokale Logdatei existiert
New-Item -Path $global:localLogFile -ItemType File -Force | Out-Null

Write-Log "===== SCRIPT START: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') =====" 'INFO'

function Finalize-Log {
    param([ValidateSet('completed','failed')][string]$Status)
    
    # Deaktiviere Netzwerk-Logging für alle weiteren Einträge
    $global:networkLoggingEnabled = $false
    
    if ($Status -eq 'completed') {
        Write-Log "Script endet mit Status '$Status'." 'INFO'
        $suffix = '_completed.log'
    } else {
        Write-Log "Script endet mit Status '$Status'." 'ERROR'
        $suffix = '_failed.log'
    }
    
    # Lokale Logdatei umbenennen
    $newLocalName = $global:localLogFile -replace '\.log$', $suffix
    Rename-Item -Path $global:localLogFile -NewName $newLocalName -Force -ErrorAction SilentlyContinue
    
    # UNC-Verfügbarkeit prüfen vor Kopierversuch
    $uncPath = '\\vmbaramundi.goevb.de\logs$'
    $uncAvailable = $false
    $startTime = Get-Date
    $timeout = 60  # Maximal 60 Sekunden warten
    
    Write-Log "Prüfe UNC-Verfügbarkeit: $uncPath (max. $timeout Sekunden)..." 'INFO'
    do {
        try {
            # Versuche auf UNC zuzugreifen
            $testDir = Join-Path $uncPath ([System.Guid]::NewGuid().ToString())
            $null = New-Item -Path $testDir -ItemType Directory -ErrorAction Stop
            $uncAvailable = $true
            Remove-Item -Path $testDir -Force -Recurse -ErrorAction SilentlyContinue
            Write-Log "UNC-Pfad verfügbar" 'INFO'
            break
        }
        catch {
            $elapsed = (Get-Date) - $startTime
            if ($elapsed.TotalSeconds -ge $timeout) {
                Write-Log "UNC-Prüfung nach $timeout Sekunden fehlgeschlagen" 'WARN'
                break
            }
            Write-Log "UNC nicht verfügbar - Wiederhole in 5 Sekunden... ($($_.Exception.Message))" 'WARN'
            Start-Sleep -Seconds 5
        }
    } while ($true)
    
    # Netzwerk-Logdatei umbenennen (falls existiert)
    try {
        $newNetworkName = $global:networkLogFile -replace '\.log$', $suffix
        
        if ($uncAvailable) {
            # Lösche vorhandene Zieldatei, falls existiert
            if (Test-Path $newNetworkName) {
                Remove-Item -Path $newNetworkName -Force -ErrorAction SilentlyContinue
                Write-Log "Vorhandene Zieldatei $newNetworkName gelöscht" 'INFO'
            }
            
            if (Test-Path $global:networkLogFile) {
                # Umbenennen mit Überschreiben erzwingen
                Rename-Item -Path $global:networkLogFile -NewName $newNetworkName -Force -ErrorAction Stop
                Write-Log "Netzwerk-Logdatei umbenannt zu $newNetworkName" 'INFO'
                
                # Lösche die ursprüngliche .log-Datei NUR wenn sie noch existiert
                if (Test-Path $global:networkLogFile) {
                    Remove-Item -Path $global:networkLogFile -Force -ErrorAction SilentlyContinue
                    Write-Log "Temporäre Netzwerk-Logdatei gelöscht" 'INFO'
                }
            } else {
                # Kopiere lokale Logdatei mit Überschreiben
                Copy-Item -Path $newLocalName -Destination $newNetworkName -Force -ErrorAction Stop
                Write-Log "Log erfolgreich ins Netzwerk kopiert" 'INFO'
            }
        } else {
            Write-Log "UNC nicht verfügbar - Überspringe Netzwerk-Logging" 'WARN'
        }
    }
    catch {
        Write-Log "Netzwerk-Log konnte nicht umbenannt/kopiert werden: $($_.Exception.Message)" 'WARN'
        Write-Log "Versuche alternative Methode: Kopiere lokales Log direkt" 'WARN'
        try {
            if ($uncAvailable) {
                Copy-Item -Path $newLocalName -Destination $newNetworkName -Force -ErrorAction Stop
                Write-Log "Log erfolgreich als neue Datei kopiert" 'INFO'
            }
        }
        catch {
            Write-Log "Alternatives Kopieren fehlgeschlagen: $($_.Exception.Message)" 'ERROR'
        }
    }
}

# -------------------------------------------------------------------------
# TEIL 1: Statische IP setzen & Backup (inkl. DHCP-Erkennung)
# -------------------------------------------------------------------------
$skip1 = Test-Path -Path $flagFile
Write-Log '## TEIL 1: Statische IP & Backup' 'DEBUG'
$skipRest = $false

if ($skip1) {
    Write-Log 'Teil 1 übersprungen (Flag vorhanden).' 'WARN'
} else {
    # Adapter auswählen
    $cfg = Get-NetIPConfiguration |
           Where-Object { $_.IPv4DefaultGateway -and -not (Get-NetAdapter -InterfaceIndex $_.InterfaceIndex).Virtual } |
           Select-Object -First 1
    
    if (-not $cfg) {
        Write-Log 'Kein Gateway-Adapter gefunden, wähle ersten aktiven Adapter' 'WARN'
        $ad0 = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and -not $_.Virtual } | Select-Object -First 1
        
        if (-not $ad0) {
            Write-Log 'KEIN AKTIVER ADAPTER GEFUNDEN! Teil 1 wird übersprungen.' 'ERROR'
            New-Item -Path $flagFile -ItemType File -Force | Out-Null
            $skipRest = $true
        }
        else {
            $cfg = Get-NetIPConfiguration -InterfaceIndex $ad0.InterfaceIndex
        }
    }

    if (-not $skipRest) {
        $idx = $cfg.InterfaceIndex
        $ad  = Get-NetAdapter -InterfaceIndex $idx

        # Prüfen, ob bereits eine IP aus dem Pool 1..3 vorhanden ist
        $poolIPs = @('192.168.116.1', '192.168.116.2', '192.168.116.3')
        $hasPoolIP = $false
        $currentIP = $null
        foreach ($ip in $cfg.IPv4Address.IPAddress) {
            if ($ip -in $poolIPs) {
                $hasPoolIP = $true
                $currentIP = $ip
                break
            }
        }

        if ($hasPoolIP) {
            Write-Log "Bereits eine IP aus dem Pool ($currentIP) konfiguriert - überspringe Teil 1." 'INFO'
            New-Item -Path $flagFile -ItemType File -Force | Out-Null
        } else {
            # Backup in Registry (HKLM statt HKCU)
            $guid = $ad.InterfaceGuid
            $src  = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
            $dstP = 'HKLM:\Software\NetIPBackup'
            $dst  = Join-Path $dstP $guid
            if (-not (Test-Path $dstP)) { New-Item -Path $dstP -ItemType Directory | Out-Null }
            if (-not (Test-Path $dst))  { New-Item -Path $dst  -ItemType Directory | Out-Null }
            
            $backupProps = @{}
            foreach ($prop in 'EnableDHCP','IPAddress','SubnetMask','DefaultGateway','NameServer') {
                try { 
                    $val = Get-ItemPropertyValue -Path $src -Name $prop -ErrorAction Stop 
                    $backupProps[$prop] = $val
                    Set-ItemProperty -Path $dst -Name $prop -Value $val
                    Write-Log "Backup $prop = $val" 'DEBUG'
                } 
                catch { 
                    Write-Log "Backup $prop nicht gefunden: $($_.Exception.Message)" 'DEBUG'
                    continue 
                }
            }
            Write-Log 'Backup abgeschlossen.' 'INFO'

            # DHCP-Check
            $wasDhcp = $cfg.Dhcp -eq 'Enabled'
            if ($wasDhcp) {
                Write-Log 'DHCP aktiv, keine statische IP gesetzt.' 'WARN'
                New-Item -Path $flagFile -ItemType File -Force | Out-Null
            } else {
                # DHCP deaktivieren & alte Konfig entfernen
                Set-NetIPInterface -InterfaceIndex $idx -Dhcp Disabled -Verbose | ForEach-Object { Write-Log $_ 'DEBUG' }
                foreach ($store in 'ActiveStore','PersistentStore') {
                    Get-NetIPAddress -InterfaceIndex $idx -PolicyStore $store -ErrorAction SilentlyContinue |
                        Remove-NetIPAddress -Confirm:$false -Verbose | ForEach-Object { Write-Log $_ 'DEBUG' }
                    Get-NetRoute -InterfaceIndex $idx -DestinationPrefix '0.0.0.0/0' -PolicyStore $store -ErrorAction SilentlyContinue |
                        Remove-NetRoute -Confirm:$false -Verbose | ForEach-Object { Write-Log $_ 'DEBUG' }
                }
                # Neue statische IP aus Pool
                $pool   = 1..3 | ForEach-Object { "192.168.116.$_" }
                $chosen = $null
                foreach ($ip in $pool) {
                    if (-not (Test-Connection -ComputerName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
                        $chosen = $ip
                        break
                    }
                }
                
                if (-not $chosen) { 
                    Write-Log 'Keine freie IP verfügbar! Verwende erste IP mit Warnung.' 'WARN'
                    $chosen = $pool[0] 
                }
                
                try {
                    New-NetIPAddress -InterfaceIndex $idx -IPAddress $chosen -PrefixLength 23 -DefaultGateway '192.168.116.8' -ErrorAction Stop | Out-Null
                    Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses '192.168.116.12','192.168.116.23' -ErrorAction Stop | Out-Null
                    Write-Log "Statische IP $chosen gesetzt." 'INFO'
                    Start-Sleep 2  # Kurze Pause für Netzwerkstabilisierung
                    Restart-NetAdapter -Name $ad.Name -Confirm:$false -ErrorAction Stop | Out-Null
                    Write-Log "Netzwerkadapter neu gestartet." 'INFO'
                    Start-Sleep 5 # Warten auf Netzwerkneustart
                    New-Item -Path $flagFile -ItemType File -Force | Out-Null
                }
                catch {
                    Write-Log "Fehler beim Setzen der IP: $($_.Exception.Message)" 'ERROR'
                    Write-Log "Stelle ursprüngliche Konfiguration wieder her..." 'WARN'
                    if ($wasDhcp) {
                        Set-NetIPInterface -InterfaceIndex $idx -Dhcp Enabled -ErrorAction SilentlyContinue
                        Set-DnsClientServerAddress -InterfaceIndex $idx -ResetServerAddresses -ErrorAction SilentlyContinue
                    } else {
                        # Alte IP wiederherstellen
                        $oldIP = $backupProps['IPAddress']
                        $oldMask = $backupProps['SubnetMask']
                        $oldGateway = $backupProps['DefaultGateway']
                        $oldDNS = $backupProps['NameServer']
                        
                        if ($oldIP -and $oldMask -and $oldGateway) {
                            $prefix = ($oldMask -split '\.' | ForEach-Object { [Convert]::ToString([int]$_,2).PadLeft(8,'0').ToCharArray() } | Where-Object { $_ -eq '1' }).Count
                            New-NetIPAddress -InterfaceIndex $idx -IPAddress $oldIP -PrefixLength $prefix -DefaultGateway $oldGateway -ErrorAction SilentlyContinue | Out-Null
                            if ($oldDNS) {
                                Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses $oldDNS -ErrorAction SilentlyContinue | Out-Null
                            }
                        }
                    }
                    Restart-NetAdapter -Name $ad.Name -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                    throw "Abbruch nach fehlgeschlagenem IP-Setup"
                }
            }
        }
    }
}

# -------------------------------------------------------------------------
# TEIL 2: Office aktivieren mit erweiterter Suche und Fehlerbehandlung
# -------------------------------------------------------------------------
Write-Log '## TEIL 2: Office aktivieren – START' 'DEBUG'
Write-Log 'Starte Office-Aktivierung...' 'INFO'

# Vereinfachter Port-Test ohne separate DNS-Prüfung
$activationHost = 'activation.sls.microsoft.com'
$portTestPassed = $false
$startTime = Get-Date
$timeout = 60  # Maximal 60 Sekunden warten

Write-Log "Starte Port-Test für ${activationHost}:443 (max. $timeout Sekunden)..." 'INFO'
do {
    try {
        $nc = Test-NetConnection $activationHost -Port 443 -WarningAction SilentlyContinue -ErrorAction Stop
        if ($nc.TcpTestSucceeded) {
            $portTestPassed = $true
            Write-Log "Port 443 für ${activationHost} ist erreichbar" 'INFO'
            break
        } else {
            Write-Log "Port 443 nicht erreichbar - Wiederhole in 5 Sekunden..." 'WARN'
            Start-Sleep -Seconds 5
        }
    }
    catch {
        Write-Log "Verbindungstest fehlgeschlagen: $($_.Exception.Message) - Wiederhole in 5 Sekunden..." 'WARN'
        Start-Sleep -Seconds 5
    }
    $elapsed = (Get-Date) - $startTime
} while ($elapsed.TotalSeconds -lt $timeout)

if (-not $portTestPassed) {
    Write-Log "Port 443 nach $timeout Sekunden nicht erreichbar - Fortsetzung mit Aktivierung" 'WARN'
}

# Erweiterte Office-Suche
$ospp = $null
$searchPaths = @(
    "${env:ProgramFiles}\Microsoft Office\Office*",
    "${env:ProgramFiles(x86)}\Microsoft Office\Office*",
    "${env:ProgramFiles}\Microsoft Office\root\Office*",
    "${env:ProgramFiles(x86)}\Microsoft Office\root\Office*",
    "${env:ProgramFiles}\Microsoft Office*",
    "${env:ProgramFiles(x86)}\Microsoft Office*"
)

foreach ($p in $searchPaths) {
    if (Test-Path $p) {
        $found = Get-ChildItem -Path $p -Recurse -Filter ospp.vbs -ErrorAction SilentlyContinue | 
                 Where-Object { $_.FullName -notmatch 'backup|old' } |
                 Select-Object -First 1
        if ($found) {
            $ospp = $found
            break
        }
    }
}

if (-not $ospp) {
    # Letzter Versuch: Systemweite Suche
    Write-Log 'ospp.vbs nicht in Standardpfaden gefunden, starte systemweite Suche...' 'WARN'
    $ospp = Get-ChildItem -Path C:\ -Recurse -Filter ospp.vbs -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match 'Microsoft Office' } |
            Select-Object -First 1
}

if ($ospp) {
    Write-Log "ospp.vbs gefunden: $($ospp.FullName)" 'INFO'
    try {
        $officeDir = $ospp.DirectoryName
        Write-Log "Wechsle Verzeichnis: $officeDir" 'DEBUG'
        Push-Location $officeDir
        
        # Aktivierung mit expliziter Ausführung
        Write-Log "Starte Office-Aktivierung..." 'INFO'
        $actArgs = "//nologo `"$($ospp.FullName)`" /act"
        $actProcess = Start-Process "cscript.exe" -ArgumentList $actArgs `
                    -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\ospp_act_out.txt" `
                    -RedirectStandardError "$env:TEMP\ospp_act_err.txt"
        
        # Ausgaben verarbeiten
        $outAct = Get-Content "$env:TEMP\ospp_act_out.txt" -ErrorAction SilentlyContinue | Out-String
        $errAct = Get-Content "$env:TEMP\ospp_act_err.txt" -ErrorAction SilentlyContinue | Out-String
        
        Write-Log "Aktivierungsausgabe:`n$outAct" 'INFO'
        if ($errAct) { Write-Log "Aktivierungsfehler:`n$errAct" 'ERROR' }
        
        # Statusabfrage
        $statArgs = "//nologo `"$($ospp.FullName)`" /dstatus"
        $statProcess = Start-Process "cscript.exe" -ArgumentList $statArgs `
                    -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\ospp_status_out.txt" `
                    -RedirectStandardError "$env:TEMP\ospp_status_err.txt"
        
        $outStat = Get-Content "$env:TEMP\ospp_status_out.txt" -ErrorAction SilentlyContinue | Out-String
        $errStat = Get-Content "$env:TEMP\ospp_status_err.txt" -ErrorAction SilentlyContinue | Out-String
        
        Write-Log "Statusausgabe:`n$outStat" 'INFO'
        if ($errStat) { Write-Log "Statusfehler:`n$errStat" 'ERROR' }
        
        # Erfolgsprüfung
        if ($outStat -match '---LICENSED---') {
            Write-Log 'Office wurde erfolgreich aktiviert' 'INFO'
        } else {
            Write-Log 'Office-Aktivierung war möglicherweise nicht erfolgreich' 'WARN'
            if ($outStat -match 'ERROR') {
                Write-Log "Fehler in Statusausgabe erkannt" 'ERROR'
            }
        }
    }
    catch {
        Write-Log "Office-Aktivierungsfehler: $($_.Exception.Message)" 'ERROR'
        Write-Log "StackTrace: $($_.ScriptStackTrace)" 'DEBUG'
    }
    finally {
        Pop-Location
        # Temporäre Dateien bereinigen
        Remove-Item "$env:TEMP\ospp_*.txt" -ErrorAction SilentlyContinue
    }
} else {
    Write-Log 'ospp.vbs nicht gefunden – Office nicht installiert?' 'ERROR'
    
    # Zusätzliche Diagnose
    $officeInstall = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |
                      Where-Object { $_.DisplayName -match "Office" } |
                      Select-Object DisplayName, InstallLocation

    if ($officeInstall) {
        Write-Log "Gefundene Office-Installationen:" 'INFO'
        $officeInstall | ForEach-Object {
            Write-Log "$($_.DisplayName) in $($_.InstallLocation)" 'INFO'
        }
    } else {
        Write-Log 'Keine Office-Installation in der Registry gefunden' 'WARN'
    }
}

Write-Log '## TEIL 2: Office aktivieren – END' 'DEBUG'

# -------------------------------------------------------------------------
# TEIL 3: Restore der ursprünglichen Konfiguration (nur wenn Backup existiert)
# -------------------------------------------------------------------------
Write-Log '## TEIL 3: Restore' 'DEBUG'
$bk = 'HKLM:\Software\NetIPBackup'
if (Test-Path $bk) {
    Get-ChildItem -Path $bk | ForEach-Object {
        $guid   = $_.PSChildName
        $dstKey = Join-Path $bk $guid
        $adp    = Get-NetAdapter | Where-Object InterfaceGuid -EQ $guid
        if ($adp) {
            $i = $adp.InterfaceIndex
            Write-Log "Restore InterfaceIndex $i" 'INFO'
            try     { 
                $dh = [bool](Get-ItemPropertyValue -Path $dstKey -Name EnableDHCP -ErrorAction Stop) 
                Write-Log "EnableDHCP aus Backup: $dh" 'DEBUG'
            } 
            catch   { 
                $dh = $true
                Write-Log "EnableDHCP nicht gefunden, setze DHCP=true" 'WARN'
            }
            
            try     { $rawIPs = Get-ItemPropertyValue -Path $dstKey -Name IPAddress } catch { $rawIPs = $null }
            try     { $mask   = Get-ItemPropertyValue -Path $dstKey -Name SubnetMask } catch { $mask   = $null }
            try     { $gwVal  = Get-ItemPropertyValue -Path $dstKey -Name DefaultGateway } catch { $gwVal  = $null }
            try     { $dns    = (Get-ItemPropertyValue -Path $dstKey -Name NameServer) -split ',' } catch { $dns = $null }
            
            if ($mask) {
                $pre = ($mask -split '\.' |
                        ForEach-Object { [Convert]::ToString([int]$_,2).PadLeft(8,'0').ToCharArray() } |
                        Where-Object { $_ -eq '1' }).Count
                Write-Log "Subnetzmaske $mask = /$pre" 'DEBUG'
            }
            
            if ($dh) {
                Write-Log "Aktiviere DHCP für $($adp.Name)" 'INFO'
                Set-NetIPInterface -InterfaceIndex $i -Dhcp Enabled -Verbose | ForEach-Object { Write-Log $_ 'DEBUG' }
                Set-DnsClientServerAddress -InterfaceIndex $i -ResetServerAddresses -Verbose | ForEach-Object { Write-Log $_ 'DEBUG' }
            } elseif ($rawIPs -and $mask -and $gwVal) {
                Write-Log "Stelle statische Konfiguration wieder her" 'INFO'
                Get-NetIPAddress -InterfaceIndex $i -ErrorAction SilentlyContinue |
                    Remove-NetIPAddress -Confirm:$false -Verbose | ForEach-Object { Write-Log $_ 'DEBUG' }
                Get-NetRoute -InterfaceIndex $i -ErrorAction SilentlyContinue |
                    Remove-NetRoute -Confirm:$false -Verbose | ForEach-Object { Write-Log $_ 'DEBUG' }
                
                $ips = if ($rawIPs -is [array]) { $rawIPs } else { @($rawIPs) }
                foreach ($ip in $ips) {
                    New-NetIPAddress -InterfaceIndex $i -IPAddress $ip -PrefixLength $pre -DefaultGateway ([string]$gwVal) -Verbose |
                        ForEach-Object { Write-Log $_ 'DEBUG' }
                    Write-Log "Setze $ip/$pre GW $gwVal" 'INFO'
                }
                
                if ($dns) {
                    Set-DnsClientServerAddress -InterfaceIndex $i -ServerAddresses $dns -Verbose | ForEach-Object { Write-Log $_ 'INFO' }
                    Write-Log "DNS-Server: $($dns -join ',')" 'INFO'
                }
            } else {
                Write-Log 'Keine vollständige Backup-Konfig vorhanden, Restore übersprungen.' 'WARN'
            }
            
            Write-Log "Starte Netzwerkadapter neu..." 'INFO'
            Restart-NetAdapter -Name $adp.Name -Confirm:$false -Verbose | ForEach-Object { Write-Log $_ 'DEBUG' }
            Start-Sleep 5  # Kurze Pause nach Netzwerkänderung
        }
    }
    # Backup-Verzeichnis nach Restore löschen
    Remove-Item -Path $bk -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "Backup-Verzeichnis $bk gelöscht." 'INFO'
} else {
    Write-Log 'Kein Backup gefunden, überspringe Restore.' 'WARN'
}

Write-Log 'END' 'INFO'
Finalize-Log 'completed'
