<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');

// Expect an existing db_config.php that sets $conn (MySQLi)
// Example: $conn = new mysqli('localhost','root','','superdaily2');
include_once __DIR__ . '/db_config.php';

$resp = ['success' => false, 'products' => [], 'count' => 0, 'message' => ''];

if (!isset($conn) || !($conn instanceof mysqli)) {
  $resp['message'] = 'DB connection not found';
  echo json_encode($resp);
  exit;
}

// Fetch featured products if column exists, else fetch all active
$query = "SELECT * FROM products";
$result = mysqli_query($conn, $query);
if (!$result) {
  $resp['message'] = mysqli_error($conn);
  echo json_encode($resp);
  exit;
}

$base = 'http://127.0.0.1/superdaily/storage/products/';
$products = [];
while ($row = mysqli_fetch_assoc($result)) {
  // Normalize image fields to full URLs from website storage
  foreach (['image','image_2','image_3','image_4'] as $k) {
    if (!empty($row[$k])) {
      $fname = basename($row[$k]);
      $row[$k] = $base . $fname;
    }
  }
  $products[] = $row;
}

$resp['success'] = true;
$resp['products'] = $products;
$resp['count'] = count($products);
echo json_encode($resp);

