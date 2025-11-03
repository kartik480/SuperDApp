<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

// Handle preflight request
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once 'db_config.php';

// Only allow GET requests
if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit();
}

try {
    // Fetch active categories ordered by sort_order
    $query = "
        SELECT 
            id, name, slug, description, icon, color, image, 
            is_active, sort_order, created_at, updated_at
        FROM categories 
        WHERE (COALESCE(is_active, 1) > 0 OR is_active IS NULL)
        ORDER BY sort_order ASC, name ASC
    ";
    
    $result = $conn->query($query);
    
    if (!$result) {
        http_response_code(500);
        echo json_encode(['success' => false, 'message' => 'Database error: ' . $conn->error]);
        exit();
    }
    
    $categories = [];
    $base = 'https://superdailys.com/superdailyapp/storage/products/';
    
    while ($row = $result->fetch_assoc()) {
        // Update image URL if present
        $image = $row['image'] ?? '';
        if (!empty($image)) {
            $fname = basename($image);
            $image = $base . $fname;
        }
        
        $categories[] = [
            'id' => $row['id'],
            'name' => $row['name'] ?? '',
            'slug' => $row['slug'] ?? '',
            'description' => $row['description'] ?? '',
            'icon' => $row['icon'] ?? 'shopping_cart',
            'color' => $row['color'] ?? '#00BFA5',
            'image' => $image,
            'is_active' => isset($row['is_active']) ? (int)$row['is_active'] : 1,
            'sort_order' => isset($row['sort_order']) ? (int)$row['sort_order'] : 0,
        ];
    }

    http_response_code(200);
    echo json_encode([
        'success' => true,
        'categories' => $categories,
        'count' => count($categories),
        'message' => 'Found ' . count($categories) . ' categories'
    ]);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Server error: ' . $e->getMessage()
    ]);
}

$conn->close();
?>

