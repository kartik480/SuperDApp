<?php
// CORS proxy with special-case for local filesystem reads (avoids nested localhost calls)
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

$url = isset($_GET['url']) ? $_GET['url'] : '';
if (!$url) { http_response_code(400); echo 'Missing url'; exit; }

// Map production storage paths
// Example: https://superdailys.com/superdailyapp/storage/products/<file>
if (preg_match('#^https?://(localhost|127\.0\.0\.1|superdailys\.com)/.*?/storage/products/(.+)$#i', $url, $m)) {
  $filename = $m[2];
  // Production path mapping - adjust based on your server structure
  // For Hostinger: typically public_html/superdailyapp/storage/products/
  $root = '/home/u276261179/domains/superdailys.com/public_html/superdailyapp/storage/products/';
  $path = $root . $filename;
  if (is_file($path)) {
    // Basic content-type by extension
    $ext = strtolower(pathinfo($path, PATHINFO_EXTENSION));
    $types = [
      'jpg' => 'image/jpeg',
      'jpeg'=> 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp'=> 'image/webp',
      'svg' => 'image/svg+xml',
    ];
    $ctype = isset($types[$ext]) ? $types[$ext] : 'application/octet-stream';
    header('Content-Type: ' . $ctype);
    readfile($path);
    exit;
  }
}

// Fallback: fetch via cURL
$ch = curl_init($url);
curl_setopt_array($ch, [
  CURLOPT_RETURNTRANSFER => true,
  CURLOPT_FOLLOWLOCATION => true,
  CURLOPT_TIMEOUT => 15,
]);
$data = curl_exec($ch);
$ctype = curl_getinfo($ch, CURLINFO_CONTENT_TYPE);
$httpcode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);
if ($ctype) header('Content-Type: ' . $ctype);
if ($httpcode) http_response_code($httpcode);
echo $data !== false ? $data : '';
?>

