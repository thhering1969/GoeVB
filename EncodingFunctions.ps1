function Get-FileEncoding {
    param (
        [string]$scriptPath
    )

    # Read file content as bytes
    $fileBytes = [System.IO.File]::ReadAllBytes($scriptPath)

    # Check if the file is UTF-8 with BOM
    if ($fileBytes.Length -gt 2 -and $fileBytes[0] -eq 0xEF -and $fileBytes[1] -eq 0xBB -and $fileBytes[2] -eq 0xBF) {
        return 'UTF-8 mit BOM'
    }

    # Check for UTF-16 BOMs
    if ($fileBytes.Length -gt 1) {
        if ($fileBytes[0] -eq 0xFF -and $fileBytes[1] -eq 0xFE) {
            return 'UTF-16 (Little Endian)'
        }
        if ($fileBytes[0] -eq 0xFE -and $fileBytes[1] -eq 0xFF) {
            return 'UTF-16 (Big Endian)'
        }
    }

    # Check if it's UTF-8 without BOM (looking for valid UTF-8 byte sequences)
    $isUTF8 = $true
    for ($i = 0; $i -lt $fileBytes.Length; $i++) {
        $byte = $fileBytes[$i]

        if ($byte -gt 0x7F) {
            # Check for multi-byte UTF-8 sequences
            if ($byte -ge 0xC0 -and $byte -lt 0xE0) {
                # 2-byte sequence
                if ($i + 1 -lt $fileBytes.Length -and ($fileBytes[$i + 1] -band 0xC0) -eq 0x80) {
                    $i++
                    continue
                }
                else {
                    $isUTF8 = $false
                    break
                }
            }
            elseif ($byte -ge 0xE0 -and $byte -lt 0xF0) {
                # 3-byte sequence
                if ($i + 2 -lt $fileBytes.Length -and
                    ($fileBytes[$i + 1] -band 0xC0) -eq 0x80 -and
                    ($fileBytes[$i + 2] -band 0xC0) -eq 0x80) {
                    $i += 2
                    continue
                }
                else {
                    $isUTF8 = $false
                    break
                }
            }
            elseif ($byte -ge 0xF0 -and $byte -lt 0xF8) {
                # 4-byte sequence
                if ($i + 3 -lt $fileBytes.Length -and
                    ($fileBytes[$i + 1] -band 0xC0) -eq 0x80 -and
                    ($fileBytes[$i + 2] -band 0xC0) -eq 0x80 -and
                    ($fileBytes[$i + 3] -band 0xC0) -eq 0x80) {
                    $i += 3
                    continue
                }
                else {
                    $isUTF8 = $false
                    break
                }
            }
            else {
                $isUTF8 = $false
                break
            }
        }
    }

    if ($isUTF8) {
        return 'UTF-8 ohne BOM'
    }

    # Check for Windows-1252 (SBCS)
    $isSBCS = $true
    foreach ($byte in $fileBytes) {
        if ($byte -gt 0x7F -and ($byte -lt 0xA0 -or $byte -gt 0xFF)) {
            $isSBCS = $false
            break
        }
    }

    if ($isSBCS) {
        return 'Windows-1252 (SBCS)'
    }

    return 'Unbekanntes oder nicht unterstütztes Encoding'
}


function Convert-ToSBCS {
    param (
        [string]$filePath,  # Der Pfad zur Eingabedatei
        [string]$outputPath # Der Pfad zur Ausgabedatei
    )

    # Erhalte das Encoding der Datei
    $detectedEncoding = Get-FileEncoding -scriptPath $filePath

    # Hole das aktuelle Console-Encoding
    $consoleEncoding = [System.Console]::OutputEncoding

    # Prüfe, ob die Datei bereits im Windows-1252 (SBCS) Encoding vorliegt
    if ($detectedEncoding -eq "Windows-1252 (SBCS)") {
        $OutputEncoding=[System.Text.Encoding]::UTF8
        [System.Console]::OutputEncoding=[System.Text.Encoding]::UTF8
        Write-Host "Die Datei ist bereits im Windows-1252 (SBCS) Encoding. Keine Konvertierung erforderlich."
        return
    }

    # Vergleiche mit dem Console-Encoding und konvertiere nur, wenn sie nicht übereinstimmen
    if ($detectedEncoding -ne $consoleEncoding) {
	$OutputEncoding=[System.Text.Encoding]::UTF8
        [System.Console]::OutputEncoding=[System.Text.Encoding]::UTF8
        Write-Host "Die Datei ist nicht im richtigen Encoding. Konvertiere..."
    } else {
	$OutputEncoding=[System.Text.Encoding]::UTF8
        [System.Console]::OutputEncoding=[System.Text.Encoding]::UTF8
        Write-Host "Das Encoding der Datei stimmt mit dem der Konsole überein. Keine Konvertierung erforderlich."
        return
    }

    # Lese den Inhalt der Datei basierend auf ihrem Encoding
    if ($detectedEncoding -eq "UTF-8 ohne BOM") {
        $content = Get-Content -Path $filePath -Encoding UTF8
    }
    elseif ($detectedEncoding -eq "Windows-1252 (SBCS)") {
        $content = Get-Content -Path $filePath -Encoding [System.Text.Encoding]::GetEncoding(1252)
    }
    elseif ($detectedEncoding -eq "UTF-16 (Little Endian)") {
        $content = Get-Content -Path $filePath -Encoding Unicode
    }
    elseif ($detectedEncoding -eq "UTF-16 (Big Endian)") {
        $content = Get-Content -Path $filePath -Encoding BigEndianUnicode
    }
    else {
	$OutputEncoding=[System.Text.Encoding]::UTF8
        [System.Console]::OutputEncoding=[System.Text.Encoding]::UTF8
        Write-Host "Unbekanntes Encoding, die Datei wird nicht konvertiert."
        return
    }

    # Umwandlung des Inhalts in Windows-1252 Encoding
    $windows1252Encoding = [System.Text.Encoding]::GetEncoding(1252)

    # Sicherstellen, dass Windows-konforme Zeilenumbrüche (CRLF) verwendet werden
    $contentWithWindowsLineEndings = $content -join "`r`n"

    # Umwandlung des Inhalts in ein Byte-Array mit Windows-1252 Encoding
    $byteContent = $windows1252Encoding.GetBytes($contentWithWindowsLineEndings)

    # Speichern der Datei im Windows-1252 Encoding mit den korrekten Zeilenumbrüchen
    [IO.File]::WriteAllBytes($outputPath, $byteContent)

    $OutputEncoding=[System.Text.Encoding]::UTF8
    [System.Console]::OutputEncoding=[System.Text.Encoding]::UTF8
    Write-Host "Die Datei wurde erfolgreich in Windows-1252 (SBCS) konvertiert und gespeichert."
}



  

