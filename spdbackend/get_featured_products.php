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

// First, check what columns exist in the products table
$tableCheck = mysqli_query($conn, "DESCRIBE products");
if (!$tableCheck) {
  $resp['message'] = 'Cannot check table structure: ' . mysqli_error($conn);
  echo json_encode($resp);
  exit;
}

$columns = [];
while ($col = mysqli_fetch_assoc($tableCheck)) {
  $columns[] = $col['Field'];
}

// Build query based on available columns
$query = "SELECT * FROM products WHERE 1=1";
$hasFeaturedFilter = false;

// Check for featured column (common names: featured, is_featured, featured_product)
if (in_array('featured', $columns)) {
  $query .= " AND featured = 1";
  $hasFeaturedFilter = true;
} elseif (in_array('is_featured', $columns)) {
  $query .= " AND is_featured = 1";
  $hasFeaturedFilter = true;
} elseif (in_array('featured_product', $columns)) {
  $query .= " AND featured_product = 1";
  $hasFeaturedFilter = true;
}

// If no featured column exists, return all products as fallback
// (This maintains backward compatibility)

// Also filter for active products if status/active column exists
if (in_array('status', $columns)) {
  $query .= " AND status = 'active'";
} elseif (in_array('is_active', $columns)) {
  $query .= " AND is_active = 1";
} elseif (in_array('active', $columns)) {
  $query .= " AND active = 1";
}

$result = mysqli_query($conn, $query);
if (!$result) {
  $resp['message'] = 'Query error: ' . mysqli_error($conn);
  echo json_encode($resp);
  exit;
}

$base = 'https://superdailys.com/superdailyapp/storage/products/';
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
$resp['debug'] = [
  'query' => $query,
  'has_featured_filter' => $hasFeaturedFilter,
  'available_columns' => $columns,
  'featured_columns_found' => [
    'featured' => in_array('featured', $columns),
    'is_featured' => in_array('is_featured', $columns),
    'featured_product' => in_array('featured_product', $columns),
  ]
];
echo json_encode($resp);

