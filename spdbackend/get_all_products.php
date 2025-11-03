<?php
// Handle preflight OPTIONS request for CORS
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
    header('Access-Control-Max-Age: 86400');
    http_response_code(200);
    exit;
}

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');

// Include database configuration
include_once __DIR__ . '/db_config.php';

$resp = ['success' => false, 'products' => [], 'count' => 0, 'message' => '', 'debug' => []];

// Debug: Log that we're starting
error_log('get_all_products.php: Starting execution');

if (!isset($conn) || !($conn instanceof mysqli)) {
  $resp['message'] = 'DB connection not found';
  $resp['debug']['error'] = 'Connection variable not set or wrong type';
  echo json_encode($resp, JSON_PRETTY_PRINT);
  exit;
}

// Test database connection
if ($conn->connect_error) {
  $resp['message'] = 'Database connection failed: ' . $conn->connect_error;
  $resp['debug']['error'] = 'Connection error: ' . $conn->connect_error;
  echo json_encode($resp, JSON_PRETTY_PRINT);
  exit;
}

$resp['debug']['db_connected'] = true;

// First, check if products table exists
$tableCheck = mysqli_query($conn, "SHOW TABLES LIKE 'products'");
if (!$tableCheck || mysqli_num_rows($tableCheck) == 0) {
  $resp['message'] = 'Products table does not exist';
  echo json_encode($resp);
  exit;
}

// Get total count first (no filters)
$countResult = mysqli_query($conn, "SELECT COUNT(*) as total FROM products");
$totalCount = 0;
if ($countResult) {
  $countRow = mysqli_fetch_assoc($countResult);
  $totalCount = $countRow['total'];
}

// Check what columns exist in the products table
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

// Build query - use SELECT * to get all available columns
// TEMPORARILY: Return ALL products without any filter to debug
// TODO: Add back active filter once confirmed products are showing
$query = "SELECT * FROM products";

// REMOVED FILTER TEMPORARILY FOR DEBUGGING
// Uncomment below to filter only active products:
/*
if (in_array('is_active', $columns)) {
  $query .= " WHERE (is_active = 1 OR is_active IS NULL)";
} elseif (in_array('status', $columns)) {
  $query .= " WHERE (status = 'active' OR status IS NULL OR status = '')";
} elseif (in_array('active', $columns)) {
  $query .= " WHERE (active = 1 OR active IS NULL)";
}
*/

// Order by created_at if it exists, otherwise by id
if (in_array('created_at', $columns)) {
  $query .= " ORDER BY created_at DESC";
} elseif (in_array('id', $columns)) {
  $query .= " ORDER BY id DESC";
}

$result = mysqli_query($conn, $query);
if (!$result) {
  $resp['message'] = 'Query error: ' . mysqli_error($conn);
  $resp['query'] = $query; // Include query in response for debugging
  echo json_encode($resp);
  exit;
}

$base = 'https://superdailys.com/storage/products/';
$products = [];
$imageDebug = [];
while ($row = mysqli_fetch_assoc($result)) {
  // Normalize image fields to full URLs from website storage
  foreach (['image','image_2','image_3','image_4'] as $k) {
    if (!empty($row[$k])) {
      $originalValue = $row[$k];
      // Extract just the filename from the path
      $fname = basename($row[$k]);
      // Remove any query parameters or hash from filename
      $fname = preg_replace('/[?#].*$/', '', $fname);
      // Build full URL
      $row[$k] = $base . $fname;
      
      // Debug logging
      if (!isset($imageDebug[$k])) {
        $imageDebug[$k] = [
          'sample_original' => $originalValue,
          'sample_filename' => $fname,
          'sample_resolved' => $row[$k],
          'count' => 0
        ];
      }
      $imageDebug[$k]['count']++;
    } else {
      // Track empty values
      if (!isset($imageDebug[$k])) {
        $imageDebug[$k] = ['count' => 0, 'empty_count' => 0];
      }
      $imageDebug[$k]['empty_count']++;
    }
  }
  $products[] = $row;
}

// Add image debug info to response
$resp['debug']['image_processing'] = $imageDebug;

$resp['success'] = true;
$resp['products'] = $products;
$resp['count'] = count($products);
$resp['total_in_db'] = $totalCount; // Total products in database (before filter)
$resp['debug'] = array_merge($resp['debug'], [
  'query' => $query,
  'total_columns' => count($columns),
  'available_columns' => $columns,
  'filtered' => count($products) < $totalCount,
  'products_fetched' => count($products),
  'total_in_db' => $totalCount
]);

// Log success for debugging
error_log('get_all_products.php: Successfully fetched ' . count($products) . ' products from ' . $totalCount . ' total');

echo json_encode($resp, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);

?>
