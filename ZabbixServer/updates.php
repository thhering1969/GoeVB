<?php

// Zabbix API Details
$zabbixServer = '192.168.116.114';
$apiToken = 'b910b5ad64ac886ed834e88cb71de707fd6b1e31b5df63fc542e4ed2eb801be4'; // API Token
$zabbixApiUrl = "http://$zabbixServer:8080/api_jsonrpc.php";

// Hostname über GET-Parameter übergeben (z. B. ?hostname=VM2WindreamTE)
$hostName = isset($_GET['hostname']) ? $_GET['hostname'] : '';
if (empty($hostName)) {
    die("Bitte einen Hostnamen angeben!");
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
    echo "<h2>Host '$hostName' wurde gefunden!</h2>";
    echo "<p><strong>Host ID:</strong> $hostId</p>";

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

        echo "<h3>Item 'log_diff_windows_update' gefunden:</h3>";
        echo "<p><strong>Item ID:</strong> $itemId</p>";
        echo "<p><strong>Item Name:</strong> $itemName</p>";
        echo "<p><strong>Letzter Wert:</strong><br>$lastValue</p>";

        if (empty($lastValue)) {
            echo "<p><strong>Letzter Wert ist leer. Ignoriere die Antwort.</strong></p>";
        } else {
            // Vorverarbeitung: Zeilen zusammenführen, die nicht mit einer Zahl beginnen.
            $lines = explode("\n", $lastValue);
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

            // Regex: Nur Zeilen mit "Installed" extrahieren, 
            // optional KB-Nummer, dann Größe, dann Titel bis zur nächsten "Installed" oder Zeilenende.
            $pattern = '/^\d+\s+\S+\s+Installed\s+(?:(KB\d+)\s+)?(\d+MB)\s+(.+?)(?=\s+Installed\b|\s*$)/im';
            preg_match_all($pattern, $cleanedLastValue, $matches, PREG_SET_ORDER);

            if (!empty($matches)) {
                echo "<h3>Installierte Updates:</h3>";
                echo "<table border='1' cellpadding='5' cellspacing='0'>";
                echo "<thead><tr><th>KB Nummer</th><th>Größe</th><th>Titel</th></tr></thead>";
                echo "<tbody>";
                foreach ($matches as $match) {
                    $kbNumber = isset($match[1]) && !empty($match[1]) ? $match[1] : 'Keine KB';
                    $size = $match[2];
                    $title = trim($match[3]);
                    echo "<tr><td>$kbNumber</td><td>$size</td><td>$title</td></tr>";
                }
                echo "</tbody></table>";
            } else {
                echo "<p>Keine installierten Updates gefunden.</p>";
            }
        }

    } else {
        echo "<p>Item 'log_diff_windows_update' nicht gefunden.</p>";
    }

} else {
    echo "Host '$hostName' nicht gefunden.";
}
?>
