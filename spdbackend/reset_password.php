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

if (!isset($input['new_password']) || empty($input['new_password'])) {
  http_response_code(400);
  echo json_encode(['success' => false, 'message' => 'New password is required']);
  exit();
}

$phone = trim($input['phone']);
$otp = trim($input['otp']);
$newPassword = $input['new_password'];

// Validate password strength
if (strlen($newPassword) < 6) {
  http_response_code(400);
  echo json_encode(['success' => false, 'message' => 'Password must be at least 6 characters long']);
  exit();
}

try {
  // Verify OTP (should already be verified, but double-check for security)
  $stmt = $conn->prepare("
    SELECT id, phone, otp, expires_at, verified 
    FROM otp_verifications 
    WHERE phone = ? AND otp = ?
    ORDER BY created_at DESC 
    LIMIT 1
  ");
  $stmt->bind_param('ss', $phone, $otp);
  $stmt->execute();
  $result = $stmt->get_result();
  
  if ($result->num_rows === 0) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Invalid OTP']);
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
  
  // Mark OTP as verified if not already
  if ($otpRecord['verified'] == 0) {
    $stmt = $conn->prepare("UPDATE otp_verifications SET verified = 1 WHERE id = ?");
    $stmt->bind_param('i', $otpRecord['id']);
    $stmt->execute();
    $stmt->close();
  }
  
  // Hash the new password
  $hashedPassword = password_hash($newPassword, PASSWORD_DEFAULT);
  
  // Update user password
  $stmt = $conn->prepare("UPDATE users SET password = ? WHERE phone = ?");
  $stmt->bind_param('ss', $hashedPassword, $phone);
  $stmt->execute();
  
  if ($stmt->affected_rows === 0) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Failed to update password']);
    $stmt->close();
    exit();
  }
  
  $stmt->close();
  
  // Delete all OTPs for this phone (cleanup)
  $stmt = $conn->prepare("DELETE FROM otp_verifications WHERE phone = ?");
  $stmt->bind_param('s', $phone);
  $stmt->execute();
  $stmt->close();
  
  echo json_encode([
    'success' => true,
    'message' => 'Password reset successfully. You can now login with your new password.',
  ]);
  
} catch (Exception $e) {
  http_response_code(500);
  echo json_encode([
    'success' => false,
    'message' => 'Error resetting password: ' . $e->getMessage(),
  ]);
}

$conn->close();
?>

