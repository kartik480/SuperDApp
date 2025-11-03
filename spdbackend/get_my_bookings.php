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

$user_id = isset($_GET['user_id']) ? intval($_GET['user_id']) : 0;
if ($user_id <= 0) {
  http_response_code(400);
  echo json_encode(['success' => false, 'message' => 'Invalid user_id']);
  exit();
}

try {
  // Fetch all bookings for the user with maid information from maids table
  $stmt = $conn->prepare("SELECT 
    b.id, b.user_id, b.maid_id, b.assigned_at, b.assigned_by, b.assignment_notes,
    b.service_id, b.subscription_plan, b.subscription_plan_details,
    b.booking_reference, b.booking_date, b.booking_time, b.time_slot,
    b.address, b.phone, b.special_instructions,
    b.duration_hours, b.total_amount, b.discount_amount, b.final_amount,
    b.status, b.payment_status, b.payment_method, b.payment_id, b.transaction_id,
    b.gateway_response, b.billing_name, b.billing_phone, b.billing_address,
    b.payment_completed_at, b.payment_failed_at,
    b.customer_notes, b.maid_notes, b.admin_notes,
    b.address_details, b.service_requirements,
    b.confirmed_at, b.started_at, b.completed_at, b.allocated_at, b.cancelled_at,
    b.created_at, b.updated_at,
    m.id as maid_table_id, m.name as maid_name, m.phone as maid_phone, m.email as maid_email
    FROM bookings b
    LEFT JOIN maids m ON b.maid_id = m.id
    WHERE b.user_id = ? 
    ORDER BY b.created_at DESC");
  
  $stmt->bind_param('i', $user_id);
  $stmt->execute();
  $result = $stmt->get_result();
  
  $bookings = [];
  while ($row = $result->fetch_assoc()) {
    // Organize maid information
    $bookingData = [
      'id' => $row['id'],
      'user_id' => $row['user_id'],
      'maid_id' => $row['maid_id'],
      'assigned_at' => $row['assigned_at'],
      'assigned_by' => $row['assigned_by'],
      'assignment_notes' => $row['assignment_notes'],
      'service_id' => $row['service_id'],
      'subscription_plan' => $row['subscription_plan'],
      'subscription_plan_details' => $row['subscription_plan_details'],
      'booking_reference' => $row['booking_reference'],
      'booking_date' => $row['booking_date'],
      'booking_time' => $row['booking_time'],
      'time_slot' => $row['time_slot'],
      'address' => $row['address'],
      'phone' => $row['phone'],
      'special_instructions' => $row['special_instructions'],
      'duration_hours' => $row['duration_hours'],
      'total_amount' => $row['total_amount'],
      'discount_amount' => $row['discount_amount'],
      'final_amount' => $row['final_amount'],
      'status' => $row['status'],
      'payment_status' => $row['payment_status'],
      'payment_method' => $row['payment_method'],
      'payment_id' => $row['payment_id'],
      'transaction_id' => $row['transaction_id'],
      'gateway_response' => $row['gateway_response'],
      'billing_name' => $row['billing_name'],
      'billing_phone' => $row['billing_phone'],
      'billing_address' => $row['billing_address'],
      'payment_completed_at' => $row['payment_completed_at'],
      'payment_failed_at' => $row['payment_failed_at'],
      'customer_notes' => $row['customer_notes'],
      'maid_notes' => $row['maid_notes'],
      'admin_notes' => $row['admin_notes'],
      'address_details' => $row['address_details'],
      'service_requirements' => $row['service_requirements'],
      'confirmed_at' => $row['confirmed_at'],
      'started_at' => $row['started_at'],
      'completed_at' => $row['completed_at'],
      'allocated_at' => $row['allocated_at'],
      'cancelled_at' => $row['cancelled_at'],
      'created_at' => $row['created_at'],
      'updated_at' => $row['updated_at'],
    ];
    
    // Add maid information from maids table if available
    if (!empty($row['maid_id']) && !empty($row['maid_name'])) {
      $bookingData['maid_info'] = [
        'id' => $row['maid_table_id'],
        'name' => $row['maid_name'],
      ];
      // Add optional fields if they exist
      if (!empty($row['maid_phone'])) {
        $bookingData['maid_info']['phone'] = $row['maid_phone'];
      }
      if (!empty($row['maid_email'])) {
        $bookingData['maid_info']['email'] = $row['maid_email'];
      }
    } else if (!empty($row['maid_id'])) {
      // Has maid_id but no maid_name found in maids table
      $bookingData['maid_info'] = null;
    } else {
      $bookingData['maid_info'] = null;
    }
    
    $bookings[] = $bookingData;
  }
  
  $stmt->close();
  
  echo json_encode([
    'success' => true,
    'bookings' => $bookings,
    'count' => count($bookings)
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

