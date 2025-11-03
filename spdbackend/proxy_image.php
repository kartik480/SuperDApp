<?php
/**
 * Image Proxy Script
 * This script proxies image requests to bypass CORS issues
 * Usage: https://superdailys.com/superdailyapp/proxy_image.php?url=<encoded_image_url>
 */

// Handle preflight OPTIONS request for CORS
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
    header('Access-Control-Max-Age: 86400');
    http_response_code(200);
    exit;
}

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');

// Get the image URL from query parameter
$imageUrl = isset($_GET['url']) ? urldecode($_GET['url']) : '';

if (empty($imageUrl)) {
    http_response_code(400);
    header('Content-Type: application/json');
    echo json_encode(['error' => 'Missing url parameter']);
    exit;
}

// Validate URL to prevent SSRF attacks - only allow images from our domains
$allowedDomains = [
    'superdailys.com', 
    'www.superdailys.com',
    'srv1881-files.hstgr.io' // Allow Hostinger file server
];
$parsedUrl = parse_url($imageUrl);
if (!$parsedUrl || !isset($parsedUrl['host'])) {
    http_response_code(400);
    header('Content-Type: application/json');
    echo json_encode(['error' => 'Invalid URL']);
    exit;
}

$isAllowed = false;
foreach ($allowedDomains as $domain) {
    if ($parsedUrl['host'] === $domain || str_ends_with($parsedUrl['host'], '.' . $domain)) {
        $isAllowed = true;
        break;
    }
}

if (!$isAllowed) {
    http_response_code(403);
    header('Content-Type: application/json');
    echo json_encode(['error' => 'Domain not allowed']);
    exit;
}

// Fetch the image
$ch = curl_init($imageUrl);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
curl_setopt($ch, CURLOPT_MAXREDIRS, 5);
curl_setopt($ch, CURLOPT_TIMEOUT, 10);
curl_setopt($ch, CURLOPT_USERAGENT, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
$imageData = curl_exec($ch);
$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
$contentType = curl_getinfo($ch, CURLINFO_CONTENT_TYPE);
$error = curl_error($ch);
curl_close($ch);

if ($error || $httpCode !== 200 || empty($imageData)) {
    http_response_code($httpCode ?: 500);
    header('Content-Type: application/json');
    echo json_encode([
        'error' => 'Failed to fetch image',
        'http_code' => $httpCode,
        'curl_error' => $error ?: 'Unknown error',
        'url' => $imageUrl
    ]);
    exit;
}

// Validate that the content is actually an image (check first few bytes)
$imageHeader = substr($imageData, 0, 4);
$isImage = false;
$detectedType = 'image/jpeg';

// Check for common image file signatures
if (substr($imageData, 0, 2) === "\xFF\xD8") {
    // JPEG
    $isImage = true;
    $detectedType = 'image/jpeg';
} elseif (substr($imageData, 0, 8) === "\x89PNG\r\n\x1a\n") {
    // PNG
    $isImage = true;
    $detectedType = 'image/png';
} elseif (substr($imageData, 0, 6) === "GIF87a" || substr($imageData, 0, 6) === "GIF89a") {
    // GIF
    $isImage = true;
    $detectedType = 'image/gif';
} elseif (substr($imageData, 0, 12) === "RIFF" && substr($imageData, 8, 4) === "WEBP") {
    // WebP
    $isImage = true;
    $detectedType = 'image/webp';
} elseif (stripos($contentType, 'image/') !== false) {
    // Trust Content-Type header if present
    $isImage = true;
    $detectedType = $contentType;
}

if (!$isImage) {
    // Might be HTML error page - check if it starts with HTML tags
    if (stripos(trim($imageData), '<!DOCTYPE') === 0 || stripos(trim($imageData), '<html') === 0) {
        http_response_code(404);
        header('Content-Type: application/json');
        echo json_encode([
            'error' => 'URL returned HTML instead of image (file may not exist)',
            'http_code' => $httpCode,
            'url' => $imageUrl,
            'content_preview' => substr($imageData, 0, 200)
        ]);
        exit;
    }
    // Fallback: use Content-Type if available, otherwise default to jpeg
    if ($contentType && stripos($contentType, 'image/') !== false) {
        $detectedType = $contentType;
    }
}

// Determine content type from URL extension if not detected
if ($detectedType === 'image/jpeg') {
    if (preg_match('/\.(jpg|jpeg)$/i', $imageUrl)) {
        $detectedType = 'image/jpeg';
    } elseif (preg_match('/\.png$/i', $imageUrl)) {
        $detectedType = 'image/png';
    } elseif (preg_match('/\.gif$/i', $imageUrl)) {
        $detectedType = 'image/gif';
    } elseif (preg_match('/\.webp$/i', $imageUrl)) {
        $detectedType = 'image/webp';
    }
}

// Set headers and output image
header('Content-Type: ' . $detectedType);
header('Content-Length: ' . strlen($imageData));
header('Cache-Control: public, max-age=86400'); // Cache for 1 day
echo $imageData;
?>

