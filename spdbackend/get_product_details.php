<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once 'db_config.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET' && $_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit();
}

try {
    // Get product ID from query parameter or POST body
    $productId = null;
    if ($_SERVER['REQUEST_METHOD'] === 'GET') {
        $productId = isset($_GET['id']) ? intval($_GET['id']) : null;
    } else {
        $data = json_decode(file_get_contents('php://input'), true);
        $productId = isset($data['id']) ? intval($data['id']) : null;
    }

    if ($productId === null || $productId <= 0) {
        http_response_code(400);
        echo json_encode(['success' => false, 'message' => 'Product ID is required']);
        exit();
    }

    // Fetch product details
    $query = "
        SELECT 
            id, name, description, brand_name, expiry_date, price, discount_price, mrp_price,
            selling_price, discount_percentage, image, image_2, image_3, image_4, category_id,
            unit, size, weight, dimensions, color, material, tax_rate, tax_type, barcode,
            hsn_code, is_bulk_product, stock_quantity, min_stock_level, max_stock_level,
            low_stock_alert, sku, sku_code, variant_name, variant_description, is_featured,
            is_active, specifications, created_at, updated_at
        FROM products 
        WHERE id = ?
        AND (COALESCE(is_active, 1) > 0 OR is_active IS NULL)
    ";
    
    $stmt = $conn->prepare($query);
    if (!$stmt) {
        http_response_code(500);
        echo json_encode(['success' => false, 'message' => 'Database error: ' . $conn->error]);
        exit();
    }
    
    $stmt->bind_param('i', $productId);
    $stmt->execute();
    $result = $stmt->get_result();
    
    if ($result->num_rows === 0) {
        http_response_code(404);
        echo json_encode(['success' => false, 'message' => 'Product not found']);
        exit();
    }
    
    $product = $result->fetch_assoc();
    
    // Update image URLs to production path (match get_all_products.php)
    $base = 'https://superdailys.com/storage/products/';
    foreach (['image', 'image_2', 'image_3', 'image_4'] as $imgField) {
        if (!empty($product[$imgField])) {
            $originalValue = $product[$imgField];
            // Extract just the filename from the path
            $fname = basename($product[$imgField]);
            // Remove any query parameters or hash from filename
            $fname = preg_replace('/[?#].*$/', '', $fname);
            // Build full URL
            $product[$imgField] = $base . $fname;
        }
    }
    
    // Format the response
    $formattedProduct = [
        'id' => $product['id'],
        'name' => $product['name'] ?? '',
        'description' => $product['description'] ?? '',
        'brand_name' => $product['brand_name'] ?? '',
        'expiry_date' => $product['expiry_date'] ?? null,
        'price' => $product['price'] ?? 0,
        'discount_price' => $product['discount_price'] ?? null,
        'mrp_price' => $product['mrp_price'] ?? null,
        'selling_price' => $product['selling_price'] ?? null,
        'discount_percentage' => $product['discount_percentage'] ?? null,
        'image' => $product['image'] ?? '',
        'image_2' => $product['image_2'] ?? '',
        'image_3' => $product['image_3'] ?? '',
        'image_4' => $product['image_4'] ?? '',
        'category_id' => $product['category_id'] ?? null,
        'unit' => $product['unit'] ?? '',
        'size' => $product['size'] ?? '',
        'weight' => $product['weight'] ?? '',
        'dimensions' => $product['dimensions'] ?? '',
        'color' => $product['color'] ?? '',
        'material' => $product['material'] ?? '',
        'tax_rate' => $product['tax_rate'] ?? null,
        'tax_type' => $product['tax_type'] ?? '',
        'barcode' => $product['barcode'] ?? '',
        'hsn_code' => $product['hsn_code'] ?? '',
        'is_bulk_product' => isset($product['is_bulk_product']) ? (int)$product['is_bulk_product'] : 0,
        'stock_quantity' => $product['stock_quantity'] ?? 0,
        'min_stock_level' => $product['min_stock_level'] ?? null,
        'max_stock_level' => $product['max_stock_level'] ?? null,
        'low_stock_alert' => isset($product['low_stock_alert']) ? (int)$product['low_stock_alert'] : 0,
        'sku' => $product['sku'] ?? '',
        'sku_code' => $product['sku_code'] ?? '',
        'variant_name' => $product['variant_name'] ?? '',
        'variant_description' => $product['variant_description'] ?? '',
        'is_featured' => isset($product['is_featured']) ? (int)$product['is_featured'] : 0,
        'is_active' => isset($product['is_active']) ? (int)$product['is_active'] : 1,
        'specifications' => $product['specifications'] ?? '',
        'created_at' => $product['created_at'] ?? '',
        'updated_at' => $product['updated_at'] ?? '',
    ];

    http_response_code(200);
    echo json_encode([
        'success' => true,
        'product' => $formattedProduct,
        'message' => 'Product details retrieved successfully'
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Server error: ' . $e->getMessage()
    ]);
}

$stmt->close();
$conn->close();
?>

