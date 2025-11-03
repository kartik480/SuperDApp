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
  $stmt = $conn->prepare("SELECT image as image_url, image_2, image_3, image_4 FROM products WHERE id = ? LIMIT 1");
  $stmt->bind_param('i', $id);
  $stmt->execute();
  $result = $stmt->get_result();

  if ($row = $result->fetch_assoc()) {
    // Update image URLs to production path
    $base = 'https://superdailys.com/superdailyapp/storage/products/';
    $images = [];
    foreach (['image_url', 'image_2', 'image_3', 'image_4'] as $imgField) {
      $img = $row[$imgField] ?? '';
      if (!empty($img)) {
        $fname = basename($img);
        $img = $base . $fname;
      }
      $images[] = $img;
    }
    
    echo json_encode([
      'success' => true,
      'id' => $id,
      'image_url' => $images[0] ?? '',
      'images' => $images
    ]);
  } else {
    http_response_code(404);
    echo json_encode(['success' => false, 'message' => 'Record not found']);
  }
  $stmt->close();
} catch (Exception $e) {
  http_response_code(500);
  echo json_encode(['success' => false, 'message' => 'Server error: ' . $e->getMessage()]);
}

$conn->close();
?>

