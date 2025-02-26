<?php
header('Content-Type: text/html; charset=utf-8');

/**
 * Konvertiert einen String in UTF-8, falls er es noch nicht ist.
 */
function convertToUtf8($str) {
    if (mb_detect_encoding($str, 'UTF-8', true) === false) {
        return utf8_encode($str);
    }
    return $str;
}
?>
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="utf-8">
    <title><?php echo convertToUtf8("Zabbix Update Log"); ?></title>
</head>
<body>
    <?php
    // Prüfe die Kodierung der aktuellen Datei
    $contents = file_get_contents(__FILE__);
    $encodings = ['UTF-8', 'ISO-8859-1', 'windows-1252'];
    $encoding = mb_detect_encoding($contents, $encodings, true);
    echo "<p>" . convertToUtf8("Die Dateikodierung ist: ") . htmlspecialchars($encoding, ENT_QUOTES, 'UTF-8') . "</p>";

    // Zabbix API Details
    $zabbixServer = '192.168.116.114';
    $apiToken = 'b910b5ad64ac886ed834e88cb71de707fd6b1e31b5df63fc542e4ed2eb801be4'; // API Token
    $zabbixApiUrl = "http://$zabbixServer:8080/api_jsonrpc.php";

    // Hostname über GET-Parameter (z. B. ?hostname=VM2WindreamTE)
    $hostName = isset($_GET['hostname']) ? $_GET['hostname'] : '';
    if (empty($hostName)) {
        die(convertToUtf8("Bitte einen Hostnamen angeben!"));
    }

    // Header für die Anfrage
    $headers = [
        "Authorization: Bearer $apiToken",
        "Content-Type: application/json"
    ];

    // 1. Host abrufen
    $body = [
        'jsonrpc' => '2.0',
        'method'  => 'host.get',
        'params'  => [
            'filter' => ['name' => $hostName],
            'output' => ['hostid', 'name']
        ],
        'id'      => 1
    ];

    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $zabbixApiUrl);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body));
    $response = curl_exec($ch);
    curl_close($ch);
    $responseData = json_decode($response, true);

    if (isset($responseData['result']) && !empty($responseData['result'])) {
        $hostId = $responseData['result'][0]['hostid'];
        $hostName = $responseData['result'][0]['name'];
        echo "<h2>" . convertToUtf8("Host '$hostName' wurde gefunden!") . "</h2>";
        echo "<p><strong>" . convertToUtf8("Host ID:") . "</strong> $hostId</p>";

        // 2. Item "log_diff_windows_update" abrufen
        $body = [
            'jsonrpc' => '2.0',
            'method'  => 'item.get',
            'params'  => [
                'hostids' => $hostId,
                'search'  => ['key_' => 'log_diff_windows_update'],
                'output'  => ['itemid', 'name', 'key_', 'lastvalue']
            ],
            'id'      => 2
        ];

        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $zabbixApiUrl);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body));
        $response = curl_exec($ch);
        curl_close($ch);
        $responseData = json_decode($response, true);

        if (isset($responseData['result']) && !empty($responseData['result'])) {
            $itemId   = $responseData['result'][0]['itemid'];
            $itemName = $responseData['result'][0]['name'];
            $lastValue = $responseData['result'][0]['lastvalue'];

            echo "<h3>" . convertToUtf8("Item 'log_diff_windows_update' gefunden:") . "</h3>";
            echo "<p><strong>" . convertToUtf8("Item ID:") . "</strong> $itemId</p>";
            echo "<p><strong>" . convertToUtf8("Item Name:") . "</strong> $itemName</p>";
            echo "<p><strong>" . convertToUtf8("Letzter Wert:") . "</strong><br>$lastValue</p>";

            // Wenn der letzte Wert leer ist, die Historie abrufen
            if (empty($lastValue)) {
                echo "<p><strong>" . convertToUtf8("Letzter Wert ist leer. Historie wird abgerufen...") . "</strong></p>";
                
                // Historie abrufen (nur nicht-leere Werte)
                $body = [
                    'jsonrpc' => '2.0',
                    'method'  => 'history.get',
                    'params'  => [
                        'itemids'   => $itemId,
                        'output'    => ['value', 'clock'],
                        'sortfield' => 'clock',
                        'sortorder' => 'DESC',
                        'limit'     => 5,
                        'history'   => 4
                    ],
                    'id'      => 3
                ];

                $ch = curl_init();
                curl_setopt($ch, CURLOPT_URL, $zabbixApiUrl);
                curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
                curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
                curl_setopt($ch, CURLOPT_POST, true);
                curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body));
                $response = curl_exec($ch);
                curl_close($ch);
                $responseData = json_decode($response, true);

                if (isset($responseData['result']) && !empty($responseData['result'])) {
                    // Verwende den aktuellsten History-Wert (DESC-Sortierung)
                    foreach ($responseData['result'] as $history) {
                        $value = $history['value'];
                        $latestTimestamp = $history['clock'];
                    }
		    echo "<p><strong>" . convertToUtf8("Letzter Log-Eintrag vom:") . "</strong> " . convertToUtf8(date('d-m-Y H:i:s', $latestTimestamp)) . "</p>";
                    
                    // Historien-Daten verarbeiten
                    $lines = explode("\n", $value);
                    $combinedLines = [];
                    foreach ($lines as $line) {
                        $line = trim($line);
                        if ($line === '') continue;
                        if (preg_match('/^\d+\s/', $line)) {
                            $combinedLines[] = $line;
                        } else {
                            if (!empty($combinedLines)) {
                                $combinedLines[count($combinedLines)-1] .= ' ' . $line;
                            }
                        }
                    }
                    $cleanedLastValue = implode("\n", $combinedLines);
                    if (substr($cleanedLastValue, -1) !== "\n") {
                        $cleanedLastValue .= "\n";
                    }

                    /* 
                      Regex zum Extrahieren der "Installed" Updates.
                      Erfasst:
                      - Update-Zeile, die mit einer Zahl beginnt.
                      - Computername, gefolgt vom Literal "Installed".
                      - Optional einen KB-Wert, dann die Größe (z. B. 78MB)
                      - Den Titel, der erfasst wird, bis ein Lookahead (z. B. "Scriptlaufzeit:", "Der Wert des Makros" oder ein erneuter "Installed"-Block) eintritt.
                    */
                    $pattern = '/^\s*(\d+)\s+(\S+)\s+Installed\s+(?:(KB\d+)\s+)?(\d+MB)\s+((?:(?!\s+Installed\s+).)+?)(?=\s+(Scriptlaufzeit:|Der Wert des Makros|Installed\s+\[\d+\])|\s*$)/m';
                    preg_match_all($pattern, $cleanedLastValue, $matches, PREG_SET_ORDER);

                    if (!empty($matches)) {
                        echo "<h3>" . convertToUtf8("Installierte Updates:") . "</h3>";
                        echo "<table border='1' cellpadding='5' cellspacing='0'>";
                        echo "<thead><tr><th>" . convertToUtf8("KB-Nummer") . "</th><th>" . convertToUtf8("Größe") . "</th><th>" . convertToUtf8("Titel") . "</th></tr></thead>";
                        echo "<tbody>";
                        foreach ($matches as $match) {
                            $kbNumber = isset($match[3]) && !empty($match[3]) ? $match[3] : 'N/A';
                            $size = $match[4];
                            $title = trim($match[5]);
                            echo "<tr><td>" . convertToUtf8($kbNumber) . "</td><td>" . convertToUtf8($size) . "</td><td>" . convertToUtf8($title) . "</td></tr>";
                        }
                        echo "</tbody></table>";
                    } else {
                        echo "<p>" . convertToUtf8("Keine installierten Updates gefunden.") . "</p>";
                    }
                } else {
                    echo "<p>" . convertToUtf8("Keine historischen Werte gefunden.") . "</p>";
                }
            } else {
                echo "<p>" . convertToUtf8("Letzter Wert ist nicht leer.") . "</p>";
            }
        } else {
            echo "<p>" . convertToUtf8("Item 'log_diff_windows_update' nicht gefunden.") . "</p>";
        }
    } else {
        echo convertToUtf8("Host '$hostName' nicht gefunden.");
    }
    ?>
</body>
</html>
