<?php
// Simple test endpoint to verify get_all_products.php works
// Access this directly in browser: https://superdailys.com/superdailyapp/test_get_all_products.php

header('Content-Type: text/html; charset=utf-8');

echo "<h1>Testing get_all_products.php</h1>";
echo "<p>This page tests the get_all_products.php endpoint directly.</p>";
echo "<hr>";

// Include and execute get_all_products.php
ob_start();
include __DIR__ . '/get_all_products.php';
$jsonOutput = ob_get_clean();

echo "<h2>Raw JSON Response:</h2>";
echo "<pre style='background: #f5f5f5; padding: 15px; border: 1px solid #ddd; overflow-x: auto;'>";
echo htmlspecialchars($jsonOutput);
echo "</pre>";

// Try to decode and display
$data = json_decode($jsonOutput, true);
if ($data) {
    echo "<h2>Decoded Response:</h2>";
    echo "<pre style='background: #e8f5e9; padding: 15px; border: 1px solid #4caf50;'>";
    echo "Success: " . ($data['success'] ? 'YES' : 'NO') . "\n";
    echo "Message: " . ($data['message'] ?? 'N/A') . "\n";
    echo "Product Count: " . ($data['count'] ?? 0) . "\n";
    echo "Total in DB: " . ($data['total_in_db'] ?? 0) . "\n";
    if (isset($data['debug'])) {
        echo "\nDebug Info:\n";
        print_r($data['debug']);
    }
    if (isset($data['products']) && is_array($data['products'])) {
        echo "\nFirst Product (if any):\n";
        if (!empty($data['products'])) {
            print_r($data['products'][0]);
        } else {
            echo "No products in array\n";
        }
    }
    echo "</pre>";
} else {
    echo "<h2 style='color: red;'>Error: Could not decode JSON response!</h2>";
    echo "<p>This might indicate a PHP error. Check server error logs.</p>";
}

echo "<hr>";
echo "<p><strong>Next Steps:</strong></p>";
echo "<ul>";
echo "<li>If you see products here but not in the app, it's likely a CORS or Flutter issue</li>";
echo "<li>If you don't see products here, check the database and PHP error logs</li>";
echo "<li>If you see PHP errors, fix them first</li>";
echo "</ul>";

?>

