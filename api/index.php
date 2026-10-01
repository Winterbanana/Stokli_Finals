<?php
declare(strict_types=1);

final class ApiError extends RuntimeException
{
    public int $httpStatus;

    public function __construct(string $message, int $httpStatus = 400)
    {
        parent::__construct($message);
        $this->httpStatus = $httpStatus;
    }
}

function respond(array $data, int $status = 200): void
{
    global $db, $idempotencyContext;
    if (isset($idempotencyContext) && $status >= 200 && $status < 300) {
        $statement = $db->prepare(
            'INSERT IGNORE INTO api_idempotency
             (user_id, operation_id, action, payload_hash, response_status, response_json)
             VALUES (?, ?, ?, ?, ?, ?)'
        );
        $statement->execute([
            $idempotencyContext['user_id'],
            $idempotencyContext['operation_id'],
            $idempotencyContext['action'],
            $idempotencyContext['payload_hash'],
            $status,
            json_encode($data, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE),
        ]);
    }
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

function require_value($value, string $name): string
{
    if (!is_string($value) || trim($value) === '') {
        throw new ApiError("A valid {$name} is required.", 422);
    }

    return trim($value);
}

function log_action(PDO $db, ?int $actorId, string $action, ?string $type = null, ?int $entityId = null, ?string $details = null): void
{
    $statement = $db->prepare(
        'INSERT INTO system_logs (actor_id, action, entity_type, entity_id, details)
         VALUES (?, ?, ?, ?, ?)'
    );
    $statement->execute([$actorId, $action, $type, $entityId, $details]);
}

function public_user(array $user): array
{
    unset($user['password_hash']);
    return $user;
}

function authorization_header(): string
{
    $header = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
    if ($header !== '') {
        return $header;
    }

    if (function_exists('getallheaders')) {
        foreach (getallheaders() as $name => $value) {
            if (strcasecmp((string)$name, 'Authorization') === 0) {
                return (string)$value;
            }
        }
    }

    return '';
}

function current_user(PDO $db): array
{
    $header = authorization_header();
    if (!preg_match('/^Bearer\s+([a-f0-9]{64})$/i', $header, $matches)) {
        throw new ApiError('Sign in to continue.', 401);
    }

    $statement = $db->prepare(
        'SELECT u.*
         FROM auth_sessions s
         JOIN users u ON u.id = s.user_id
         WHERE s.token_hash = ? AND s.expires_at > NOW() AND u.account_status = "active"
         LIMIT 1'
    );
    $statement->execute([hash('sha256', $matches[1])]);
    $user = $statement->fetch(PDO::FETCH_ASSOC);
    if (!$user) {
        throw new ApiError('Your session has expired. Please sign in again.', 401);
    }

    return $user;
}

function require_admin(array $user): void
{
    if ($user['role'] !== 'admin') {
        throw new ApiError('Administrator access is required.', 403);
    }
}

function available_stock(PDO $db, int $equipmentId): int
{
    $statement = $db->prepare(
        'SELECT e.total_stock
           - (SELECT COUNT(*) FROM borrowing_transactions b
              WHERE b.equipment_id = e.id AND b.status IN ("active", "return_pending"))
           - COALESCE((SELECT SUM(x.quantity) FROM inventory_exceptions x
              WHERE x.equipment_id = e.id AND x.status = "open"), 0) AS available_stock
         FROM equipment e
         WHERE e.id = ? AND e.is_active = 1
           AND e.inventory_status = "active"
           AND e.item_condition <> "Damaged"'
    );
    $statement->execute([$equipmentId]);
    $available = $statement->fetchColumn();
    if ($available === false) {
        throw new ApiError('Equipment was not found.', 404);
    }

    return max(0, (int)$available);
}

function make_code(string $prefix, int $id): string
{
    return $prefix . date('Y') . '-' . str_pad((string)$id, 6, '0', STR_PAD_LEFT);
}

function ensure_equipment_schema(PDO $db): void
{
    $db->exec(
        'CREATE TABLE IF NOT EXISTS api_schema_migrations (
           version SMALLINT UNSIGNED NOT NULL,
           applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
           PRIMARY KEY (version)
         ) ENGINE=InnoDB'
    );
    $applied = $db->query(
        'SELECT 1 FROM api_schema_migrations WHERE version = 1 LIMIT 1'
    )->fetchColumn();
    if ($applied) {
        return;
    }

    $columns = [
        'model' => 'VARCHAR(120) NULL',
        'serial_number' => 'VARCHAR(120) NULL',
        'location' => 'VARCHAR(120) NULL',
        'description' => 'TEXT NULL',
        'inventory_status' => 'VARCHAR(32) NOT NULL DEFAULT "active"',
    ];
    $existingColumns = $db->query('SHOW COLUMNS FROM equipment')
        ->fetchAll(PDO::FETCH_COLUMN, 0);
    foreach ($columns as $name => $definition) {
        if (!in_array($name, $existingColumns, true)) {
            $db->exec("ALTER TABLE equipment ADD COLUMN {$name} {$definition}");
        }
    }

    $indexes = [
        'idx_equipment_name' => 'name',
        'idx_equipment_brand' => 'brand',
        'idx_equipment_serial' => 'serial_number',
        'idx_equipment_inventory_status' => 'inventory_status',
        'idx_transactions_equipment_status' => 'equipment_id, status',
        'idx_transactions_due_status' => 'due_at, status',
        'idx_exceptions_equipment_status' => 'equipment_id, status',
    ];
    $existingIndexes = [
        'equipment' => $db->query('SHOW INDEX FROM equipment')
            ->fetchAll(PDO::FETCH_COLUMN, 2),
        'borrowing_transactions' => $db->query('SHOW INDEX FROM borrowing_transactions')
            ->fetchAll(PDO::FETCH_COLUMN, 2),
        'inventory_exceptions' => $db->query('SHOW INDEX FROM inventory_exceptions')
            ->fetchAll(PDO::FETCH_COLUMN, 2),
    ];
    foreach ($indexes as $name => $columns) {
        $table = str_starts_with($name, 'idx_transactions_')
            ? 'borrowing_transactions'
            : (str_starts_with($name, 'idx_exceptions_') ? 'inventory_exceptions' : 'equipment');
        if (!in_array($name, $existingIndexes[$table], true)) {
            $db->exec("CREATE INDEX {$name} ON {$table} ({$columns})");
        }
    }
    $db->exec('INSERT IGNORE INTO api_schema_migrations (version) VALUES (1)');
}

function ensure_account_schema(PDO $db): void
{
    $columns = $db->query('SHOW COLUMNS FROM users')->fetchAll(PDO::FETCH_COLUMN, 0);
    $definitions = [
        'email' => 'VARCHAR(254) NULL',
        'profile_photo' => 'VARCHAR(80) NULL',
        'profile_version' => 'INT UNSIGNED NOT NULL DEFAULT 1',
    ];
    foreach ($definitions as $name => $definition) {
        if (!in_array($name, $columns, true)) {
            $db->exec("ALTER TABLE users ADD COLUMN {$name} {$definition}");
        }
    }
    $indexes = $db->query('SHOW INDEX FROM users')->fetchAll(PDO::FETCH_COLUMN, 2);
    if (!in_array('uq_users_email', $indexes, true)) {
        $db->exec('CREATE UNIQUE INDEX uq_users_email ON users (email)');
    }
    $db->exec('INSERT IGNORE INTO api_schema_migrations (version) VALUES (2)');
}

