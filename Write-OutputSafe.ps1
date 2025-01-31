function Write-OutputSafe {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $umlaute = @{
        'Ä' = '$([char]0x00C4)'; 'Ö' = '$([char]0x00D6)'; 'Ü' = '$([char]0x00DC)'
        'ä' = '$([char]0x00E4)'; 'ö' = '$([char]0x00F6)'; 'ü' = '$([char]0x00FC)'
        'ß' = '$([char]0x00DF)'
    }

    foreach ($key in $umlaute.Keys) {
        $Text = $Text -replace [regex]::Escape($key), $umlaute[$key]
    }

    # Invoke-Expression aufrufen, um Console::WriteLine korrekt zu nutzen
    Invoke-Expression "[Console]::WriteLine(`"$Text`")"
}
