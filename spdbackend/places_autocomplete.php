<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

$input = isset($_GET['input']) ? trim($_GET['input']) : '';
if ($input === '') { echo json_encode(['predictions' => []]); exit; }

$key = 'AIzaSyDx_sQ51Uv1zBO2CfQSaM5tWMmnUFMIJaA';
$url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=' . urlencode($input) . '&key=' . $key;

$ch = curl_init($url);
curl_setopt_array($ch, [
  CURLOPT_RETURNTRANSFER => true,
  CURLOPT_FOLLOWLOCATION => true,
  CURLOPT_TIMEOUT => 10,
]);
$out = curl_exec($ch);
if ($out === false) {
  http_response_code(502);
  echo json_encode(['predictions' => [], 'error' => curl_error($ch)]);
  curl_close($ch);
  exit;
}
curl_close($ch);
echo $out;
?>

