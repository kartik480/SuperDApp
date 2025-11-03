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
    // Fetch non-featured services (is_featured = 0, NULL, or not 1)
    $query = "
        SELECT 
            id, name, description, price, discount_price, image, image_2, image_3, image_4,
            main_category, subcategory, persons_count, cooking_price, property_type, cleaning_price,
            price_1_person, price_2_persons, price_1_2_persons, price_2_5_persons, price_5_10_persons,
            price_10_plus_persons, price_1_bhk, price_2_bhk, price_3_bhk, price_4_bhk,
            price_2_washroom, price_3_washroom, price_4_washroom, price_4_plus_washroom,
            monthly_plan_price, duration, booking_advance_hours, category, subscription_plans, coupon_type,
            coupon_image, coupon_service_names, coupon_discount_price, booking_requirements,
            service_latitude, service_longitude, location_id, unit, is_featured, is_active,
            features, requirements, created_at, updated_at
        FROM services 
        WHERE (COALESCE(is_featured, 0) = 0 OR is_featured IS NULL)
        AND (COALESCE(is_active, 1) > 0 OR is_active IS NULL)
        ORDER BY created_at DESC
    ";
    
    $result = $conn->query($query);
    
    if (!$result) {
        http_response_code(500);
        echo json_encode(['success' => false, 'message' => 'Database error: ' . $conn->error]);
        exit();
    }
    
    $services = [];
    // Base URL for service images
    $base = 'https://superdailys.com/storage/services/';
    
    while ($row = $result->fetch_assoc()) {
        // Update image URLs to point to services storage
        foreach (['image', 'image_2', 'image_3', 'image_4'] as $imgField) {
            if (!empty($row[$imgField])) {
                // Extract just the filename from the path
                $fname = basename($row[$imgField]);
                // Remove any query parameters or hash from filename
                $fname = preg_replace('/[?#].*$/', '', $fname);
                // Build full URL - ensure it starts with https://superdailys.com/storage/services/
                if (!empty($fname) && $fname !== '.' && $fname !== '..') {
                    $row[$imgField] = $base . $fname;
                } else {
                    $row[$imgField] = ''; // Set empty if filename is invalid
                }
            } else {
                $row[$imgField] = ''; // Ensure empty strings for null/empty values
            }
        }
        
        $services[] = [
            'id' => $row['id'],
            'name' => $row['name'] ?? '',
            'description' => $row['description'] ?? '',
            'price' => $row['price'] ?? 0,
            'discount_price' => $row['discount_price'] ?? null,
            'image' => $row['image'] ?? '',
            'image_2' => $row['image_2'] ?? '',
            'image_3' => $row['image_3'] ?? '',
            'image_4' => $row['image_4'] ?? '',
            'main_category' => $row['main_category'] ?? '',
            'subcategory' => $row['subcategory'] ?? '',
            'persons_count' => $row['persons_count'] ?? null,
            'cooking_price' => $row['cooking_price'] ?? null,
            'property_type' => $row['property_type'] ?? '',
            'cleaning_price' => $row['cleaning_price'] ?? null,
            'price_1_person' => $row['price_1_person'] ?? null,
            'price_2_persons' => $row['price_2_persons'] ?? null,
            'price_1_2_persons' => $row['price_1_2_persons'] ?? null,
            'price_2_5_persons' => $row['price_2_5_persons'] ?? null,
            'price_5_10_persons' => $row['price_5_10_persons'] ?? null,
            'price_10_plus_persons' => $row['price_10_plus_persons'] ?? null,
            'price_1_bhk' => $row['price_1_bhk'] ?? null,
            'price_2_bhk' => $row['price_2_bhk'] ?? null,
            'price_3_bhk' => $row['price_3_bhk'] ?? null,
            'price_4_bhk' => $row['price_4_bhk'] ?? null,
            'price_2_washroom' => $row['price_2_washroom'] ?? null,
            'price_3_washroom' => $row['price_3_washroom'] ?? null,
            'price_4_washroom' => $row['price_4_washroom'] ?? null,
            'price_4_plus_washroom' => $row['price_4_plus_washroom'] ?? null,
            'monthly_plan_price' => $row['monthly_plan_price'] ?? null,
            'duration' => $row['duration'] ?? '',
            'unit' => $row['unit'] ?? '',
            'is_featured' => isset($row['is_featured']) ? (int)$row['is_featured'] : 0,
            'is_active' => isset($row['is_active']) ? (int)$row['is_active'] : 1,
        ];
    }

    http_response_code(200);
    echo json_encode([
        'success' => true,
        'services' => $services,
        'count' => count($services),
        'message' => 'Found ' . count($services) . ' non-featured services'
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

