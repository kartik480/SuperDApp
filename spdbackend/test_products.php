<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');

// Simple test endpoint to verify the file is accessible and database works
include_once __DIR__ . '/db_config.php';

$test = [
  'file_accessible' => true,
  'db_connected' => false,
  'table_exists' => false,
  'product_count' => 0,
  'sample_product' => null
];

if (isset($conn) && ($conn instanceof mysqli)) {
  $test['db_connected'] = true;
  
  // Check if table exists
  $tableCheck = mysqli_query($conn, "SHOW TABLES LIKE 'products'");
  if ($tableCheck && mysqli_num_rows($tableCheck) > 0) {
    $test['table_exists'] = true;
    
    // Get product count
    $countResult = mysqli_query($conn, "SELECT COUNT(*) as total FROM products");
    if ($countResult) {
      $countRow = mysqli_fetch_assoc($countResult);
      $test['product_count'] = $countRow['total'];
    }
    
    // Get one sample product
    $sampleResult = mysqli_query($conn, "SELECT * FROM products LIMIT 1");
    if ($sampleResult && mysqli_num_rows($sampleResult) > 0) {
      $test['sample_product'] = mysqli_fetch_assoc($sampleResult);
    }
  }
} else {
  $test['db_error'] = 'Connection not found or invalid';
}

echo json_encode($test, JSON_PRETTY_PRINT);
?>

