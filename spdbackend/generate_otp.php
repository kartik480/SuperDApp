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

$phone = trim($input['phone']);

try {
  // Check if user exists with this phone number
  $stmt = $conn->prepare("SELECT id, name, phone FROM users WHERE phone = ?");
  $stmt->bind_param('s', $phone);
  $stmt->execute();
  $result = $stmt->get_result();
  
  if ($result->num_rows === 0) {
    http_response_code(404);
    echo json_encode(['success' => false, 'message' => 'No account found with this phone number']);
    exit();
  }
  
  $user = $result->fetch_assoc();
  $stmt->close();
  
  // Generate 6-digit OTP
  $otp = str_pad(rand(0, 999999), 6, '0', STR_PAD_LEFT);
  
  // OTP expires in 10 minutes
  $expires_at = date('Y-m-d H:i:s', strtotime('+10 minutes'));
  
  // Store OTP in database (create table if not exists)
  // First check if otp_verifications table exists, if not create it
  $createTableQuery = "CREATE TABLE IF NOT EXISTS otp_verifications (
    id INT AUTO_INCREMENT PRIMARY KEY,
    phone VARCHAR(20) NOT NULL,
    otp VARCHAR(6) NOT NULL,
    expires_at DATETIME NOT NULL,
    verified TINYINT(1) DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_phone_otp (phone, otp),
    INDEX idx_expires_at (expires_at)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";
  
  $conn->query($createTableQuery);
  
  // Delete old unverified OTPs for this phone
  $stmt = $conn->prepare("DELETE FROM otp_verifications WHERE phone = ? AND verified = 0");
  $stmt->bind_param('s', $phone);
  $stmt->execute();
  $stmt->close();
  
  // Insert new OTP
  $stmt = $conn->prepare("INSERT INTO otp_verifications (phone, otp, expires_at) VALUES (?, ?, ?)");
  $stmt->bind_param('sss', $phone, $otp, $expires_at);
  $stmt->execute();
  $stmt->close();
  
  // TODO: Send OTP via SMS Gateway (Twilio, Nexmo, etc.)
  // For now, we'll return the OTP in the response for testing
  // In production, remove this and send via SMS
  
  // Example SMS sending (uncomment and configure when ready):
  /*
  $smsMessage = "Your Super Daily OTP is: $otp. Valid for 10 minutes. Do not share this code.";
  // Send SMS using your preferred SMS gateway
  // sendSMS($phone, $smsMessage);
  */
  
  echo json_encode([
    'success' => true,
    'message' => 'OTP sent successfully to your phone number',
    'otp' => $otp, // Remove this in production
    'debug' => [
      'phone' => $phone,
      'expires_at' => $expires_at,
    ],
  ]);
  
} catch (Exception $e) {
  http_response_code(500);
  echo json_encode([
    'success' => false,
    'message' => 'Error generating OTP: ' . $e->getMessage(),
  ]);
}

$conn->close();
?>