function equipment_query(PDO $db, array $filters = []): array
{
    $search = trim((string)($filters['search'] ?? ''));
    $category = trim((string)($filters['category'] ?? ''));
    $status = trim((string)($filters['status'] ?? ''));
    $code = trim((string)($filters['equipment_code'] ?? ''));
    $includeDetails = ($filters['include_details'] ?? false) === true;
    $limit = max(1, min(100, (int)($filters['limit'] ?? 30)));
    $offset = max(0, (int)($filters['offset'] ?? 0));
    $base = 'SELECT e.id, e.equipment_code, e.name, e.brand, e.model, e.category,
                    e.serial_number, e.program, e.location, e.description,
                    e.total_stock, e.item_condition, e.inventory_status,
                    e.image_asset, e.is_active,
                    COALESCE(b.borrowed_quantity, 0) AS borrowed_quantity,
                    COALESCE(b.overdue_quantity, 0) AS overdue_quantity,
                    COALESCE(r.pending_quantity, 0) AS pending_quantity,
                    COALESCE(x.damaged_quantity, 0) AS damaged_quantity,
                    COALESCE(x.lost_quantity, 0) AS lost_quantity,
                    COALESCE(x.maintenance_quantity, 0) AS maintenance_quantity,
                    CASE
                      WHEN e.is_active = 0
                        OR e.inventory_status IN ("retired", "maintenance", "under maintenance", "under_maintenance", "lost", "damaged")
                        OR e.item_condition = "Damaged"
                        OR COALESCE(x.damaged_quantity, 0) > 0 THEN 0
                      ELSE GREATEST(0, e.total_stock
                        - COALESCE(b.borrowed_quantity, 0)
                        - COALESCE(x.reserved_quantity, 0))
                    END AS available_stock,
                    CASE
                      WHEN e.is_active = 0 OR e.inventory_status = "retired" THEN "Retired"
                      WHEN e.inventory_status IN ("maintenance", "under maintenance", "under_maintenance") THEN "Under Maintenance"
                      WHEN e.inventory_status = "lost" THEN "Lost"
                      WHEN e.inventory_status = "damaged" THEN "Damaged"
                      WHEN COALESCE(x.lost_quantity, 0) > 0 AND
                           e.total_stock - COALESCE(b.borrowed_quantity, 0) - COALESCE(x.reserved_quantity, 0) <= 0 THEN "Lost"
                      WHEN COALESCE(x.damaged_quantity, 0) > 0 OR e.item_condition = "Damaged" THEN "Damaged"
                      WHEN COALESCE(b.overdue_quantity, 0) > 0 THEN "Overdue"
                      WHEN COALESCE(b.borrowed_quantity, 0) > 0 THEN "Borrowed"
                      WHEN COALESCE(r.pending_quantity, 0) > 0 THEN "Pending"
                      WHEN e.total_stock - COALESCE(x.reserved_quantity, 0) > 0 THEN "Available"
                      ELSE "Unavailable"
                    END AS status
             FROM equipment e
             LEFT JOIN (
               SELECT equipment_id,
                      COUNT(*) AS borrowed_quantity,
                      SUM(CASE WHEN due_at < NOW() THEN 1 ELSE 0 END) AS overdue_quantity
               FROM borrowing_transactions
               WHERE status IN ("active", "return_pending")
               GROUP BY equipment_id
             ) b ON b.equipment_id = e.id
             LEFT JOIN (
               SELECT equipment_id,
                      SUM(quantity) AS reserved_quantity,
                      SUM(CASE WHEN exception_type = "damaged" THEN quantity ELSE 0 END) AS damaged_quantity,
                      SUM(CASE WHEN exception_type = "missing" THEN quantity ELSE 0 END) AS lost_quantity,
                      SUM(CASE WHEN exception_type = "maintenance" THEN quantity ELSE 0 END) AS maintenance_quantity
               FROM inventory_exceptions
               WHERE status = "open"
               GROUP BY equipment_id
             ) x ON x.equipment_id = e.id
             LEFT JOIN (
               SELECT equipment_id, COUNT(*) AS pending_quantity
               FROM borrowing_requests
               WHERE status = "pending"
               GROUP BY equipment_id
             ) r ON r.equipment_id = e.id';
    $where = [];
    $params = [];
    if ($code !== '') {
        $where[] = 'equipment_code = ?';
        $params[] = $code;
    }
    if ($search !== '') {
        $where[] = '(CAST(id AS CHAR) LIKE ? OR equipment_code LIKE ? OR name LIKE ? OR brand LIKE ? OR model LIKE ?
                     OR category LIKE ? OR serial_number LIKE ? OR status LIKE ?)';
        $needle = '%' . $search . '%';
        array_push($params, $needle, $needle, $needle, $needle, $needle, $needle, $needle, $needle);
    }
    if ($category !== '' && strtolower($category) !== 'all') {
        $where[] = 'category = ?';
        $params[] = $category;
    }
    if ($status !== '' && strtolower($status) !== 'all') {
        $where[] = 'LOWER(status) = LOWER(?)';
        $params[] = $status;
    }
    $projection = $includeDetails
        ? '*'
        : 'id, equipment_code, name, brand, model, category, serial_number,
           total_stock, item_condition, inventory_status, image_asset, is_active, borrowed_quantity,
           overdue_quantity, pending_quantity, damaged_quantity, lost_quantity,
           maintenance_quantity, available_stock, status';
    $sql = 'SELECT ' . $projection . ' FROM (' . $base . ') inventory' .
        ($where ? ' WHERE ' . implode(' AND ', $where) : '') .
        ' ORDER BY id';
    $count = $db->prepare('SELECT COUNT(*) FROM (' . $base . ') inventory' .
        ($where ? ' WHERE ' . implode(' AND ', $where) : ''));
    $count->execute($params);
    $total = (int)$count->fetchColumn();
    $statement = $db->prepare($sql . ' LIMIT ? OFFSET ?');
    foreach ($params as $index => $value) {
        $statement->bindValue($index + 1, $value);
    }
    $statement->bindValue(count($params) + 1, $limit, PDO::PARAM_INT);
    $statement->bindValue(count($params) + 2, $offset, PDO::PARAM_INT);
    $statement->execute();
    $items = $statement->fetchAll(PDO::FETCH_ASSOC);
    return [
        'items' => $items,
        'total_count' => $total,
        'offset' => $offset,
        'limit' => $limit,
        'has_more' => $offset + count($items) < $total,
        'categories' => $db->query('SELECT DISTINCT category FROM equipment ORDER BY category')
            ->fetchAll(PDO::FETCH_COLUMN),
    ];
}

function unpaid_balance(PDO $db, int $userId): float
{
    $statement = $db->prepare(
        'SELECT COALESCE(SUM(amount - amount_paid), 0)
         FROM penalties WHERE user_id = ? AND status = "unpaid"'
    );
    $statement->execute([$userId]);
    return (float)$statement->fetchColumn();
}

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PATCH, OPTIONS');
header('Access-Control-Allow-Headers: Authorization, Content-Type, Idempotency-Key');
header('Cache-Control: no-store');

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'OPTIONS') {
    http_response_code(204);
    exit;
}

try {
    $config = require __DIR__ . '/config.php';
    $db = new PDO(
        "mysql:host={$config['host']};port={$config['port']};dbname={$config['database']};charset=utf8mb4",
        $config['username'],
        $config['password'],
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]
    );
    $db->exec(
        'CREATE TABLE IF NOT EXISTS api_idempotency (
           user_id BIGINT UNSIGNED NOT NULL,
           operation_id CHAR(32) NOT NULL,
           action VARCHAR(80) NOT NULL,
           payload_hash CHAR(64) NOT NULL,
           response_status SMALLINT UNSIGNED NOT NULL,
           response_json MEDIUMTEXT NOT NULL,
           created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
           PRIMARY KEY (user_id, operation_id),
           CONSTRAINT fk_idempotency_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
         ) ENGINE=InnoDB'
    );
    ensure_equipment_schema($db);
    ensure_account_schema($db);
} catch (PDOException $error) {
    error_log('Stokli database connection failed: ' . $error->getMessage());
    respond(['error' => 'The Stokli database is unavailable. Check the XAMPP MySQL service and database setup.'], 503);
}

$method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
$action = (string)($_GET['action'] ?? '');
$raw = file_get_contents('php://input');
$body = $raw === '' ? [] : json_decode($raw, true);
if (!is_array($body)) {
    respond(['error' => 'Request body must be a valid JSON object.'], 400);
}

