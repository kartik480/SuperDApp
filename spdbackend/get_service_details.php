<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
  http_response_code(200);
  exit();
}

require_once 'db_config.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
  http_response_code(405);
  echo json_encode(['success' => false, 'message' => 'Method not allowed']);
  exit();
}

$id = isset($_GET['id']) ? intval($_GET['id']) : 0;
if ($id <= 0) {
  http_response_code(400);
  echo json_encode(['success' => false, 'message' => 'Invalid id']);
  exit();
}

try {
  $stmt = $conn->prepare("SELECT id, name, description, price, discount_price, image, image_2, image_3, image_4, main_category, subcategory, persons_count, cooking_price, property_type, cleaning_price, price_1_person, price_2_persons, price_1_2_persons, price_2_5_persons, price_5_10_persons, price_10_plus_persons, price_1_bhk, price_2_bhk, price_3_bhk, price_4_bhk, price_2_washroom, price_3_washroom, price_4_washroom, price_4_plus_washroom, duration, booking_advance_hours, category, subscription_plans, monthly_plan_price, coupon_type, coupon_image, coupon_service_names, coupon_discount_price, booking_requirements, service_latitude, service_longitude, location_id, unit, is_featured, is_active, features, requirements, created_at, updated_at FROM services WHERE id = ? LIMIT 1");
  $stmt->bind_param('i', $id);
  $stmt->execute();
  $result = $stmt->get_result();

  if ($row = $result->fetch_assoc()) {
    // Update image URLs to production path (use services storage, not products)
    // Use same URL format as monthly subscription (which works)
    $base = 'https://superdailys.com/storage/services/';
    
    foreach (['image', 'image_2', 'image_3', 'image_4'] as $imgField) {
      if (!empty($row[$imgField])) {
        // Extract just the filename from the path
        $fname = basename($row[$imgField]);
        // Remove any query parameters or hash from filename
        $fname = preg_replace('/[?#].*$/', '', $fname);
        // Build full URL
        $row[$imgField] = $base . $fname;
      }
    }
    
    echo json_encode(['success' => true, 'service' => $row]);
  } else {
    http_response_code(404);
    echo json_encode(['success' => false, 'message' => 'Service not found']);
  }
  $stmt->close();
} catch (Exception $e) {
  http_response_code(500);
  echo json_encode(['success' => false, 'message' => 'Server error: ' . $e->getMessage()]);
}

$conn->close();
?>

