<?php
// spdbackend/bookings_create.php

// CORS and JSON headers (adjust Access-Control-Allow-Origin as needed)
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

// Read JSON request body
$raw = file_get_contents('php://input');
$data = json_decode($raw, true);
if (!is_array($data)) {
  http_response_code(400);
  echo json_encode(['success' => false, 'message' => 'Invalid JSON body']);
  exit;
}

// --- CONFIGURE YOUR DATABASE HERE ---
$dbHost = '127.0.0.1';    // e.g., 127.0.0.1 or localhost
$dbName = 'superdaily2';  // your database name
$dbUser = 'root';         // your DB user
$dbPass = '';             // your DB password
$table  = 'bookings';     // target table
// ------------------------------------

try {
  $pdo = new PDO("mysql:host={$dbHost};dbname={$dbName};charset=utf8mb4", $dbUser, $dbPass, [
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
  ]);
} catch (Throwable $e) {
  http_response_code(500);
  echo json_encode(['success' => false, 'message' => 'DB connect error', 'error' => $e->getMessage()]);
  exit;
}

// Whitelist of columns allowed to be inserted
$allowed = [
  'user_id','maid_id','assigned_at','assigned_by','assignment_notes',
  'service_id','subscription_plan','subscription_plan_details','booking_reference',
  'booking_date','booking_time','time_slot','address','phone','special_instructions',
  'duration_hours','total_amount','discount_amount','final_amount','status',
  'payment_status','payment_method','payment_id','transaction_id','gateway_response',
  'billing_name','billing_phone','billing_address','payment_completed_at','payment_failed_at',
  'customer_notes','maid_notes','admin_notes','address_details','service_requirements',
  'confirmed_at','started_at','completed_at','allocated_at','cancelled_at',
  'created_at','updated_at'
];

// Minimal required fields
$required = ['user_id','service_id','booking_date','booking_time','final_amount'];
foreach ($required as $r) {
  if (!array_key_exists($r, $data) || $data[$r] === null || $data[$r] === '') {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => "Missing required: $r"]);
    exit;
  }
}

// Filter payload
$insert = [];
foreach ($allowed as $col) {
  if (array_key_exists($col, $data)) {
    $insert[$col] = $data[$col];
  }
}

// Normalize JSON columns if your schema uses JSON type with CHECK(JSON_VALID(...))
if (array_key_exists('address_details', $insert)) {
  $v = $insert['address_details'];
  if (is_array($v)) {
    $insert['address_details'] = json_encode($v, JSON_UNESCAPED_UNICODE);
  } elseif (is_string($v)) {
    $trim = trim($v);
    if ($trim === '') {
      $insert['address_details'] = null;
    } else {
      // If not already a valid JSON string, wrap it
      json_decode($trim, true);
      if (json_last_error() !== JSON_ERROR_NONE) {
        $insert['address_details'] = json_encode(['address' => $v], JSON_UNESCAPED_UNICODE);
      } else {
        $insert['address_details'] = $trim;
      }
    }
  }
}

// Auto timestamps if not set
$now = date('Y-m-d H:i:s');
if (!isset($insert['created_at']) || empty($insert['created_at'])) $insert['created_at'] = $now;
if (!isset($insert['updated_at']) || empty($insert['updated_at'])) $insert['updated_at'] = $now;

// Build INSERT
$cols = array_keys($insert);
$phs  = array_map(fn($c) => ':' . $c, $cols);
$sql  = 'INSERT INTO `' . $table . '` (' . implode(',', array_map(fn($c) => '`'.$c.'`', $cols)) . ') VALUES (' . implode(',', $phs) . ')';

try {
  $stmt = $pdo->prepare($sql);
  foreach ($insert as $k => $v) {
    if (is_int($v))          { $type = PDO::PARAM_INT; }
    elseif (is_bool($v))     { $type = PDO::PARAM_BOOL; }
    elseif ($v === null)     { $type = PDO::PARAM_NULL; }
    else                     { $type = PDO::PARAM_STR; }
    $stmt->bindValue(':' . $k, $v, $type);
  }
  $stmt->execute();
  $id = $pdo->lastInsertId();
  echo json_encode(['success' => true, 'id' => $id]);
} catch (Throwable $e) {
  http_response_code(500);
  echo json_encode(['success' => false, 'message' => 'Insert failed', 'error' => $e->getMessage()]);
}