try {
    if ($action === 'health' && $method === 'GET') {
        respond(['ok' => true, 'service' => 'stokli-api', 'database' => 'connected']);
    }

    if ($action === 'login' && $method === 'POST') {
        $accountId = require_value($body['account_id'] ?? null, 'account ID');
        $password = require_value($body['password'] ?? null, 'password');
        $role = $body['role'] ?? null;
        if (!in_array($role, ['student', 'admin'], true)) {
            throw new ApiError('Choose a valid account type.', 422);
        }

        $statement = $db->prepare('SELECT * FROM users WHERE account_id = ? LIMIT 1');
        $statement->execute([$accountId]);
        $user = $statement->fetch();
        if (!$user || $user['role'] !== $role || !password_verify($password, $user['password_hash'])) {
            throw new ApiError('Invalid account ID, account type, or password.', 401);
        }
        if ($user['account_status'] !== 'active') {
            throw new ApiError('This account has been suspended. Contact an administrator.', 403);
        }

        $token = bin2hex(random_bytes(32));
        $session = $db->prepare(
            'INSERT INTO auth_sessions (user_id, token_hash, expires_at) VALUES (?, ?, DATE_ADD(NOW(), INTERVAL 30 DAY))'
        );
        $session->execute([(int)$user['id'], hash('sha256', $token)]);
        log_action($db, (int)$user['id'], 'auth.login', 'user', (int)$user['id']);
        respond(['token' => $token, 'user' => public_user($user)]);
    }

    if ($action === 'register' && $method === 'POST') {
        $accountId = require_value($body['account_id'] ?? null, 'student ID');
        $fullName = require_value($body['full_name'] ?? null, 'full name');
        $password = require_value($body['password'] ?? null, 'password');
        if (strlen($password) < 8 || !preg_match('/[A-Z]/', $password) || !preg_match('/[a-z]/', $password)
            || !preg_match('/\d/', $password) || !preg_match('/[^A-Za-z0-9]/', $password)) {
            throw new ApiError('Use at least 8 characters with uppercase, lowercase, a number, and a special character.', 422);
        }

        $statement = $db->prepare('SELECT id FROM users WHERE account_id = ? LIMIT 1');
        $statement->execute([$accountId]);
        if ($statement->fetchColumn()) {
            throw new ApiError('That account ID is already registered.', 409);
        }

        $insert = $db->prepare(
            'INSERT INTO users (account_id, full_name, password_hash, role) VALUES (?, ?, ?, "student")'
        );
        $insert->execute([$accountId, $fullName, password_hash($password, PASSWORD_DEFAULT)]);
        $userId = (int)$db->lastInsertId();
        log_action($db, $userId, 'auth.register', 'user', $userId);
        respond(['message' => 'Account created. You can now sign in.'], 201);
    }

    $user = current_user($db);
    $userId = (int)$user['id'];
    $idempotencyKey = (string)($_SERVER['HTTP_IDEMPOTENCY_KEY'] ?? '');
    if ($idempotencyKey !== '') {
        if (!preg_match('/^[a-f0-9]{32}$/i', $idempotencyKey)) {
            throw new ApiError('The operation key is invalid.', 422);
        }
        $payloadHash = hash('sha256', $action . "\n" . $method . "\n" . json_encode($body));
        $receipt = $db->prepare(
            'SELECT action, payload_hash, response_status, response_json
             FROM api_idempotency WHERE user_id = ? AND operation_id = ? LIMIT 1'
        );
        $receipt->execute([$userId, $idempotencyKey]);
        $previous = $receipt->fetch();
        if ($previous) {
            if ($previous['action'] !== $action || !hash_equals($previous['payload_hash'], $payloadHash)) {
                throw new ApiError('The operation key was already used for a different request.', 409);
            }
            http_response_code((int)$previous['response_status']);
            header('Content-Type: application/json; charset=utf-8');
            echo $previous['response_json'];
            exit;
        }
        $idempotencyContext = [
            'user_id' => $userId,
            'operation_id' => $idempotencyKey,
            'action' => $action,
            'payload_hash' => $payloadHash,
        ];
    }

    if ($action === 'logout' && $method === 'POST') {
        $header = authorization_header();
        preg_match('/^Bearer\s+([a-f0-9]{64})$/i', $header, $matches);
        $statement = $db->prepare('DELETE FROM auth_sessions WHERE token_hash = ?');
        $statement->execute([hash('sha256', $matches[1])]);
        log_action($db, $userId, 'auth.logout', 'user', $userId);
        respond(['message' => 'Signed out.']);
    }

    if ($action === 'me' && $method === 'GET') {
        respond(['user' => public_user($user)]);
    }

    if ($action === 'profile_photo' && $method === 'GET') {
        $targetId = filter_var($_GET['user_id'] ?? $user['id'], FILTER_VALIDATE_INT);
        if ($targetId === false || $targetId < 1) {
            throw new ApiError('A valid account is required.', 422);
        }
        if ((int)$targetId !== (int)$user['id']) {
            require_admin($user);
        }
        $statement = $db->prepare(
            'SELECT role, profile_photo FROM users WHERE id = ? LIMIT 1'
        );
        $statement->execute([(int)$targetId]);
        $target = $statement->fetch();
        if (!$target || ($target['role'] === 'admin' && (int)$targetId !== (int)$user['id'])) {
            throw new ApiError('Profile photo was not found.', 404);
        }
        $filename = $target['profile_photo'];
        if (!is_string($filename) || !preg_match('/^[a-f0-9]{48}\.(jpg|png|webp)$/', $filename)) {
            throw new ApiError('Profile photo was not found.', 404);
        }
        $photoPath = __DIR__ . '/profile_photos/' . $filename;
        if (!is_file($photoPath)) {
            throw new ApiError('Profile photo was not found.', 404);
        }
        $mime = match (pathinfo($filename, PATHINFO_EXTENSION)) {
            'jpg' => 'image/jpeg',
            'png' => 'image/png',
            'webp' => 'image/webp',
        };
        header('Content-Type: ' . $mime);
        header('Content-Length: ' . (string)filesize($photoPath));
        header('X-Content-Type-Options: nosniff');
        readfile($photoPath);
        exit;
    }

    if ($action === 'update_profile' && $method === 'POST') {
        $targetAccountId = $body['target_account_id'] ?? $user['account_id'];
        if (!is_string($targetAccountId) || trim($targetAccountId) === '' || strlen($targetAccountId) > 64) {
            throw new ApiError('A valid account is required.', 422);
        }
        $targetAccountId = trim($targetAccountId);
        $isSelf = hash_equals((string)$user['account_id'], $targetAccountId);
        if (!$isSelf) {
            require_admin($user);
        }
        $db->beginTransaction();
        $lookup = $db->prepare('SELECT * FROM users WHERE account_id = ? FOR UPDATE');
        $lookup->execute([$targetAccountId]);
        $target = $lookup->fetch();
        if (!$target || (!$isSelf && $target['role'] !== 'student')) {
            throw new ApiError('Student account was not found.', 404);
        }
        $targetId = (int)$target['id'];
        $expectedVersion = filter_var($body['expected_version'] ?? null, FILTER_VALIDATE_INT);
        if ($expectedVersion === false || $expectedVersion < 1) {
            throw new ApiError('The profile version is missing or invalid.', 422);
        }
        if ($expectedVersion !== (int)$target['profile_version']) {
            log_action(
                $db,
                $userId,
                'account.profile_conflict',
                'user',
                $targetId,
                'Expected version ' . $expectedVersion .
                '; current version ' . (int)$target['profile_version']
            );
            $db->commit();
            throw new ApiError(
                'This profile was changed elsewhere. Refresh it and review the latest values before saving again.',
                409
            );
        }

        $fields = [];
        $allowedFields = ['full_name', 'email', 'contact_number', 'program_section'];
        foreach ($allowedFields as $field) {
            if (!array_key_exists($field, $body)) {
                continue;
            }
            $value = trim((string)$body[$field]);
            $limit = match ($field) {
                'full_name' => 120,
                'email' => 254,
                'contact_number' => 32,
                'program_section' => 80,
            };
            if (strlen($value) > $limit) {
                throw new ApiError('One or more profile fields are too long.', 422);
            }
            if ($field === 'full_name' && $value === '') {
                throw new ApiError('Full name cannot be empty.', 422);
            }
            if ($field === 'email' && $value !== '' && !filter_var($value, FILTER_VALIDATE_EMAIL)) {
                throw new ApiError('Enter a valid email address.', 422);
            }
            $fields[$field] = $value === '' && $field === 'email' ? null : $value;
        }
        if (array_key_exists('account_status', $body)) {
            if ($isSelf || $user['role'] !== 'admin' || $target['role'] !== 'student') {
                throw new ApiError('Only an administrator can change a Student account status.', 403);
            }
            if (!in_array($body['account_status'], ['active', 'suspended'], true)) {
                throw new ApiError('Choose a valid Student account status.', 422);
            }
            $fields['account_status'] = $body['account_status'];
        }
        if ($fields === [] && !array_key_exists('profile_photo_base64', $body)
            && ($body['remove_profile_photo'] ?? false) !== true) {
            throw new ApiError('There are no profile changes to save.', 422);
        }
        if (isset($fields['email'])) {
            $duplicate = $db->prepare('SELECT id FROM users WHERE email = ? AND id <> ? LIMIT 1');
            $duplicate->execute([$fields['email'], (int)$targetId]);
            if ($duplicate->fetchColumn()) {
                throw new ApiError('That email address is already used by another account.', 409);
            }
        }

        $newPhoto = null;
        $newPhotoPath = null;
        $oldPhoto = is_string($target['profile_photo']) ? $target['profile_photo'] : null;
        if (array_key_exists('profile_photo_base64', $body)) {
            $encoded = $body['profile_photo_base64'];
            if (!is_string($encoded) || $encoded === '' || strlen($encoded) > 2_200_000) {
                throw new ApiError('Choose a valid profile image under 1.5 MB.', 422);
            }
            $newPhoto = base64_decode($encoded, true);
            if ($newPhoto === false || strlen($newPhoto) > 1_572_864) {
                throw new ApiError('Choose a valid profile image under 1.5 MB.', 422);
            }
            $imageInfo = @getimagesizefromstring($newPhoto);
            $mime = (new finfo(FILEINFO_MIME_TYPE))->buffer($newPhoto);
            $extension = match ($mime) {
                'image/jpeg' => 'jpg',
                'image/png' => 'png',
                'image/webp' => 'webp',
                default => null,
            };
            if ($imageInfo === false || $extension === null ||
                $imageInfo[0] < 1 || $imageInfo[1] < 1 ||
                $imageInfo[0] > 4000 || $imageInfo[1] > 4000 ||
                $imageInfo[0] * $imageInfo[1] > 16_000_000) {
                throw new ApiError('Profile photos must be valid JPG, PNG, or WEBP images.', 422);
            }
            $photoDirectory = __DIR__ . '/profile_photos';
            if (!is_dir($photoDirectory) && !mkdir($photoDirectory, 0750, true) && !is_dir($photoDirectory)) {
                throw new ApiError('Profile photo storage is unavailable.', 503);
            }
            $newPhotoPath = bin2hex(random_bytes(24)) . '.' . $extension;
            $photoFile = $photoDirectory . '/' . $newPhotoPath;
        } elseif (($body['remove_profile_photo'] ?? false) === true) {
            $fields['profile_photo'] = null;
        }

        try {
            if ($newPhotoPath !== null) {
                $written = file_put_contents($photoFile, $newPhoto, LOCK_EX);
                if ($written !== strlen($newPhoto)) {
                    throw new ApiError('The profile photo could not be saved.', 503);
                }
                $fields['profile_photo'] = $newPhotoPath;
            }
            $fields['profile_version'] = (int)$target['profile_version'] + 1;
            $columns = array_keys($fields);
            $assignments = implode(', ', array_map(static fn(string $column): string => "{$column} = ?", $columns));
            $update = $db->prepare("UPDATE users SET {$assignments} WHERE id = ?");
            $update->execute([...array_values($fields), (int)$targetId]);

            $changedFields = array_values(array_diff($columns, ['profile_photo', 'profile_version']));
            $baseAction = $isSelf ? 'account.profile_updated' : 'account.student_updated';
            log_action(
                $db,
                $userId,
                $baseAction,
                'user',
                (int)$targetId,
                'Changed fields: ' . implode(', ', $changedFields)
            );
            if (array_key_exists('profile_photo_base64', $body)) {
                log_action(
                    $db,
                    $userId,
                    $isSelf ? 'account.photo_uploaded' : 'account.student_photo_updated',
                    'user',
                    (int)$targetId
                );
            }
            if (($body['remove_profile_photo'] ?? false) === true) {
                log_action(
                    $db,
                    $userId,
                    $isSelf ? 'account.photo_removed' : 'account.student_photo_removed',
                    'user',
                    (int)$targetId
                );
            }
            if (array_key_exists('account_status', $body) &&
                $body['account_status'] !== $target['account_status']) {
                log_action(
                    $db,
                    $userId,
                    $body['account_status'] === 'active'
                        ? 'account.student_activated'
                        : 'account.student_suspended',
                    'user',
                    (int)$targetId
                );
            }
            $updated = $db->prepare('SELECT * FROM users WHERE id = ? LIMIT 1');
            $updated->execute([(int)$targetId]);
            $response = [
                'message' => 'Profile updated.',
                'user' => public_user($updated->fetch()),
            ];
            if (isset($idempotencyContext)) {
                $receipt = $db->prepare(
                    'INSERT IGNORE INTO api_idempotency
                     (user_id, operation_id, action, payload_hash, response_status, response_json)
                     VALUES (?, ?, ?, ?, 200, ?)'
                );
                $receipt->execute([
                    $idempotencyContext['user_id'],
                    $idempotencyContext['operation_id'],
                    $idempotencyContext['action'],
                    $idempotencyContext['payload_hash'],
                    json_encode($response, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE),
                ]);
            }
            $db->commit();
        } catch (Throwable $error) {
            if ($db->inTransaction()) {
                $db->rollBack();
            }
            if ($newPhotoPath !== null && isset($photoFile) && is_file($photoFile)) {
                unlink($photoFile);
            }
            throw $error;
        }
        if (($body['remove_profile_photo'] ?? false) === true || $newPhotoPath !== null) {
            if ($oldPhoto !== null && preg_match('/^[a-f0-9]{48}\.(jpg|png|webp)$/', $oldPhoto)) {
                $oldPhotoFile = __DIR__ . '/profile_photos/' . $oldPhoto;
                if (is_file($oldPhotoFile)) {
                    unlink($oldPhotoFile);
                }
            }
        }
        respond($response);
    }

    if ($action === 'change_password' && $method === 'POST') {
        $currentPassword = require_value($body['current_password'] ?? null, 'current password');
        $newPassword = require_value($body['new_password'] ?? null, 'new password');
        if (!password_verify($currentPassword, $user['password_hash'])) {
            throw new ApiError('The current password is incorrect.', 403);
        }
        if (strlen($newPassword) < 8 || !preg_match('/[A-Z]/', $newPassword) || !preg_match('/[a-z]/', $newPassword)
            || !preg_match('/\d/', $newPassword) || !preg_match('/[^A-Za-z0-9]/', $newPassword)) {
            throw new ApiError('Use at least 8 characters with uppercase, lowercase, a number, and a special character.', 422);
        }
        $db->beginTransaction();
        $statement = $db->prepare('UPDATE users SET password_hash = ? WHERE id = ?');
        $statement->execute([password_hash($newPassword, PASSWORD_DEFAULT), $userId]);
        preg_match('/^Bearer\s+([a-f0-9]{64})$/i', authorization_header(), $matches);
        $revoke = $db->prepare('DELETE FROM auth_sessions WHERE user_id = ? AND token_hash <> ?');
        $revoke->execute([$userId, hash('sha256', $matches[1])]);
        log_action($db, $userId, 'account.password_changed', 'user', $userId);
        $db->commit();
        respond(['message' => 'Password updated.']);
    }

    if ($action === 'equipment' && $method === 'GET') {
        $limit = filter_var($_GET['limit'] ?? 30, FILTER_VALIDATE_INT);
        $offset = filter_var($_GET['offset'] ?? 0, FILTER_VALIDATE_INT);
        if ($limit === false || $limit < 1 || $limit > 100 || $offset === false || $offset < 0) {
            throw new ApiError('Equipment page must use a limit from 1 to 100 and a non-negative offset.', 422);
        }
        respond(equipment_query($db, [
            'limit' => $limit,
            'offset' => $offset,
            'search' => is_string($_GET['search'] ?? null) ? $_GET['search'] : '',
            'category' => is_string($_GET['category'] ?? null) ? $_GET['category'] : '',
            'status' => is_string($_GET['status'] ?? null) ? $_GET['status'] : '',
        ]));
    }

    if ($action === 'equipment_detail' && $method === 'GET') {
        $code = require_value($_GET['equipment_code'] ?? null, 'equipment code');
        $result = equipment_query($db, [
            'equipment_code' => $code,
            'limit' => 1,
            'include_details' => true,
        ]);
        if (!$result['items']) {
            throw new ApiError('Equipment was not found.', 404);
        }
        $detail = ['item' => $result['items'][0]];
        if ($user['role'] === 'admin') {
            $history = $db->prepare(
                'SELECT b.transaction_code, b.borrowed_at, b.due_at, b.returned_at, b.status,
                        r.request_code, r.status AS request_status, r.requested_at,
                        u.account_id, u.full_name AS student_name
                 FROM borrowing_transactions b
                 JOIN borrowing_requests r ON r.id = b.request_id
                 JOIN users u ON u.id = b.user_id
                 WHERE b.equipment_id = ? ORDER BY b.id DESC LIMIT 100'
            );
            $history->execute([(int)$detail['item']['id']]);
            $returns = $db->prepare(
                'SELECT rr.reported_condition, rr.status, rr.reported_at, rr.reviewed_at,
                        b.transaction_code, u.account_id, u.full_name AS student_name
                 FROM return_reports rr
                 JOIN borrowing_transactions b ON b.id = rr.transaction_id
                 JOIN users u ON u.id = rr.user_id
                 WHERE b.equipment_id = ? ORDER BY rr.id DESC LIMIT 100'
            );
            $returns->execute([(int)$detail['item']['id']]);
            $exceptions = $db->prepare(
                'SELECT exception_type, quantity, notes, status, created_at, resolved_at
                 FROM inventory_exceptions WHERE equipment_id = ? ORDER BY id DESC LIMIT 100'
            );
            $exceptions->execute([(int)$detail['item']['id']]);
            $detail['borrowings'] = $history->fetchAll();
            $detail['returns'] = $returns->fetchAll();
            $detail['exceptions'] = $exceptions->fetchAll();
        }
        respond($detail);
    }

    if ($action === 'requests' && $method === 'GET') {
        $sql = 'SELECT r.id, r.request_code, r.status, r.request_note, r.requested_at, r.reviewed_at,
                       e.equipment_code, e.name AS item_name, e.image_asset, e.category,
                       u.id AS student_id, u.account_id, u.full_name AS student_name
                FROM borrowing_requests r
                JOIN equipment e ON e.id = r.equipment_id
                JOIN users u ON u.id = r.user_id';
        if ($user['role'] !== 'admin') {
            $statement = $db->prepare($sql . ' WHERE r.user_id = ? ORDER BY r.requested_at DESC');
            $statement->execute([$userId]);
        } else {
            $statement = $db->query($sql . ' ORDER BY r.requested_at DESC');
        }
        respond(['requests' => $statement->fetchAll()]);
    }

    if ($action === 'create_request' && $method === 'POST') {
        if ($user['role'] !== 'student') {
            throw new ApiError('Only student accounts can request equipment.', 403);
        }
        $code = require_value($body['equipment_code'] ?? null, 'equipment code');
        $db->beginTransaction();
        $equipmentQuery = $db->prepare(
            'SELECT id, name FROM equipment
             WHERE equipment_code = ? AND is_active = 1
               AND inventory_status = "active" AND item_condition <> "Damaged"
             FOR UPDATE'
        );
        $equipmentQuery->execute([$code]);
        $item = $equipmentQuery->fetch();
        if (!$item) {
            throw new ApiError('Equipment was not found.', 404);
        }
        $requestCode = isset($body['request_code']) && is_string($body['request_code'])
            ? require_value($body['request_code'], 'request code')
            : null;
        if ($requestCode !== null) {
            $existingCode = $db->prepare(
                'SELECT id FROM borrowing_requests WHERE request_code = ? AND user_id = ? LIMIT 1'
            );
            $existingCode->execute([$requestCode, $userId]);
            $existingRequestId = $existingCode->fetchColumn();
            if ($existingRequestId) {
                $db->commit();
                respond([
                    'message' => 'Borrowing request was already synchronized.',
                    'request_id' => (int)$existingRequestId,
                    'request_code' => $requestCode,
                ]);
            }
        }
        if (available_stock($db, (int)$item['id']) < 1) {
            throw new ApiError('This item is currently unavailable.', 409);
        }
        $existing = $db->prepare(
            'SELECT r.id FROM borrowing_requests r
             WHERE r.user_id = ? AND r.equipment_id = ?
               AND (r.status = "pending" OR EXISTS (
                 SELECT 1 FROM borrowing_transactions b
                 WHERE b.request_id = r.id AND b.status IN ("active", "return_pending")
               ))
             LIMIT 1'
        );
        $existing->execute([$userId, (int)$item['id']]);
        if ($existing->fetchColumn()) {
            throw new ApiError('You already have an open request for this item.', 409);
        }
        $insert = $db->prepare(
            'INSERT INTO borrowing_requests (request_code, user_id, equipment_id, request_note)
             VALUES (?, ?, ?, ?)'
        );
        $insert->execute([make_code('TMP-', random_int(100000000, 999999999)), $userId, (int)$item['id'], isset($body['note']) ? substr((string)$body['note'], 0, 500) : null]);
        $requestId = (int)$db->lastInsertId();
        $requestCode = $requestCode ?? make_code('REQ-', $requestId);
        $update = $db->prepare('UPDATE borrowing_requests SET request_code = ? WHERE id = ?');
        $update->execute([$requestCode, $requestId]);
        log_action($db, $userId, 'request.created', 'borrowing_request', $requestId, $item['name']);
        $db->commit();
        respond([
            'message' => 'Borrowing request submitted.',
            'request_id' => $requestId,
            'request_code' => $requestCode,
        ], 201);
    }

    if ($action === 'review_request' && $method === 'POST') {
        require_admin($user);
        $requestCode = $body['request_code'] ?? null;
        $requestId = filter_var($body['request_id'] ?? null, FILTER_VALIDATE_INT);
        $decision = $body['decision'] ?? null;
        if ((!$requestId && !is_string($requestCode)) || !in_array($decision, ['approved', 'rejected'], true)) {
            throw new ApiError('Choose a request and a valid review decision.', 422);
        }
        $db->beginTransaction();
        $requestQuery = $requestCode !== null
            ? $db->prepare('SELECT * FROM borrowing_requests WHERE request_code = ? FOR UPDATE')
            : $db->prepare('SELECT * FROM borrowing_requests WHERE id = ? FOR UPDATE');
        $requestQuery->execute([$requestCode ?? $requestId]);
        $request = $requestQuery->fetch();
        if (!$request || $request['status'] !== 'pending') {
            throw new ApiError('This request is no longer awaiting review.', 409);
        }
        if ($decision === 'approved') {
            $equipmentLock = $db->prepare('SELECT id FROM equipment WHERE id = ? AND is_active = 1 FOR UPDATE');
            $equipmentLock->execute([(int)$request['equipment_id']]);
            if (!$equipmentLock->fetchColumn() || available_stock($db, (int)$request['equipment_id']) < 1) {
                throw new ApiError('No available stock remains for this request.', 409);
            }
            $insert = $db->prepare(
                'INSERT INTO borrowing_transactions
                 (transaction_code, request_id, user_id, equipment_id, borrowed_at, due_at)
                 VALUES (?, ?, ?, ?, NOW(), DATE_ADD(NOW(), INTERVAL 8 HOUR))'
            );
            $insert->execute([make_code('TMP-', random_int(100000000, 999999999)), (int)$request['id'], (int)$request['user_id'], (int)$request['equipment_id']]);
            $transactionId = (int)$db->lastInsertId();
            $codeUpdate = $db->prepare('UPDATE borrowing_transactions SET transaction_code = ? WHERE id = ?');
            $codeUpdate->execute([make_code('BOR-', $transactionId), $transactionId]);
        }
        $update = $db->prepare(
            'UPDATE borrowing_requests SET status = ?, reviewed_by = ?, reviewed_at = NOW() WHERE id = ?'
        );
        $requestId = (int)$request['id'];
        $update->execute([$decision, $userId, $requestId]);
        log_action($db, $userId, 'request.' . $decision, 'borrowing_request', $requestId);
        $db->commit();
        respond(['message' => 'Request ' . $decision . '.']);
    }

    if ($action === 'borrowings' && $method === 'GET') {
        $sql = 'SELECT b.id, b.transaction_code, b.borrowed_at, b.due_at, b.returned_at, b.status,
                       r.request_code, r.requested_at, r.reviewed_at,
                       e.equipment_code, e.name AS item_name, e.image_asset,
                       u.account_id, u.full_name AS student_name
                FROM borrowing_transactions b
                JOIN equipment e ON e.id = b.equipment_id
                JOIN users u ON u.id = b.user_id
                JOIN borrowing_requests r ON r.id = b.request_id';
        if ($user['role'] !== 'admin') {
            $statement = $db->prepare($sql . ' WHERE b.user_id = ? ORDER BY b.borrowed_at DESC');
            $statement->execute([$userId]);
        } else {
            $statement = $db->query($sql . ' ORDER BY b.borrowed_at DESC');
        }
        respond(['borrowings' => $statement->fetchAll()]);
    }

    if ($action === 'create_return' && $method === 'POST') {
        if ($user['role'] !== 'student') {
            throw new ApiError('Only student accounts can submit return reports.', 403);
        }
        $transactionId = filter_var($body['transaction_id'] ?? null, FILTER_VALIDATE_INT);
        $condition = $body['condition'] ?? null;
        $requestCode = $body['request_code'] ?? null;
        if ((!$transactionId && !is_string($requestCode)) || !in_array($condition, ['Good', 'Damaged', 'Missing'], true)) {
            throw new ApiError('Choose an active borrowing and a valid condition.', 422);
        }
        $photo = null;
        if (isset($body['photo_base64']) && $body['photo_base64'] !== '') {
            if (!is_string($body['photo_base64']) || strlen($body['photo_base64']) > 2800000) {
                throw new ApiError('Return photos must be smaller than 2 MB.', 413);
            }
            $photo = base64_decode($body['photo_base64'], true);
            if ($photo === false || strlen($photo) > 2097152) {
                throw new ApiError('The selected return photo is invalid or too large.', 422);
            }
        }
        $db->beginTransaction();
        $borrowQuery = $requestCode !== null
            ? $db->prepare(
                'SELECT b.id FROM borrowing_transactions b
                 JOIN borrowing_requests r ON r.id = b.request_id
                 WHERE r.request_code = ? AND b.user_id = ? AND b.status = "active" FOR UPDATE'
            )
            : $db->prepare(
                'SELECT id FROM borrowing_transactions
                 WHERE id = ? AND user_id = ? AND status = "active" FOR UPDATE'
            );
        $borrowQuery->execute([$requestCode ?? $transactionId, $userId]);
        $resolvedTransactionId = $borrowQuery->fetchColumn();
        if (!$resolvedTransactionId) {
            throw new ApiError('This borrowing is not available for return.', 409);
        }
        $transactionId = (int)$resolvedTransactionId;
        $insert = $db->prepare(
            'INSERT INTO return_reports (transaction_id, user_id, reported_condition, photo_data)
             VALUES (?, ?, ?, ?)'
        );
        $insert->bindValue(1, $transactionId, PDO::PARAM_INT);
        $insert->bindValue(2, $userId, PDO::PARAM_INT);
        $insert->bindValue(3, $condition);
        $insert->bindValue(4, $photo, $photo === null ? PDO::PARAM_NULL : PDO::PARAM_LOB);
        $insert->execute();
        $reportId = (int)$db->lastInsertId();
        $update = $db->prepare('UPDATE borrowing_transactions SET status = "return_pending" WHERE id = ?');
        $update->execute([$transactionId]);
        log_action($db, $userId, 'return.submitted', 'return_report', $reportId, $condition);
        $db->commit();
        respond(['message' => 'Return report sent for staff review.'], 201);
    }

    if ($action === 'returns' && $method === 'GET') {
        $sql = 'SELECT r.id, r.transaction_id, r.reported_condition, r.status, r.reported_at, r.reviewed_at,
                       r.photo_data IS NOT NULL AS has_photo, b.transaction_code,
                       b.borrowed_at, b.due_at, b.returned_at, b.status AS borrowing_status,
                       b.borrowed_at, b.due_at, b.returned_at, b.status AS borrowing_status,
                       b.equipment_id, b.user_id,
                       q.request_code, e.equipment_code, e.name AS item_name,
                       u.account_id, u.full_name AS student_name
                FROM return_reports r
                JOIN borrowing_transactions b ON b.id = r.transaction_id
                JOIN borrowing_requests q ON q.id = b.request_id
                JOIN equipment e ON e.id = b.equipment_id
                JOIN users u ON u.id = r.user_id';
        if ($user['role'] !== 'admin') {
            $statement = $db->prepare($sql . ' WHERE r.user_id = ? ORDER BY r.reported_at DESC');
            $statement->execute([$userId]);
        } else {
            $statement = $db->query($sql . ' ORDER BY r.reported_at DESC');
        }
        respond(['returns' => $statement->fetchAll()]);
    }

    if ($action === 'return_photo' && $method === 'POST') {
        require_admin($user);
        $reportId = filter_var($body['report_id'] ?? null, FILTER_VALIDATE_INT);
        if (!$reportId) {
            throw new ApiError('Choose a return report.', 422);
        }
        $statement = $db->prepare(
            'SELECT photo_data FROM return_reports WHERE id = ? AND photo_data IS NOT NULL'
        );
        $statement->execute([$reportId]);
        $photo = $statement->fetchColumn();
        if ($photo === false) {
            throw new ApiError('This return report has no photo.', 404);
        }
        respond(['photo_base64' => base64_encode($photo)]);
    }

    if ($action === 'review_return' && $method === 'POST') {
        require_admin($user);
        $reportId = filter_var($body['report_id'] ?? null, FILTER_VALIDATE_INT);
        $requestCode = $body['request_code'] ?? null;
        $decision = $body['decision'] ?? null;
        if ((!$reportId && !is_string($requestCode)) || !in_array($decision, ['accept', 'reject'], true)) {
            throw new ApiError('Choose a return report and a valid decision.', 422);
        }
        $db->beginTransaction();
        $reportQuery = $requestCode !== null
            ? $db->prepare(
                'SELECT rr.*, b.equipment_id, b.user_id, b.id AS borrowing_id
                 FROM return_reports rr
                 JOIN borrowing_transactions b ON b.id = rr.transaction_id
                 JOIN borrowing_requests q ON q.id = b.request_id
                 WHERE q.request_code = ? AND rr.status = "pending"
                 ORDER BY rr.id DESC LIMIT 1 FOR UPDATE'
            )
            : $db->prepare(
                'SELECT rr.*, b.equipment_id, b.user_id, b.id AS borrowing_id
                 FROM return_reports rr
                 JOIN borrowing_transactions b ON b.id = rr.transaction_id
                 WHERE rr.id = ? FOR UPDATE'
            );
        $reportQuery->execute([$requestCode ?? $reportId]);
        $report = $reportQuery->fetch();
        if (!$report || $report['status'] !== 'pending') {
            throw new ApiError('This return report is no longer awaiting review.', 409);
        }
        if ($decision === 'reject') {
            $reportId = (int)$report['id'];
            $update = $db->prepare('UPDATE return_reports SET status = "rejected", reviewed_by = ?, reviewed_at = NOW() WHERE id = ?');
            $update->execute([$userId, $reportId]);
            $borrow = $db->prepare('UPDATE borrowing_transactions SET status = "active" WHERE id = ?');
            $borrow->execute([(int)$report['borrowing_id']]);
        } else {
            $reportId = (int)$report['id'];
            $update = $db->prepare('UPDATE return_reports SET status = "accepted", reviewed_by = ?, reviewed_at = NOW() WHERE id = ?');
            $update->execute([$userId, $reportId]);
            $newStatus = $report['reported_condition'] === 'Missing' ? 'missing' : 'returned';
            $borrow = $db->prepare(
                'UPDATE borrowing_transactions SET status = ?, returned_at = NOW() WHERE id = ?'
            );
            $borrow->execute([$newStatus, (int)$report['borrowing_id']]);
            if ($report['reported_condition'] !== 'Good') {
                $exception = $db->prepare(
                    'INSERT INTO inventory_exceptions
                     (equipment_id, transaction_id, reported_by, exception_type, quantity, notes)
                     VALUES (?, ?, ?, ?, 1, ?)'
                );
                $exception->execute([
                    (int)$report['equipment_id'],
                    (int)$report['borrowing_id'],
                    $userId,
                    strtolower($report['reported_condition']),
                    'Student return report: ' . $report['reported_condition'],
                ]);
            }
            if ($report['reported_condition'] === 'Missing') {
                $penalty = $db->prepare(
                    'INSERT INTO penalties (user_id, transaction_id, amount, reason)
                     VALUES (?, ?, 200.00, "Missing equipment")'
                );
                $penalty->execute([(int)$report['user_id'], (int)$report['borrowing_id']]);
            }
        }
        log_action($db, $userId, 'return.' . $decision, 'return_report', $reportId, $report['reported_condition']);
        $db->commit();
        respond(['message' => 'Return report ' . ($decision === 'accept' ? 'accepted' : 'rejected') . '.']);
    }

    if ($action === 'penalties' && $method === 'GET') {
        $sql = 'SELECT p.id, p.transaction_id, p.amount, p.amount_paid, p.reason, p.status, p.created_at,
                       b.transaction_code, u.account_id, u.full_name AS student_name
                FROM penalties p
                JOIN users u ON u.id = p.user_id
                LEFT JOIN borrowing_transactions b ON b.id = p.transaction_id';
        if ($user['role'] !== 'admin') {
            $statement = $db->prepare($sql . ' WHERE p.user_id = ? ORDER BY p.created_at DESC');
            $statement->execute([$userId]);
        } else {
            $statement = $db->query($sql . ' ORDER BY p.created_at DESC');
        }
        respond(['penalties' => $statement->fetchAll(), 'outstanding_balance' => unpaid_balance($db, $userId)]);
    }

    if ($action === 'payments' && $method === 'GET') {
        $sql = 'SELECT p.id, p.payment_code, p.amount, p.method, p.status, p.reference_note,
                       p.created_at, p.reviewed_at,
                       u.account_id, u.full_name AS student_name
                FROM payments p JOIN users u ON u.id = p.user_id';
        if ($user['role'] !== 'admin') {
            $statement = $db->prepare($sql . ' WHERE p.user_id = ? ORDER BY p.created_at DESC');
            $statement->execute([$userId]);
        } else {
            $statement = $db->query($sql . ' ORDER BY p.created_at DESC');
        }
        respond(['payments' => $statement->fetchAll()]);
    }

    if ($action === 'create_payment' && $method === 'POST') {
        if ($user['role'] !== 'student') {
            throw new ApiError('Only student accounts can submit payments.', 403);
        }
        $amount = filter_var($body['amount'] ?? null, FILTER_VALIDATE_FLOAT);
        $paymentMethod = $body['method'] ?? null;
        if (!$amount || $amount <= 0 || !in_array($paymentMethod, ['GCash', 'Maya', 'Cash'], true)) {
            throw new ApiError('Enter a valid payment amount and method.', 422);
        }
        $db->beginTransaction();
        $userLock = $db->prepare('SELECT id FROM users WHERE id = ? AND role = "student" FOR UPDATE');
        $userLock->execute([$userId]);
        if (!$userLock->fetchColumn()) {
            throw new ApiError('Student account was not found.', 404);
        }
        $paymentCode = isset($body['payment_code']) && is_string($body['payment_code'])
            ? require_value($body['payment_code'], 'payment code')
            : null;
        if ($paymentCode !== null) {
            $existingPayment = $db->prepare(
                'SELECT id FROM payments WHERE payment_code = ? AND user_id = ? LIMIT 1'
            );
            $existingPayment->execute([$paymentCode, $userId]);
            $existingPaymentId = $existingPayment->fetchColumn();
            if ($existingPaymentId) {
                $db->commit();
                respond([
                    'message' => 'Payment record was already synchronized.',
                    'payment_id' => (int)$existingPaymentId,
                    'payment_code' => $paymentCode,
                ]);
            }
        }
        $balance = unpaid_balance($db, $userId);
        $reservedQuery = $db->prepare(
            'SELECT COALESCE(SUM(amount), 0) FROM payments WHERE user_id = ? AND status = "pending"'
        );
        $reservedQuery->execute([$userId]);
        $available = max(0, $balance - (float)$reservedQuery->fetchColumn());
        if ($amount > $available + 0.001) {
            throw new ApiError('Payment amount exceeds the outstanding balance available for settlement.', 409);
        }
        $insert = $db->prepare(
            'INSERT INTO payments (payment_code, user_id, amount, method, reference_note)
             VALUES (?, ?, ?, ?, ?)'
        );
        $insert->execute([make_code('TMP-', random_int(100000000, 999999999)), $userId, number_format($amount, 2, '.', ''), $paymentMethod, isset($body['reference_note']) ? substr((string)$body['reference_note'], 0, 160) : null]);
        $paymentId = (int)$db->lastInsertId();
        $update = $db->prepare('UPDATE payments SET payment_code = ? WHERE id = ?');
        $paymentCode = $paymentCode ?? make_code('PAY-', $paymentId);
        $update->execute([$paymentCode, $paymentId]);
        log_action($db, $userId, 'payment.submitted', 'payment', $paymentId, $paymentMethod);
        $db->commit();
        respond([
            'message' => 'Payment record sent for staff verification.',
            'payment_id' => $paymentId,
            'payment_code' => $paymentCode,
        ], 201);
    }

    if ($action === 'review_payment' && $method === 'POST') {
        require_admin($user);
        $paymentId = filter_var($body['payment_id'] ?? null, FILTER_VALIDATE_INT);
        $paymentCode = $body['payment_code'] ?? null;
        $decision = $body['decision'] ?? null;
        if ((!$paymentId && !is_string($paymentCode)) || !in_array($decision, ['verify', 'reject'], true)) {
            throw new ApiError('Choose a payment and a valid decision.', 422);
        }
        $db->beginTransaction();
        $paymentQuery = $paymentCode !== null
            ? $db->prepare('SELECT * FROM payments WHERE payment_code = ? FOR UPDATE')
            : $db->prepare('SELECT * FROM payments WHERE id = ? FOR UPDATE');
        $paymentQuery->execute([$paymentCode ?? $paymentId]);
        $payment = $paymentQuery->fetch();
        if (!$payment || $payment['status'] !== 'pending') {
            throw new ApiError('This payment is no longer awaiting verification.', 409);
        }
        $newStatus = $decision === 'verify' ? 'verified' : 'rejected';
        $update = $db->prepare('UPDATE payments SET status = ?, reviewed_by = ?, reviewed_at = NOW() WHERE id = ?');
        $paymentId = (int)$payment['id'];
        $update->execute([$newStatus, $userId, $paymentId]);
        if ($decision === 'verify') {
            $remaining = (float)$payment['amount'];
            $penaltyQuery = $db->prepare(
                'SELECT id, amount, amount_paid FROM penalties
                 WHERE user_id = ? AND status = "unpaid" ORDER BY created_at, id FOR UPDATE'
            );
            $penaltyQuery->execute([(int)$payment['user_id']]);
            foreach ($penaltyQuery->fetchAll() as $penalty) {
                if ($remaining <= 0) {
                    break;
                }
                $due = max(0, (float)$penalty['amount'] - (float)$penalty['amount_paid']);
                $paid = min($remaining, $due);
                $totalPaid = (float)$penalty['amount_paid'] + $paid;
                $status = $totalPaid + 0.001 >= (float)$penalty['amount'] ? 'paid' : 'unpaid';
                $penaltyUpdate = $db->prepare('UPDATE penalties SET amount_paid = ?, status = ?, settled_at = IF(? = "paid", NOW(), settled_at) WHERE id = ?');
                $penaltyUpdate->execute([number_format($totalPaid, 2, '.', ''), $status, $status, (int)$penalty['id']]);
                $remaining -= $paid;
            }
            if ($remaining > 0.01) {
                throw new ApiError('The outstanding balance changed; this payment cannot be verified.', 409);
            }
        }
        log_action($db, $userId, 'payment.' . $newStatus, 'payment', (int)$paymentId);
        $db->commit();
        respond(['message' => 'Payment ' . $newStatus . '.']);
    }

    if ($action === 'admin_stats' && $method === 'GET') {
        require_admin($user);
        $counts = $db->query(
            'SELECT
               (SELECT COUNT(*) FROM equipment) AS equipment_count,
               (SELECT COALESCE(SUM(total_stock), 0) FROM equipment) AS total_stock,
               (SELECT COALESCE(SUM(CASE
                    WHEN e.is_active = 0
                      OR e.inventory_status IN ("retired", "maintenance", "under maintenance", "under_maintenance", "lost", "damaged")
                      OR e.item_condition = "Damaged"
                      OR COALESCE(x.damaged_quantity, 0) > 0 THEN 0
                    ELSE GREATEST(0, e.total_stock
                      - COALESCE(b.borrowed_quantity, 0)
                      - COALESCE(x.reserved_quantity, 0)) END), 0)
                FROM equipment e
                LEFT JOIN (
                    SELECT equipment_id, COUNT(*) AS borrowed_quantity
                    FROM borrowing_transactions
                    WHERE status IN ("active", "return_pending")
                    GROUP BY equipment_id
                ) b ON b.equipment_id = e.id
                LEFT JOIN (
                    SELECT equipment_id, SUM(quantity) AS reserved_quantity,
                           SUM(CASE WHEN exception_type = "damaged" THEN quantity ELSE 0 END) AS damaged_quantity
                    FROM inventory_exceptions WHERE status = "open"
                    GROUP BY equipment_id
                ) x ON x.equipment_id = e.id) AS available_quantity,
               (SELECT COUNT(*) FROM borrowing_transactions WHERE status IN ("active", "return_pending")) AS borrowed_quantity,
               (SELECT COUNT(*) FROM equipment WHERE is_active = 0 OR inventory_status = "retired") AS retired_count,
               (SELECT COUNT(*) FROM equipment WHERE item_condition = "Damaged" OR inventory_status = "damaged") AS damaged_count,
               (SELECT COUNT(*) FROM equipment WHERE inventory_status IN ("maintenance", "under maintenance", "under_maintenance")) AS maintenance_count,
               (SELECT COUNT(*) FROM equipment WHERE inventory_status = "lost") AS lost_count,
               (SELECT COUNT(*) FROM borrowing_requests WHERE status = "pending") AS pending_requests,
               (SELECT COUNT(*) FROM borrowing_transactions WHERE status IN ("active", "return_pending")) AS active_borrowings,
               (SELECT COUNT(*) FROM return_reports WHERE status = "pending") AS pending_returns,
               (SELECT COUNT(*) FROM payments WHERE status = "pending") AS pending_payments,
               (SELECT COUNT(*) FROM inventory_exceptions WHERE status = "open") AS open_exceptions,
               (SELECT COUNT(*) FROM users WHERE role = "student" AND account_status = "active") AS student_count'
        )->fetch();
        respond(['stats' => $counts]);
    }

    if ($action === 'admin_users' && $method === 'GET') {
        require_admin($user);
        $statement = $db->query(
            'SELECT id, account_id, full_name, role, email, program_section, contact_number,
                    account_status, profile_photo, profile_version, updated_at, created_at
             FROM users ORDER BY role, full_name'
        );
        respond(['users' => $statement->fetchAll()]);
    }

    if ($action === 'student_account' && $method === 'GET') {
        require_admin($user);
        $accountId = require_value($_GET['account_id'] ?? null, 'student account ID');
        $profileQuery = $db->prepare(
            'SELECT id, account_id, full_name, role, email, program_section, contact_number,
                    account_status, profile_photo, profile_version, created_at, updated_at
             FROM users WHERE account_id = ? AND role = "student" LIMIT 1'
        );
        $profileQuery->execute([$accountId]);
        $profile = $profileQuery->fetch();
        if (!$profile) {
            throw new ApiError('Student account was not found.', 404);
        }
        $studentId = (int)$profile['id'];
        $queryRows = static function (PDO $db, string $sql, array $parameters): array {
            $query = $db->prepare($sql);
            $query->execute($parameters);
            return $query->fetchAll();
        };
        respond([
            'profile' => $profile,
            'requests' => $queryRows(
                $db,
                'SELECT r.request_code, r.status, r.requested_at, r.reviewed_at,
                        e.equipment_code, e.name AS item_name
                 FROM borrowing_requests r JOIN equipment e ON e.id = r.equipment_id
                 WHERE r.user_id = ? ORDER BY r.id DESC LIMIT 100',
                [$studentId]
            ),
            'borrowings' => $queryRows(
                $db,
                'SELECT b.transaction_code, b.status, b.borrowed_at, b.due_at, b.returned_at,
                        e.equipment_code, e.name AS item_name
                 FROM borrowing_transactions b JOIN equipment e ON e.id = b.equipment_id
                 WHERE b.user_id = ? ORDER BY b.id DESC LIMIT 100',
                [$studentId]
            ),
            'returns' => $queryRows(
                $db,
                'SELECT rr.id, rr.status, rr.reported_condition, rr.reported_at, rr.reviewed_at,
                        e.equipment_code, e.name AS item_name, b.transaction_code
                 FROM return_reports rr
                 JOIN borrowing_transactions b ON b.id = rr.transaction_id
                 JOIN equipment e ON e.id = b.equipment_id
                 WHERE rr.user_id = ? ORDER BY rr.id DESC LIMIT 100',
                [$studentId]
            ),
            'penalties' => $queryRows(
                $db,
                'SELECT id, amount, amount_paid, reason, status, created_at, settled_at
                 FROM penalties WHERE user_id = ? ORDER BY id DESC LIMIT 100',
                [$studentId]
            ),
            'payments' => $queryRows(
                $db,
                'SELECT payment_code, amount, method, status, reference_note, created_at, reviewed_at
                 FROM payments WHERE user_id = ? ORDER BY id DESC LIMIT 100',
                [$studentId]
            ),
            'activities' => $queryRows(
                $db,
                'SELECT id, actor_id, action, entity_type, entity_id, details, created_at
                 FROM system_logs
                 WHERE (entity_type = "user" AND entity_id = ?) OR actor_id = ?
                 ORDER BY id DESC LIMIT 100',
                [$studentId, $studentId]
            ),
        ]);
    }

    if ($action === 'exceptions' && $method === 'GET') {
        require_admin($user);
        $statement = $db->query(
            'SELECT x.id, x.exception_type, x.quantity, x.notes, x.status, x.created_at, x.resolved_at,
                    e.equipment_code, e.name AS item_name, u.account_id,
                    u.full_name AS reported_by_name, b.transaction_code
             FROM inventory_exceptions x
             JOIN equipment e ON e.id = x.equipment_id
             JOIN users u ON u.id = x.reported_by
             LEFT JOIN borrowing_transactions b ON b.id = x.transaction_id
             ORDER BY x.created_at DESC'
        );
        respond(['exceptions' => $statement->fetchAll()]);
    }

    if ($action === 'mark_missing' && $method === 'POST') {
        require_admin($user);
        $code = require_value($body['equipment_code'] ?? null, 'equipment code');
        $db->beginTransaction();
        $statement = $db->prepare('SELECT id FROM equipment WHERE equipment_code = ? AND is_active = 1 FOR UPDATE');
        $statement->execute([$code]);
        $equipmentId = $statement->fetchColumn();
        if (!$equipmentId || available_stock($db, (int)$equipmentId) < 1) {
            throw new ApiError('No available unit can be marked missing.', 409);
        }
        $insert = $db->prepare(
            'INSERT INTO inventory_exceptions (equipment_id, reported_by, exception_type, notes)
             VALUES (?, ?, "missing", ?)'
        );
        $insert->execute([(int)$equipmentId, $userId, isset($body['notes']) ? substr((string)$body['notes'], 0, 500) : 'Marked missing during stock check.']);
        $exceptionId = (int)$db->lastInsertId();
        log_action($db, $userId, 'inventory.exception.created', 'inventory_exception', $exceptionId, $code);
        $db->commit();
        respond(['message' => 'Equipment marked missing.']);
    }

    if ($action === 'resolve_exception' && $method === 'POST') {
        require_admin($user);
        $exceptionId = filter_var($body['exception_id'] ?? null, FILTER_VALIDATE_INT);
        $equipmentCode = $body['equipment_code'] ?? null;
        $exceptionType = $body['exception_type'] ?? null;
        if (!$exceptionId && (!is_string($equipmentCode) || !is_string($exceptionType))) {
            throw new ApiError('Choose an inventory exception.', 422);
        }
        if ($equipmentCode !== null) {
            $lookup = $db->prepare(
                'SELECT x.id FROM inventory_exceptions x
                 JOIN equipment e ON e.id = x.equipment_id
                 WHERE e.equipment_code = ? AND x.exception_type = ? AND x.status = "open"
                 ORDER BY x.id DESC LIMIT 1'
            );
            $lookup->execute([$equipmentCode, $exceptionType]);
            $exceptionId = $lookup->fetchColumn();
            if ($exceptionId) {
                $statement = $db->prepare(
                    'UPDATE inventory_exceptions SET status = "resolved", resolved_at = NOW()
                     WHERE id = ? AND status = "open"'
                );
                $statement->execute([(int)$exceptionId]);
            }
        } else {
            $statement = $db->prepare(
                'UPDATE inventory_exceptions SET status = "resolved", resolved_at = NOW()
                 WHERE id = ? AND status = "open"'
            );
            $statement->execute([$exceptionId]);
        }
        if ($statement->rowCount() === 0) {
            throw new ApiError('This exception is already resolved or was not found.', 404);
        }
        log_action($db, $userId, 'inventory.exception.resolved', 'inventory_exception', (int)$exceptionId);
        respond(['message' => 'Inventory exception resolved.']);
    }

    if ($action === 'adjust_stock' && $method === 'POST') {
        require_admin($user);
        $code = require_value($body['equipment_code'] ?? null, 'equipment code');
        $delta = filter_var($body['delta'] ?? null, FILTER_VALIDATE_INT);
        if ($delta === false || $delta === 0) {
            throw new ApiError('Stock adjustment must be a non-zero whole number.', 422);
        }
        $db->beginTransaction();
        $lock = $db->prepare('SELECT id, total_stock FROM equipment WHERE equipment_code = ? AND is_active = 1 FOR UPDATE');
        $lock->execute([$code]);
        $item = $lock->fetch();
        if (!$item) {
            throw new ApiError('Equipment was not found.', 404);
        }
        $updatedStock = (int)$item['total_stock'] + $delta;
        $inUse = (int)$db->query(
            'SELECT COUNT(*) FROM borrowing_transactions WHERE equipment_id = ' . (int)$item['id'] . ' AND status IN ("active", "return_pending")'
        )->fetchColumn();
        $reserved = $db->query(
            'SELECT COALESCE(SUM(quantity), 0) FROM inventory_exceptions WHERE equipment_id = ' . (int)$item['id'] . ' AND status = "open"'
        )->fetchColumn();
        if ($updatedStock < $inUse + (int)$reserved) {
            throw new ApiError('Stock cannot be lower than units currently borrowed or recorded missing/damaged.', 409);
        }
        $update = $db->prepare('UPDATE equipment SET total_stock = ? WHERE id = ?');
        $update->execute([$updatedStock, (int)$item['id']]);
        log_action($db, $userId, 'inventory.stock_adjusted', 'equipment', (int)$item['id'], 'Delta: ' . $delta);
        $db->commit();
        respond(['message' => 'Stock updated.', 'total_stock' => $updatedStock]);
    }

    if ($action === 'remove_equipment' && $method === 'POST') {
        require_admin($user);
        $code = require_value($body['equipment_code'] ?? null, 'equipment code');
        $lock = $db->prepare('SELECT id FROM equipment WHERE equipment_code = ? AND is_active = 1');
        $lock->execute([$code]);
        $equipmentId = $lock->fetchColumn();
        if (!$equipmentId) {
            throw new ApiError('Equipment was not found.', 404);
        }
        $active = $db->prepare('SELECT COUNT(*) FROM borrowing_transactions WHERE equipment_id = ? AND status IN ("active", "return_pending")');
        $active->execute([(int)$equipmentId]);
        if ((int)$active->fetchColumn() > 0) {
            throw new ApiError('Equipment cannot be removed while it is borrowed or awaiting return review.', 409);
        }
        $update = $db->prepare('UPDATE equipment SET is_active = 0 WHERE id = ?');
        $update->execute([(int)$equipmentId]);
        log_action($db, $userId, 'inventory.equipment_removed', 'equipment', (int)$equipmentId, $code);
        respond(['message' => 'Equipment removed from active inventory.']);
    }

    if ($action === 'admin_logs' && $method === 'GET') {
        require_admin($user);
        $statement = $db->query(
            'SELECT l.id, l.action, l.entity_type, l.entity_id, l.details, l.created_at,
                    u.account_id, u.full_name AS actor_name
             FROM system_logs l LEFT JOIN users u ON u.id = l.actor_id
             ORDER BY l.created_at DESC LIMIT 150'
        );
        respond(['logs' => $statement->fetchAll()]);
    }

    if ($action === 'report_summary' && $method === 'GET') {
        require_admin($user);
        $summary = $db->query(
            'SELECT
               (SELECT COUNT(*) FROM borrowing_transactions WHERE status = "returned") AS completed_returns,
               (SELECT COUNT(*) FROM borrowing_transactions WHERE status IN ("active", "return_pending")) AS active_borrowings,
               (SELECT COUNT(*) FROM inventory_exceptions WHERE status = "open") AS open_exceptions,
               (SELECT COUNT(*) FROM penalties WHERE status = "unpaid") AS unpaid_penalties,
               (SELECT COALESCE(SUM(amount), 0) FROM payments WHERE status = "verified") AS verified_payments,
               (SELECT COUNT(*) FROM system_logs) AS audit_events'
        )->fetch();
        respond(['summary' => $summary]);
    }

    throw new ApiError('API action not found.', 404);
} catch (ApiError $error) {
    if ($db->inTransaction()) {
        $db->rollBack();
    }
    respond(['error' => $error->getMessage()], $error->httpStatus);
} catch (PDOException $error) {
    if ($db->inTransaction()) {
        $db->rollBack();
    }
    error_log('Stokli API database error: ' . $error->getMessage());
    respond(['error' => 'The request could not be completed. Check the server log or database records.'], 500);
}
