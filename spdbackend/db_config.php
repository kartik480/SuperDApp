<?php
// Production Database Configuration for Hostinger
// Database: u276261179_superdaily2
// Host: localhost (typical for Hostinger)

$dbHost = 'localhost';
$dbName = 'u276261179_superdaily2';
$dbUser = 'u276261179_superdaily2';
$dbPass = '1VyqFllO+';

// Create MySQLi connection
$conn = new mysqli($dbHost, $dbUser, $dbPass, $dbName);

// Check connection
if ($conn->connect_error) {
  die(json_encode(['success' => false, 'message' => 'Database connection failed: ' . $conn->connect_error]));
}

// Set charset to utf8mb4 for proper Unicode support
$conn->set_charset('utf8mb4');

// Also create a PDO connection for endpoints that use PDO
try {
  $pdo = new PDO(
    "mysql:host={$dbHost};dbname={$dbName};charset=utf8mb4",
    $dbUser,
    $dbPass,
    [
      PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
      PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
      PDO::ATTR_EMULATE_PREPARES => false,
    ]
  );
} catch (PDOException $e) {
  // PDO connection failure - log but don't die if MySQLi works
  error_log('PDO connection failed: ' . $e->getMessage());
}

// For backward compatibility with files using require_once 'db_config.php'
// Define constants for older code
define('DB_HOST', $dbHost);
define('DB_USER', $dbUser);
define('DB_PASS', $dbPass);
define('DB_NAME', $dbName);
