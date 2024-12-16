# Schritt 1: Dienstinformationen abrufen
$serviceName = "Zabbix Agent 2"
$service = Get-WmiObject -Class Win32_Service -Filter "Name = '$serviceName'"

if ($service) {
    # Hole den Pfad und die Argumente des Zabbix-Agent-Dienstes
    $servicePath = $service.PathName

    # Überprüfen, ob der Dienstpfad korrekt gefunden wurde
    if ($servicePath) {
        Write-Host "Dienstpfad gefunden: $servicePath"
        
        # Extrahiere den Pfad zur Konfigurationsdatei aus den Dienstargumenten
        # Der Parameter '-c' wird verwendet, um den Pfad zur Konfigurationsdatei zu definieren
        if ($servicePath -match "-c\s+""([^""]+)""") {
            $configFilePath = $matches[1]
            Write-Host "Der Pfad zur Konfigurationsdatei ist: $configFilePath"
            
            # Füge hier deinen Code zum Bearbeiten der Konfigurationsdatei hinzu
            # Beispiel: Benutzerparameter zum Ende der Konfiguration hinzufügen
            $userParameterLine = 'UserParameter=copy.pswindowsupdate,powershell.exe -ExecutionPolicy Bypass -File "C:\Scripts\Zabbix\PSWindowsUpdateScript.ps1"'
            
            if (Test-Path -Path $configFilePath) {
                Write-Host "Die Konfigurationsdatei wurde gefunden: $configFilePath"
                
                # Lese den Inhalt der Konfigurationsdatei
                $configContent = Get-Content -Path $configFilePath
                
                # Überprüfe, ob der UserParameter bereits vorhanden ist
                if ($configContent -contains $userParameterLine) {
                    Write-Host "Der UserParameter ist bereits in der Konfiguration vorhanden."
                } else {
                    # Suche nach der Zeile "# UserParameter=" (unabhängig von möglichen Leerzeichen)
                    $userParameterStartLine = $configContent | Where-Object { $_ -match "#\s*UserParameter=" }

                    if ($userParameterStartLine) {
                        # Finde die Position, wo der UserParameter hinzugefügt werden soll (direkt nach der gefundenen Zeile)
                        $insertPosition = $configContent.IndexOf($userParameterStartLine) + 1
                        Write-Host "Füge den UserParameter nach der Zeile '$userParameterStartLine' ein."

                        # Füge den UserParameter ein
                        $configContent = $configContent[0..($insertPosition-1)] + $userParameterLine + $configContent[$insertPosition..$configContent.Length]

                        # Schreibe den aktualisierten Inhalt zurück in die Konfigurationsdatei
                        Set-Content -Path $configFilePath -Value $configContent
                        Write-Host "Der UserParameter wurde erfolgreich zur Konfiguration hinzugefügt."
                    } else {
                        Write-Host "Fehler: Die Zeile '# UserParameter=' wurde nicht gefunden."
                    }
                }
                
                # Schritt 2: Zabbix-Agent neu starten
                Write-Host "Starte den Zabbix-Agenten neu..."
                Restart-Service -Name "Zabbix Agent 2"
                Write-Host "Der Zabbix-Agent wurde neu gestartet."
            } else {
                Write-Host "Fehler: Die Konfigurationsdatei wurde nicht gefunden unter $configFilePath."
            }
        } else {
            Write-Host "Fehler: Der Pfad zur Konfigurationsdatei konnte nicht extrahiert werden."
        }
    } else {
        Write-Host "Fehler: Der Dienstpfad konnte nicht abgerufen werden."
    }
} else {
    Write-Host "Fehler: Der Dienst '$serviceName' wurde nicht gefunden."
}
