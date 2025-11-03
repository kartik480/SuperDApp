<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
  http_response_code(200);
  exit();
}

require_once 'db_config.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
  http_response_code(405);
  echo json_encode(['success' => false, 'message' => 'Method not allowed']);
  exit();
}

// Get JSON input
$input = json_decode(file_get_contents('php://input'), true);

// Validate input
if (!isset($input['phone']) || empty($input['phone'])) {
  http_response_code(400);
  echo json_encode(['success' => false, 'message' => 'Phone number is required']);
  exit();
}

if (!isset($input['otp']) || empty($input['otp'])) {
  http_response_code(400);
  echo json_encode(['success' => false, 'message' => 'OTP is required']);
  exit();
}

$phone = trim($input['phone']);
$otp = trim($input['otp']);

try {
  // Verify OTP
  $stmt = $conn->prepare("
    SELECT id, phone, otp, expires_at, verified 
    FROM otp_verifications 
    WHERE phone = ? AND otp = ? AND verified = 0
    ORDER BY created_at DESC 
    LIMIT 1
  ");
  $stmt->bind_param('ss', $phone, $otp);
  $stmt->execute();
  $result = $stmt->get_result();
  
  if ($result->num_rows === 0) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Invalid or expired OTP']);
    exit();
  }
  
  $otpRecord = $result->fetch_assoc();
  $stmt->close();
  
  // Check if OTP is expired
  $expiresAt = new DateTime($otpRecord['expires_at']);
  $now = new DateTime();
  
  if ($now > $expiresAt) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'OTP has expired. Please request a new one']);
    exit();
  }
  
  echo json_encode([
    'success' => true,
    'message' => 'OTP verified successfully',
  ]);
  
} catch (Exception $e) {
  http_response_code(500);
  echo json_encode([
    'success' => false,
    'message' => 'Error verifying OTP: ' . $e->getMessage(),
  ]);
}

$conn->close();
?>

