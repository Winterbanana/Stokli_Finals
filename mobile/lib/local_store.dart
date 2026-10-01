import "dart:convert";
import "dart:typed_data";

import "package:crypto/crypto.dart";
import "package:sqflite/sqflite.dart";

import "api_exception.dart";

typedef JsonMap = Map<String, dynamic>;

const _items = [
  {
    "code": "STK-001",
    "name": "Display Port",
    "category": "Cables",
    "stock": 5,
    "image": "display-port.jpg",
  },
  {
    "code": "STK-002",
    "name": "RGB Keyboard",
    "category": "Peripherals",
    "stock": 3,
    "image": "rgb-keyboard.jpg",
  },
  {
    "code": "STK-003",
    "name": "RGB Mouse",
    "category": "Peripherals",
    "stock": 5,
    "image": "rgb-mouse.jpg",
  },
  {
    "code": "STK-004",
    "name": "RGB Speaker Bluetooth",
    "category": "Audio",
    "stock": 2,
    "image": "rgb-speaker-bluetooth.jpg",
  },
  {
    "code": "STK-005",
    "name": "RGB Speaker Desktop",
    "category": "Audio",
    "stock": 4,
    "image": "rgb-speaker-desktop.jpg",
  },
  {
    "code": "STK-006",
    "name": "Screw Driver Set",
    "category": "Tools",
    "stock": 3,
    "image": "screw-driver-set.jpg",
  },
  {
    "code": "STK-007",
    "name": "Thermal Paste",
    "category": "Tools",
    "stock": 5,
    "image": "thermal-paste.jpg",
  },
  {
    "code": "STK-008",
    "name": "VGA Port",
    "category": "Cables",
    "stock": 4,
    "image": "vga-port.jpg",
  },
];

class LocalStore {
  LocalStore({Database? database}) {
    _database = database;
  }

  Database? _database;
  Future<Database>? _opening;

  Future<void> initialize() async {
    if (_database != null) return;
    _opening ??= _open();
    _database = await _opening!;
  }

  Future<Database> _open() async {
    final root = await getDatabasesPath();
    return openDatabase(
      "$root/stokli_local.db",
      version: 4,
      onCreate: (db, version) async {
        await _createSchema(db);
        await _seed(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createSyncTables(db);
        if (oldVersion < 3) {
          await db.execute("ALTER TABLE equipment ADD COLUMN model TEXT");
          await db.execute(
            "ALTER TABLE equipment ADD COLUMN serial_number TEXT",
          );
          await db.execute("ALTER TABLE equipment ADD COLUMN location TEXT");
          await db.execute("ALTER TABLE equipment ADD COLUMN description TEXT");
          await db.execute(
            "ALTER TABLE equipment ADD COLUMN inventory_status TEXT NOT NULL DEFAULT 'active'",
          );
          await _createEquipmentIndexes(db);
        }
        if (oldVersion < 4) await _ensureAccountColumns(db);
      },
    );
  }

  static Future<void> createSchema(DatabaseExecutor db) async {
    await _createSchema(db);
  }

  static Future<void> seed(DatabaseExecutor db) async {
    await _seed(db);
  }

  Future<void> resetDemoData() async {
    final db = await _db;
    await db.transaction((txn) async {
      for (final table in [
        "return_reports",
        "inventory_exceptions",
        "penalties",
        "payments",
        "borrowing_transactions",
        "borrowing_requests",
        "offline_outbox",
        "remote_snapshots",
        "system_logs",
        "equipment",
        "users",
      ]) {
        await txn.delete(table);
      }
      await _seed(txn);
    });
  }

  static Future<void> _createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id TEXT NOT NULL UNIQUE,
        full_name TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL CHECK(role IN ('student','admin')),
        program_section TEXT,
        contact_number TEXT,
        account_status TEXT NOT NULL DEFAULT 'active',
        email TEXT,
        profile_photo TEXT,
        profile_photo_data BLOB,
        profile_version INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE equipment (
        id INTEGER PRIMARY KEY,
        equipment_code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        brand TEXT NOT NULL DEFAULT 'Stokli',
        model TEXT,
        category TEXT NOT NULL,
        serial_number TEXT,
        program TEXT NOT NULL DEFAULT 'IT Laboratory',
        location TEXT,
        description TEXT,
        inventory_status TEXT NOT NULL DEFAULT 'active',
        total_stock INTEGER NOT NULL DEFAULT 0,
        item_condition TEXT NOT NULL DEFAULT 'Good',
        image_asset TEXT,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE borrowing_requests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_code TEXT NOT NULL UNIQUE,
        user_id INTEGER NOT NULL REFERENCES users(id),
        equipment_id INTEGER NOT NULL REFERENCES equipment(id),
        status TEXT NOT NULL DEFAULT 'pending',
        request_note TEXT,
        requested_at TEXT NOT NULL,
        reviewed_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE borrowing_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_code TEXT NOT NULL UNIQUE,
        request_id INTEGER NOT NULL UNIQUE REFERENCES borrowing_requests(id),
        user_id INTEGER NOT NULL REFERENCES users(id),
        equipment_id INTEGER NOT NULL REFERENCES equipment(id),
        borrowed_at TEXT NOT NULL,
        due_at TEXT NOT NULL,
        returned_at TEXT,
        status TEXT NOT NULL DEFAULT 'active'
      )
    ''');
    await db.execute('''
      CREATE TABLE return_reports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_id INTEGER NOT NULL REFERENCES borrowing_transactions(id),
        user_id INTEGER NOT NULL REFERENCES users(id),
        reported_condition TEXT NOT NULL,
        photo_data BLOB,
        status TEXT NOT NULL DEFAULT 'pending',
        reported_at TEXT NOT NULL,
        reviewed_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE inventory_exceptions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        equipment_id INTEGER NOT NULL REFERENCES equipment(id),
        transaction_id INTEGER REFERENCES borrowing_transactions(id),
        reported_by INTEGER NOT NULL REFERENCES users(id),
        exception_type TEXT NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 1,
        notes TEXT,
        status TEXT NOT NULL DEFAULT 'open',
        created_at TEXT NOT NULL,
        resolved_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE penalties (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL REFERENCES users(id),
        transaction_id INTEGER REFERENCES borrowing_transactions(id),
        amount REAL NOT NULL,
        amount_paid REAL NOT NULL DEFAULT 0,
        reason TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'unpaid',
        created_at TEXT NOT NULL,
        settled_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        payment_code TEXT NOT NULL UNIQUE,
        user_id INTEGER NOT NULL REFERENCES users(id),
        amount REAL NOT NULL,
        method TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        reference_note TEXT,
        created_at TEXT NOT NULL,
        reviewed_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE system_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        actor_id INTEGER,
        action TEXT NOT NULL,
        entity_type TEXT,
        entity_id INTEGER,
        details TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await _createSyncTables(db);
    await db.execute(
      "CREATE INDEX idx_local_request_status ON borrowing_requests(user_id,status)",
    );
    await db.execute(
      "CREATE INDEX idx_local_borrowing_user_status ON borrowing_transactions(user_id,status)",
    );
    await db.execute(
      "CREATE INDEX idx_local_payment_user_status ON payments(user_id,status)",
    );
    await _createEquipmentIndexes(db);
  }

  static Future<void> _ensureAccountColumns(DatabaseExecutor db) async {
    final columns = (await db.rawQuery("PRAGMA table_info(users)"))
        .map((row) => row["name"] as String)
        .toSet();
    const definitions = {
      "email": "TEXT",
      "profile_photo": "TEXT",
      "profile_photo_data": "BLOB",
      "profile_version": "INTEGER NOT NULL DEFAULT 1",
      "updated_at": "TEXT",
    };
    for (final entry in definitions.entries) {
      if (!columns.contains(entry.key)) {
        await db.execute(
          "ALTER TABLE users ADD COLUMN ${entry.key} ${entry.value}",
        );
      }
    }
  }

  static Future<void> _createEquipmentIndexes(DatabaseExecutor db) async {
    await db.execute(
      "CREATE INDEX IF NOT EXISTS idx_local_equipment_name ON equipment(name)",
    );
    await db.execute(
      "CREATE INDEX IF NOT EXISTS idx_local_equipment_brand ON equipment(brand)",
    );
    await db.execute(
      "CREATE INDEX IF NOT EXISTS idx_local_equipment_category ON equipment(category)",
    );
    await db.execute(
      "CREATE INDEX IF NOT EXISTS idx_local_transaction_equipment_status ON borrowing_transactions(equipment_id,status)",
    );
    await db.execute(
      "CREATE INDEX IF NOT EXISTS idx_local_exception_equipment_status ON inventory_exceptions(equipment_id,status)",
    );
  }

  static Future<void> _createSyncTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_outbox (
        operation_id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL,
        action TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS remote_snapshots (
        account_id TEXT NOT NULL,
        action TEXT NOT NULL,
        response_json TEXT NOT NULL,
        saved_at TEXT NOT NULL,
        PRIMARY KEY (account_id, action)
      )
    ''');
  }

  static Future<void> _seed(DatabaseExecutor db) async {
    final passwordHash = _hash("demo-student");
    final adminHash = _hash("demo-admin");
    final users = [
      ["STUDENT-001", "Demo Student 1", passwordHash, "student"],
      ["STUDENT-002", "Demo Student 2", passwordHash, "student"],
      ["STUDENT-003", "Demo Student 3", passwordHash, "student"],
      ["STUDENT-004", "Demo Student 4", passwordHash, "student"],
      ["STUDENT-005", "Demo Student 5", passwordHash, "student"],
      ["STUDENT-006", "Demo Student 6", passwordHash, "student"],
      ["ADMIN-001", "Demo Admin 1", adminHash, "admin"],
      ["ADMIN-002", "Demo Admin 2", adminHash, "admin"],
    ];
    for (final user in users) {
      await db.insert("users", {
        "account_id": user[0],
        "full_name": user[1],
        "password_hash": user[2],
        "role": user[3],
        "program_section": user[3] == "student" ? "BSIT 204" : null,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      await db.insert("equipment", {
        "id": i + 1,
        "equipment_code": item["code"],
        "name": item["name"],
        "brand": "Stokli",
        "category": item["category"],
        "program": "IT Laboratory",
        "total_stock": item["stock"],
        "item_condition": "Good",
        "image_asset": item["image"],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    final now = DateTime.now();
    final usersByAccount = await db.query("users");
    final userIds = {
      for (final row in usersByAccount)
        row["account_id"] as String: row["id"] as int,
    };
    await db.insert("borrowing_requests", {
      "id": 1,
      "request_code": "REQ-2026-0051",
      "user_id": userIds["STUDENT-001"],
      "equipment_id": 3,
      "status": "pending",
      "requested_at": now
          .subtract(const Duration(minutes: 30))
          .toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert("borrowing_requests", {
      "id": 2,
      "request_code": "REQ-2026-0052",
      "user_id": userIds["STUDENT-004"],
      "equipment_id": 7,
      "status": "pending",
      "requested_at": now
          .subtract(const Duration(minutes: 20))
          .toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert("borrowing_requests", {
      "id": 3,
      "request_code": "REQ-2026-0053",
      "user_id": userIds["STUDENT-005"],
      "equipment_id": 8,
      "status": "pending",
      "requested_at": now
          .subtract(const Duration(minutes: 10))
          .toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert("borrowing_requests", {
      "id": 4,
      "request_code": "REQ-2026-0048",
      "user_id": userIds["STUDENT-001"],
      "equipment_id": 1,
      "status": "approved",
      "requested_at": now.subtract(const Duration(hours: 2)).toIso8601String(),
      "reviewed_at": now.subtract(const Duration(hours: 1)).toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert("borrowing_transactions", {
      "id": 1,
      "transaction_code": "BOR-2026-000001",
      "request_id": 4,
      "user_id": userIds["STUDENT-001"],
      "equipment_id": 1,
      "borrowed_at": now.subtract(const Duration(hours: 2)).toIso8601String(),
      "due_at": now.add(const Duration(hours: 6)).toIso8601String(),
      "status": "active",
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert("penalties", {
      "id": 1,
      "user_id": userIds["STUDENT-001"],
      "amount": 200,
      "amount_paid": 0,
      "reason": "Outstanding equipment penalty",
      "status": "unpaid",
      "created_at": now.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert("inventory_exceptions", {
      "id": 1,
      "equipment_id": 4,
      "reported_by": userIds["ADMIN-001"],
      "exception_type": "damaged",
      "quantity": 1,
      "notes": "Speaker is under staff review.",
      "status": "open",
      "created_at": now.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert("inventory_exceptions", {
      "id": 2,
      "equipment_id": 8,
      "reported_by": userIds["ADMIN-001"],
      "exception_type": "missing",
      "quantity": 1,
      "notes": "Reported missing during stock check.",
      "status": "open",
      "created_at": now.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert("system_logs", {
      "actor_id": userIds["ADMIN-001"],
      "action": "system.seeded",
      "entity_type": "database",
      "details": "Offline Stokli sample records created.",
      "created_at": now.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static String _hash(String password) =>
      sha256.convert(utf8.encode(password)).toString();

  Future<Database> get _db async {
    await initialize();
    return _database!;
  }

  Future<JsonMap> login(JsonMap body) async {
    final db = await _db;
    final accountId = (body["account_id"] as String? ?? "").trim();
    final password = body["password"] as String? ?? "";
    final role = body["role"] as String? ?? "";
    final rows = await db.query(
      "users",
      where: "lower(account_id) = lower(?)",
      whereArgs: [accountId],
      limit: 1,
    );
    if (rows.isEmpty ||
        rows.first["role"] != role ||
        rows.first["account_status"] != "active" ||
        rows.first["password_hash"] != _hash(password)) {
      throw const ApiException(
        "Invalid account ID, account type, or password.",
        statusCode: 401,
      );
    }
    final user = _publicUser(rows.first);
    return {"token": "offline:${user["id"]}", "user": user};
  }

  Future<JsonMap> me(String token) async {
    final match = RegExp(r"^offline:(\d+)$").firstMatch(token);
    if (match == null) {
      throw const ApiException(
        "Offline session expired. Sign in again.",
        statusCode: 401,
      );
    }
    final rows = await (await _db).query(
      "users",
      where: "id = ?",
      whereArgs: [int.parse(match.group(1)!)],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const ApiException(
        "Offline account was not found.",
        statusCode: 401,
      );
    }
    return {"user": _publicUser(rows.first)};
  }

  Future<int> pendingOperationCount() async =>
      Sqflite.firstIntValue(
        await (await _db).rawQuery("SELECT COUNT(*) FROM offline_outbox"),
      ) ??
      0;

  Future<List<JsonMap>> pendingOperations(String accountId) async =>
      (await _db).query(
        "offline_outbox",
        where: "account_id=?",
        whereArgs: [accountId],
        orderBy: "created_at, rowid",
      );

  Future<void> removePendingOperation(String operationId) async {
    await (await _db).delete(
      "offline_outbox",
      where: "operation_id=?",
      whereArgs: [operationId],
    );
  }

  Future<void> replacePendingOperationPayload(
    String operationId,
    JsonMap payload,
  ) async {
    final updated = await (await _db).update(
      "offline_outbox",
      {"payload": jsonEncode(payload)},
      where: "operation_id=? AND action='update_profile'",
      whereArgs: [operationId],
    );
    if (updated != 1) {
      throw const ApiException(
        "The pending profile edit could not be found.",
        statusCode: 404,
      );
    }
  }

  Future<void> queuePendingOperation({
    required String operationId,
    required String accountId,
    required String action,
    required JsonMap body,
    required String token,
    JsonMap? result,
  }) async {
    final user = await _userForToken(token);
    final db = await _db;
    final payload = Map<String, dynamic>.from(body);
    switch (action) {
      case "create_request":
        payload["request_code"] ??= result?["request_code"];
      case "review_request":
        payload["request_code"] ??= await _codeForId(
          db,
          "borrowing_requests",
          "request_code",
          _int(body["request_id"]),
        );
      case "create_return":
        if (payload["request_code"] == null) {
          final rows = await db.rawQuery(
            '''SELECT r.request_code
                 FROM borrowing_transactions b
                 JOIN borrowing_requests r ON r.id=b.request_id
                 WHERE b.id=? AND b.user_id=? LIMIT 1''',
            [_int(body["transaction_id"]), user["id"]],
          );
          if (rows.isEmpty) {
            throw const ApiException(
              "Borrowing reference is missing for sync.",
            );
          }
          payload["request_code"] = rows.first["request_code"];
        }
      case "review_return":
        if (payload["request_code"] == null) {
          final rows = await db.rawQuery(
            '''SELECT q.request_code
                 FROM return_reports r
                 JOIN borrowing_transactions b ON b.id=r.transaction_id
                 JOIN borrowing_requests q ON q.id=b.request_id
                 WHERE r.id=? LIMIT 1''',
            [_int(body["report_id"])],
          );
          if (rows.isEmpty) {
            throw const ApiException("Return reference is missing for sync.");
          }
          payload["request_code"] = rows.first["request_code"];
        }
      case "create_payment":
        payload["payment_code"] ??= await _codeForId(
          db,
          "payments",
          "payment_code",
          _int(result?["payment_id"]),
        );
      case "review_payment":
        payload["payment_code"] ??= await _codeForId(
          db,
          "payments",
          "payment_code",
          _int(body["payment_id"]),
        );
      case "resolve_exception":
        if (payload["equipment_code"] == null ||
            payload["exception_type"] == null) {
          final rows = await db.rawQuery(
            '''SELECT e.equipment_code, x.exception_type
                 FROM inventory_exceptions x
                 JOIN equipment e ON e.id=x.equipment_id
                 WHERE x.id=? LIMIT 1''',
            [_int(body["exception_id"])],
          );
          if (rows.isEmpty) {
            throw const ApiException(
              "Exception reference is missing for sync.",
            );
          }
          payload["equipment_code"] ??= rows.first["equipment_code"];
          payload["exception_type"] ??= rows.first["exception_type"];
        }
      case "change_password":
      case "register":
        throw const ApiException(
          "Password changes and new account registration require a server connection.",
          statusCode: 503,
        );
    }
    payload.removeWhere((key, value) => value == null);
    await db.insert("offline_outbox", {
      "operation_id": operationId,
      "account_id": accountId,
      "action": action,
      "payload": jsonEncode(payload),
      "created_at": _now(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<String> _codeForId(
    DatabaseExecutor db,
    String table,
    String column,
    int id,
  ) async {
    final rows = await db.query(
      table,
      columns: [column],
      where: "id=?",
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty || rows.first[column] is! String) {
      throw const ApiException("A local record reference is missing for sync.");
    }
    return rows.first[column] as String;
  }

  Future<void> cacheRemoteResponse(
    String action,
    String accountId,
    JsonMap response,
  ) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert("remote_snapshots", {
        "account_id": accountId,
        "action": action,
        "response_json": jsonEncode(response),
        "saved_at": _now(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _cacheSnapshotRows(txn, action, response);
    });
  }

  Future<void> _cacheSnapshotRows(
    Transaction txn,
    String action,
    JsonMap response,
  ) async {
    final rows = switch (action) {
      "equipment" => response["items"],
      "requests" => response["requests"],
      "borrowings" => response["borrowings"],
      "returns" => response["returns"],
      "penalties" => response["penalties"],
      "payments" => response["payments"],
      "exceptions" => response["exceptions"],
      "admin_users" => response["users"],
      _ => null,
    };
    if (rows is! List) return;
    for (final value in rows.whereType<Map<String, dynamic>>()) {
      switch (action) {
        case "equipment":
          await _ensureEquipment(txn, value);
        case "requests":
          await _cacheRequestRow(txn, value);
        case "borrowings":
          await _cacheBorrowingRow(txn, value);
        case "returns":
          await _cacheReturnRow(txn, value);
        case "penalties":
          await _cachePenaltyRow(txn, value);
        case "payments":
          await _cachePaymentRow(txn, value);
        case "exceptions":
          await _cacheExceptionRow(txn, value);
        case "admin_users":
          await _ensureUser(txn, value);
      }
    }
  }

  Future<int?> _ensureUser(DatabaseExecutor txn, JsonMap row) async {
    final accountId = row["account_id"] as String?;
    final fullName =
        row["student_name"] ?? row["full_name"] ?? row["actor_name"];
    if (accountId == null || fullName is! String) return null;
    final existing = await txn.query(
      "users",
      where: "account_id=?",
      whereArgs: [accountId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final old = existing.first;
      await txn.update(
        "users",
        {
          "full_name": fullName,
          "role": row["role"] ?? old["role"],
          "email": row["email"] ?? old["email"],
          "program_section": row["program_section"] ?? old["program_section"],
          "contact_number": row["contact_number"] ?? old["contact_number"],
          "account_status": row["account_status"] ?? old["account_status"],
          "profile_photo": row.containsKey("profile_photo")
              ? row["profile_photo"]
              : old["profile_photo"],
          "profile_photo_data":
              row.containsKey("profile_photo") &&
                  row["profile_photo"] != old["profile_photo"]
              ? null
              : old["profile_photo_data"],
          "profile_version": row["profile_version"] ?? old["profile_version"],
          "updated_at": row["updated_at"] ?? old["updated_at"],
        },
        where: "id=?",
        whereArgs: [old["id"]],
      );
      return old["id"] as int;
    }
    return txn.insert("users", {
      "account_id": accountId,
      "full_name": fullName,
      "password_hash": "",
      "role": row["role"] ?? "student",
      "email": row["email"],
      "program_section": row["program_section"],
      "contact_number": row["contact_number"],
      "account_status": row["account_status"] ?? "active",
      "profile_photo": row["profile_photo"],
      "profile_version": row["profile_version"] ?? 1,
      "updated_at": row["updated_at"],
    });
  }

  Future<int?> _ensureEquipment(Transaction txn, JsonMap row) async {
    final code = row["equipment_code"] as String?;
    final name = row["name"] ?? row["item_name"];
    if (code == null || name is! String) return null;
    final matches = await txn.query(
      "equipment",
      where: "equipment_code=?",
      whereArgs: [code],
      limit: 1,
    );
    final old = matches.isEmpty ? <String, Object?>{} : matches.first;
    final fields = <String, Object?>{
      "equipment_code": code,
      "name": name,
      "brand": row["brand"] ?? old["brand"] ?? "Stokli",
      "model": row["model"] ?? old["model"],
      "category": row["category"] ?? old["category"] ?? "Other",
      "serial_number": row["serial_number"] ?? old["serial_number"],
      "program": row["program"] ?? old["program"] ?? "IT Laboratory",
      "location": row["location"] ?? old["location"],
      "description": row["description"] ?? old["description"],
      "inventory_status":
          row["inventory_status"] ?? old["inventory_status"] ?? "active",
      "total_stock": row.containsKey("total_stock")
          ? _int(row["total_stock"])
          : old["total_stock"] ?? 0,
      "item_condition":
          row["item_condition"] ?? old["item_condition"] ?? "Good",
      "image_asset": row["image_asset"] ?? old["image_asset"],
      "is_active": row["is_active"] ?? old["is_active"] ?? 1,
    };
    if (matches.isEmpty) return txn.insert("equipment", fields);
    final id = matches.first["id"] as int;
    await txn.update("equipment", fields, where: "id=?", whereArgs: [id]);
    return id;
  }

  Future<int?> _ensureRequest(
    Transaction txn,
    JsonMap row,
    int? userId,
    int? equipmentId,
  ) async {
    final code = row["request_code"] as String?;
    if (code == null || userId == null || equipmentId == null) return null;
    final matches = await txn.query(
      "borrowing_requests",
      where: "request_code=?",
      whereArgs: [code],
      limit: 1,
    );
    final fields = <String, Object?>{
      "request_code": code,
      "user_id": userId,
      "equipment_id": equipmentId,
      "status": row["status"] ?? "approved",
      "request_note": row["request_note"],
      "requested_at": row["requested_at"] ?? row["borrowed_at"] ?? _now(),
      "reviewed_at": row["reviewed_at"],
    };
    if (matches.isEmpty) return txn.insert("borrowing_requests", fields);
    final id = matches.first["id"] as int;
    await txn.update(
      "borrowing_requests",
      fields,
      where: "id=?",
      whereArgs: [id],
    );
    return id;
  }

  Future<int?> _cacheRequestRow(Transaction txn, JsonMap row) async {
    final userId = await _ensureUser(txn, row);
    final equipmentId = await _ensureEquipment(txn, row);
    return _ensureRequest(txn, row, userId, equipmentId);
  }

  Future<int?> _cacheBorrowingRow(Transaction txn, JsonMap row) async {
    final userId = await _ensureUser(txn, row);
    final equipmentId = await _ensureEquipment(txn, row);
    final requestId = await _ensureRequest(
      txn,
      {...row, "status": "approved"},
      userId,
      equipmentId,
    );
    final code = row["transaction_code"] as String?;
    if (code == null ||
        userId == null ||
        equipmentId == null ||
        requestId == null) {
      return null;
    }
    var existing = await txn.query(
      "borrowing_transactions",
      where: "transaction_code=?",
      whereArgs: [code],
      limit: 1,
    );
    if (existing.isEmpty) {
      existing = await txn.query(
        "borrowing_transactions",
        where: "request_id=?",
        whereArgs: [requestId],
        limit: 1,
      );
    }
    final old = existing.isEmpty ? <String, Object?>{} : existing.first;
    final transactionStatus =
        row["borrowing_status"] ??
        (row.containsKey("reported_condition") ? null : row["status"]);
    final values = <String, Object?>{
      "transaction_code": code,
      "request_id": requestId,
      "user_id": userId,
      "equipment_id": equipmentId,
      "borrowed_at": row["borrowed_at"] ?? old["borrowed_at"] ?? _now(),
      "due_at": row["due_at"] ?? old["due_at"] ?? _now(),
      "returned_at": row.containsKey("returned_at")
          ? row["returned_at"]
          : old["returned_at"],
      "status": transactionStatus ?? old["status"] ?? "active",
    };
    if (existing.isEmpty) return txn.insert("borrowing_transactions", values);
    final id = existing.first["id"] as int;
    await txn.update(
      "borrowing_transactions",
      values,
      where: "id=?",
      whereArgs: [id],
    );
    return id;
  }

  Future<int?> _cacheReturnRow(Transaction txn, JsonMap row) async {
    final borrowingId = await _cacheBorrowingRow(txn, row);
    final userId = await _ensureUser(txn, row);
    final condition = row["reported_condition"] as String?;
    if (borrowingId == null || userId == null || condition == null) return null;
    final reportedAt = row["reported_at"] ?? _now();
    final existing = await txn.query(
      "return_reports",
      where: "transaction_id=? AND reported_at=? AND reported_condition=?",
      whereArgs: [borrowingId, reportedAt, condition],
      limit: 1,
    );
    final values = <String, Object?>{
      "transaction_id": borrowingId,
      "user_id": userId,
      "reported_condition": condition,
      "status": row["status"] ?? "pending",
      "reported_at": reportedAt,
      "reviewed_at": row["reviewed_at"],
    };
    if (existing.isEmpty) return txn.insert("return_reports", values);
    final id = existing.first["id"] as int;
    await txn.update("return_reports", values, where: "id=?", whereArgs: [id]);
    return id;
  }

  Future<void> _cachePenaltyRow(Transaction txn, JsonMap row) async {
    final userId = await _ensureUser(txn, row);
    if (userId == null) return;
    int? transactionId;
    final transactionCode = row["transaction_code"] as String?;
    if (transactionCode != null) {
      final transactions = await txn.query(
        "borrowing_transactions",
        columns: ["id"],
        where: "transaction_code=?",
        whereArgs: [transactionCode],
        limit: 1,
      );
      if (transactions.isNotEmpty) {
        transactionId = transactions.first["id"] as int;
      }
    }
    final existing = await txn.query(
      "penalties",
      where: "user_id=? AND reason=? AND amount=?",
      whereArgs: [userId, row["reason"], _number(row["amount"])],
      limit: 1,
    );
    final values = <String, Object?>{
      "user_id": userId,
      "transaction_id": transactionId,
      "amount": _number(row["amount"]),
      "amount_paid": _number(row["amount_paid"]),
      "reason": row["reason"] ?? "Penalty",
      "status": row["status"] ?? "unpaid",
      "created_at": row["created_at"] ?? _now(),
      "settled_at": row["settled_at"],
    };
    if (existing.isEmpty) {
      await txn.insert("penalties", values);
    } else {
      await txn.update(
        "penalties",
        values,
        where: "id=?",
        whereArgs: [existing.first["id"]],
      );
    }
  }

  Future<void> _cachePaymentRow(Transaction txn, JsonMap row) async {
    final userId = await _ensureUser(txn, row);
    final code = row["payment_code"] as String?;
    if (userId == null || code == null) return;
    final existing = await txn.query(
      "payments",
      where: "payment_code=?",
      whereArgs: [code],
      limit: 1,
    );
    final values = <String, Object?>{
      "payment_code": code,
      "user_id": userId,
      "amount": _number(row["amount"]),
      "method": row["method"] ?? "Cash",
      "status": row["status"] ?? "pending",
      "reference_note": row["reference_note"],
      "created_at": row["created_at"] ?? _now(),
      "reviewed_at": row["reviewed_at"],
    };
    if (existing.isEmpty) {
      await txn.insert("payments", values);
    } else {
      await txn.update(
        "payments",
        values,
        where: "id=?",
        whereArgs: [existing.first["id"]],
      );
    }
  }

  Future<void> _cacheExceptionRow(Transaction txn, JsonMap row) async {
    final equipmentId = await _ensureEquipment(txn, row);
    final reporterId = await _ensureUser(txn, {
      ...row,
      "student_name": row["reported_by_name"],
    });
    if (equipmentId == null || reporterId == null) return;
    final createdAt = row["created_at"] ?? _now();
    final existing = await txn.query(
      "inventory_exceptions",
      where: "equipment_id=? AND exception_type=? AND created_at=?",
      whereArgs: [equipmentId, row["exception_type"], createdAt],
      limit: 1,
    );
    int? transactionId;
    final transactionCode = row["transaction_code"] as String?;
    if (transactionCode != null) {
      final transactions = await txn.query(
        "borrowing_transactions",
        columns: ["id"],
        where: "transaction_code=?",
        whereArgs: [transactionCode],
        limit: 1,
      );
      if (transactions.isNotEmpty) {
        transactionId = transactions.first["id"] as int;
      }
    }
    final values = <String, Object?>{
      "equipment_id": equipmentId,
      "transaction_id": transactionId,
      "reported_by": reporterId,
      "exception_type": row["exception_type"] ?? "missing",
      "quantity": _int(row["quantity"] ?? 1),
      "notes": row["notes"],
      "status": row["status"] ?? "open",
      "created_at": createdAt,
      "resolved_at": row["resolved_at"],
    };
    if (existing.isEmpty) {
      await txn.insert("inventory_exceptions", values);
    } else {
      await txn.update(
        "inventory_exceptions",
        values,
        where: "id=?",
        whereArgs: [existing.first["id"]],
      );
    }
  }

  Future<JsonMap> overlayRemoteSnapshot(
    String action,
    String accountId,
    JsonMap local,
    JsonMap user,
  ) async {
    final rows = await (await _db).query(
      "remote_snapshots",
      columns: ["response_json"],
      where: "account_id=? AND action=?",
      whereArgs: [accountId, action],
      limit: 1,
    );
    if (rows.isEmpty) return local;
    final decoded = jsonDecode(rows.first["response_json"] as String);
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException("Cached server snapshot is invalid.");
    }
    final listKey = switch (action) {
      "equipment" => "items",
      "requests" => "requests",
      "borrowings" => "borrowings",
      "returns" => "returns",
      "penalties" => "penalties",
      "payments" => "payments",
      "exceptions" => "exceptions",
      "admin_users" => "users",
      "admin_logs" => "logs",
      _ => null,
    };
    if (listKey == null) return decoded;
    final keyName = switch (action) {
      "equipment" => "equipment_code",
      "requests" => "request_code",
      "borrowings" => "transaction_code",
      "payments" => "payment_code",
      "admin_users" => "account_id",
      "admin_logs" => "id",
      _ => null,
    };
    final remoteRows = decoded[listKey];
    final localRows = local[listKey];
    if (remoteRows is! List || localRows is! List) {
      return {...decoded, ...local};
    }
    final pending = await (await _db).query(
      "offline_outbox",
      columns: ["action", "payload"],
      where: "account_id=?",
      whereArgs: [accountId],
    );
    final pendingKeys = <String>{};
    for (final operation in pending) {
      final payload = jsonDecode(operation["payload"] as String);
      if (payload is! Map<String, dynamic>) continue;
      final operationAction = operation["action"];
      final key = switch (operationAction) {
        "create_request" || "review_request" => payload["request_code"],
        "create_return" || "review_return" => payload["request_code"],
        "create_payment" || "review_payment" => payload["payment_code"],
        "mark_missing" ||
        "resolve_exception" ||
        "adjust_stock" ||
        "remove_equipment" => payload["equipment_code"],
        _ => null,
      };
      if (key is String) pendingKeys.add(key);
      if (operationAction == "create_payment" ||
          operationAction == "review_payment") {
        pendingKeys.add("__penalties__");
      }
      if (key is String &&
          (operationAction == "review_request" ||
              operationAction == "create_return" ||
              operationAction == "review_return")) {
        final related = await (await _db).rawQuery(
          '''SELECT b.transaction_code, e.equipment_code
               FROM borrowing_requests r
               JOIN equipment e ON e.id=r.equipment_id
               LEFT JOIN borrowing_transactions b ON b.request_id=r.id
               WHERE r.request_code=?''',
          [key],
        );
        for (final row in related) {
          if (row["transaction_code"] is String) {
            pendingKeys.add(row["transaction_code"] as String);
          }
          if (row["equipment_code"] is String) {
            pendingKeys.add(row["equipment_code"] as String);
          }
        }
      }
    }
    final merged = <String, JsonMap>{};
    for (final value in remoteRows.whereType<Map<String, dynamic>>()) {
      if (action == "exceptions" &&
          user["role"] != "admin" &&
          value["account_id"] != user["account_id"]) {
        continue;
      }
      if (action == "returns" &&
          user["role"] != "admin" &&
          value["account_id"] != user["account_id"]) {
        continue;
      }
      final key = _snapshotKey(action, value, keyName);
      if (key != null) merged[key] = value;
    }
    for (final value in localRows.whereType<Map<String, dynamic>>()) {
      if (action == "exceptions" &&
          user["role"] != "admin" &&
          value["account_id"] != user["account_id"]) {
        continue;
      }
      if (action == "returns" &&
          user["role"] != "admin" &&
          value["account_id"] != user["account_id"]) {
        continue;
      }
      final key = _snapshotKey(action, value, keyName);
      final syncKey = switch (action) {
        "equipment" => value["equipment_code"],
        "requests" => value["request_code"],
        "borrowings" => value["request_code"],
        "payments" => value["payment_code"],
        "exceptions" => value["equipment_code"],
        "returns" => value["transaction_code"],
        "penalties" => "__penalties__",
        _ => key,
      };
      if (key != null && pendingKeys.contains(syncKey)) {
        merged[key] = value;
      }
    }
    return {...decoded, ...local, listKey: merged.values.toList()};
  }

  String? _snapshotKey(String action, JsonMap row, String? keyName) {
    final key = keyName == null
        ? switch (action) {
            "returns" =>
              "${row["transaction_code"]}:${row["reported_at"]}:${row["reported_condition"]}",
            "penalties" =>
              row["transaction_code"]?.toString() ??
                  "${row["account_id"]}:${row["reason"]}:${row["amount"]}",
            "exceptions" =>
              "${row["equipment_code"]}:${row["exception_type"]}:${row["created_at"]}",
            _ => null,
          }
        : row[keyName]?.toString();
    return key == null || key.isEmpty ? null : key;
  }

  Future<JsonMap> get(String action, String token) async {
    if (action == "health") {
      return {"ok": true, "service": "stokli-local", "database": "offline"};
    }
    final user = await _userForToken(token);
    final db = await _db;
    switch (action) {
      case "me":
        return {"user": _publicUser(user)};
      case "equipment":
        return {"items": await _equipment()};
      case "requests":
        return {"requests": await _requests(user)};
      case "borrowings":
        return {"borrowings": await _borrowings(user)};
      case "returns":
        return {"returns": await _returns(user)};
      case "penalties":
        final rows = await _penalties(user);
        return {
          "penalties": rows,
          "outstanding_balance": rows
              .where((row) => row["status"] == "unpaid")
              .fold<double>(
                0,
                (sum, row) =>
                    sum + _number(row["amount"]) - _number(row["amount_paid"]),
              ),
        };
      case "payments":
        return {"payments": await _payments(user)};
      case "admin_stats":
        _requireAdmin(user);
        final equipment = await db.rawQuery('''
          SELECT COUNT(*) AS equipment_count,
                 COALESCE(SUM(e.total_stock),0) AS total_stock,
                 COALESCE(SUM(CASE
                   WHEN e.is_active=0 OR LOWER(e.inventory_status) IN
                     ('retired','maintenance','under maintenance','under_maintenance','lost','damaged')
                     OR LOWER(e.item_condition)='damaged' OR COALESCE(x.damaged_quantity,0)>0 THEN 0
                   ELSE MAX(0,e.total_stock-COALESCE(b.borrowed_quantity,0)
                     -COALESCE(x.reserved_quantity,0)) END),0) AS available_quantity,
                 COALESCE(SUM(COALESCE(b.borrowed_quantity,0)),0) AS borrowed_quantity,
                 SUM(CASE WHEN e.is_active=0 OR LOWER(e.inventory_status)='retired' THEN 1 ELSE 0 END) AS retired_count
          FROM equipment e
          LEFT JOIN (
            SELECT equipment_id, COUNT(*) AS borrowed_quantity
            FROM borrowing_transactions
            WHERE status IN ('active','return_pending')
            GROUP BY equipment_id
          ) b ON b.equipment_id=e.id
          LEFT JOIN (
            SELECT equipment_id, SUM(quantity) AS reserved_quantity,
                   SUM(CASE WHEN exception_type='damaged' THEN quantity ELSE 0 END) AS damaged_quantity
            FROM inventory_exceptions WHERE status='open'
            GROUP BY equipment_id
          ) x ON x.equipment_id=e.id
        ''');
        final stats = <String, Object?>{
          ...equipment.first,
          "pending_requests": await _count(
            "borrowing_requests",
            where: "status='pending'",
          ),
          "active_borrowings": await _count(
            "borrowing_transactions",
            where: "status IN ('active','return_pending')",
          ),
          "pending_returns": await _count(
            "return_reports",
            where: "status='pending'",
          ),
          "pending_payments": await _count(
            "payments",
            where: "status='pending'",
          ),
          "open_exceptions": await _count(
            "inventory_exceptions",
            where: "status='open'",
          ),
          "student_count": await _count(
            "users",
            where: "role='student' AND account_status='active'",
          ),
        };
        return {"stats": stats};
      case "admin_users":
        _requireAdmin(user);
        return {
          "users": await db.query(
            "users",
            columns: [
              "id",
              "account_id",
              "full_name",
              "role",
              "email",
              "program_section",
              "contact_number",
              "account_status",
              "profile_photo",
              "profile_photo_data",
              "profile_version",
              "updated_at",
            ],
            orderBy: "role, full_name",
          ),
        };
      case "exceptions":
        _requireAdmin(user);
        return {"exceptions": await _exceptions()};
      case "admin_logs":
        _requireAdmin(user);
        final logs = await db.rawQuery('''
          SELECT l.*, u.account_id, u.full_name AS actor_name
          FROM system_logs l LEFT JOIN users u ON u.id=l.actor_id
          ORDER BY l.id DESC LIMIT 150
        ''');
        return {"logs": logs};
      case "report_summary":
        _requireAdmin(user);
        return {
          "summary": {
            "completed_returns": await _count(
              "borrowing_transactions",
              where: "status='returned'",
            ),
            "active_borrowings": await _count(
              "borrowing_transactions",
              where: "status IN ('active','return_pending')",
            ),
            "open_exceptions": await _count(
              "inventory_exceptions",
              where: "status='open'",
            ),
            "unpaid_penalties": await _count(
              "penalties",
              where: "status='unpaid'",
            ),
            "verified_payments": await _sum(
              "payments",
              "amount",
              where: "status='verified'",
            ),
            "audit_events": await _count("system_logs"),
          },
        };
      default:
        throw const ApiException(
          "Offline data view is not available.",
          statusCode: 404,
        );
    }
  }

  Future<JsonMap> getStudentAccount(String accountId, String token) async {
    final actor = await _userForToken(token);
    _requireAdmin(actor);
    final db = await _db;
    final profiles = await db.query(
      "users",
      where: "account_id=? AND role='student'",
      whereArgs: [accountId],
      limit: 1,
    );
    if (profiles.isEmpty) {
      throw const ApiException(
        "Student account was not found.",
        statusCode: 404,
      );
    }
    final student = profiles.first;
    final id = student["id"];
    return {
      "profile": _publicUser(student),
      "requests": await db.rawQuery(
        '''SELECT r.request_code, r.status, r.requested_at, r.reviewed_at,
                  e.equipment_code, e.name AS item_name
           FROM borrowing_requests r JOIN equipment e ON e.id=r.equipment_id
           WHERE r.user_id=? ORDER BY r.id DESC LIMIT 100''',
        [id],
      ),
      "borrowings": await db.rawQuery(
        '''SELECT b.transaction_code, b.status, b.borrowed_at, b.due_at, b.returned_at,
                  e.equipment_code, e.name AS item_name
           FROM borrowing_transactions b JOIN equipment e ON e.id=b.equipment_id
           WHERE b.user_id=? ORDER BY b.id DESC LIMIT 100''',
        [id],
      ),
      "returns": await db.rawQuery(
        '''SELECT rr.id, rr.status, rr.reported_condition, rr.reported_at, rr.reviewed_at,
                  e.equipment_code, e.name AS item_name, b.transaction_code
           FROM return_reports rr
           JOIN borrowing_transactions b ON b.id=rr.transaction_id
           JOIN equipment e ON e.id=b.equipment_id
           WHERE rr.user_id=? ORDER BY rr.id DESC LIMIT 100''',
        [id],
      ),
      "penalties": await db.query(
        "penalties",
        columns: [
          "id",
          "amount",
          "amount_paid",
          "reason",
          "status",
          "created_at",
          "settled_at",
        ],
        where: "user_id=?",
        whereArgs: [id],
        orderBy: "id DESC",
        limit: 100,
      ),
      "payments": await db.query(
        "payments",
        columns: [
          "payment_code",
          "amount",
          "method",
          "status",
          "reference_note",
          "created_at",
          "reviewed_at",
        ],
        where: "user_id=?",
        whereArgs: [id],
        orderBy: "id DESC",
        limit: 100,
      ),
      "activities": await db.rawQuery(
        '''SELECT l.id, l.actor_id, l.action, l.entity_type, l.entity_id, l.details, l.created_at
           FROM system_logs l
           WHERE (l.entity_type='user' AND l.entity_id=?) OR l.actor_id=?
           ORDER BY l.id DESC LIMIT 100''',
        [id, id],
      ),
    };
  }

  Future<JsonMap> getEquipmentPage(
    String token, {
    int limit = 30,
    int offset = 0,
    String search = "",
    String category = "",
    String status = "",
  }) async {
    await _userForToken(token);
    return _readEquipmentPage(
      limit: limit,
      offset: offset,
      search: search,
      category: category,
      status: status,
    );
  }

  Future<JsonMap> getCachedEquipmentPage({
    int limit = 30,
    int offset = 0,
    String search = "",
    String category = "",
    String status = "",
  }) => _readEquipmentPage(
    limit: limit,
    offset: offset,
    search: search,
    category: category,
    status: status,
  );

  Future<JsonMap> _readEquipmentPage({
    required int limit,
    required int offset,
    required String search,
    required String category,
    required String status,
  }) async {
    final size = limit.clamp(1, 100).toInt();
    final start = offset < 0 ? 0 : offset;
    final db = await _db;
    final where = <String>[];
    final args = <Object?>[];
    final normalizedSearch = search.trim();
    if (normalizedSearch.isNotEmpty) {
      where.add(
        "(equipment_code LIKE ? OR CAST(id AS TEXT) LIKE ? OR name LIKE ? OR brand LIKE ? OR model LIKE ? OR category LIKE ? OR serial_number LIKE ? OR status LIKE ?)",
      );
      final pattern = "%$normalizedSearch%";
      args.addAll(List<Object?>.filled(8, pattern));
    }
    if (category.isNotEmpty && category.toLowerCase() != "all") {
      where.add("category=?");
      args.add(category);
    }
    if (status.isNotEmpty && status.toLowerCase() != "all") {
      where.add("LOWER(status)=LOWER(?)");
      args.add(status);
    }
    final filtered = where.isEmpty ? "" : "WHERE ${where.join(" AND ")}";
    final rows = await db.rawQuery(
      '''SELECT id, equipment_code, name, brand, model, category, serial_number,
                total_stock, item_condition, inventory_status, image_asset, is_active,
                borrowed_quantity, overdue_quantity, pending_quantity,
                damaged_quantity, lost_quantity, maintenance_quantity,
                available_stock, status
         FROM (${_equipmentSelect()}) inventory
         $filtered ORDER BY id LIMIT ? OFFSET ?''',
      [...args, size, start],
    );
    final countRows = await db.rawQuery(
      '''SELECT COUNT(*) AS total FROM (${_equipmentSelect()}) inventory
         $filtered''',
      args,
    );
    final categories = await db.rawQuery(
      "SELECT DISTINCT category FROM equipment ORDER BY category",
    );
    final total = _int(countRows.first["total"]);
    return {
      "items": rows,
      "total_count": total,
      "offset": start,
      "limit": size,
      "has_more": start + rows.length < total,
      "categories": categories.map((row) => row["category"]).toList(),
    };
  }

  Future<JsonMap> post(String action, JsonMap body, String token) async {
    if (action == "login") return login(body);
    if (action == "register") return register(body);
    final user = await _userForToken(token);
    final db = await _db;
    switch (action) {
      case "logout":
        return {"message": "Signed out."};
      case "change_password":
        return changePassword(user, body);
      case "update_profile":
        return updateProfile(user, body);
      case "create_request":
        return createRequest(user, body);
      case "review_request":
        return reviewRequest(user, body);
      case "create_return":
        return createReturn(user, body);
      case "return_photo":
        _requireAdmin(user);
        final id = _int(body["report_id"]);
        final rows = await db.query(
          "return_reports",
          columns: ["photo_data"],
          where: "id=?",
          whereArgs: [id],
          limit: 1,
        );
        if (rows.isEmpty || rows.first["photo_data"] == null) {
          throw const ApiException(
            "This return report has no photo.",
            statusCode: 404,
          );
        }
        return {
          "photo_base64": base64Encode(rows.first["photo_data"] as List<int>),
        };
      case "review_return":
        return reviewReturn(user, body);
      case "create_payment":
        return createPayment(user, body);
      case "review_payment":
        return reviewPayment(user, body);
      case "mark_missing":
        return markMissing(user, body);
      case "resolve_exception":
        return resolveException(user, body);
      case "adjust_stock":
        return adjustStock(user, body);
      case "remove_equipment":
        return removeEquipment(user, body);
      default:
        throw const ApiException(
          "Offline action is not available.",
          statusCode: 404,
        );
    }
  }

  Future<JsonMap> register(JsonMap body) async {
    final db = await _db;
    final accountId = (body["account_id"] as String? ?? "").trim();
    final fullName = (body["full_name"] as String? ?? "").trim();
    final password = body["password"] as String? ?? "";
    if (accountId.isEmpty || fullName.isEmpty || !_strongPassword(password)) {
      throw const ApiException(
        "Enter an account ID, full name, and a strong password.",
        statusCode: 422,
      );
    }
    try {
      await db.insert("users", {
        "account_id": accountId,
        "full_name": fullName,
        "password_hash": _hash(password),
        "role": "student",
        "program_section": "",
      });
    } on DatabaseException {
      throw const ApiException(
        "That account ID is already registered.",
        statusCode: 409,
      );
    }
    await _log(null, "auth.register", "user", null, detail: accountId);
    return {"message": "Account created. You can now sign in."};
  }

  Future<void> cacheRegisteredUser({
    required String accountId,
    required String fullName,
    required String password,
  }) async {
    final db = await _db;
    await db.insert("users", {
      "account_id": accountId,
      "full_name": fullName,
      "password_hash": _hash(password),
      "role": "student",
      "program_section": "",
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<JsonMap> changePassword(JsonMap user, JsonMap body) async {
    final current = body["current_password"] as String? ?? "";
    final next = body["new_password"] as String? ?? "";
    if (user["password_hash"] != _hash(current)) {
      throw const ApiException(
        "The current password is incorrect.",
        statusCode: 403,
      );
    }
    if (!_strongPassword(next)) {
      throw const ApiException(
        "Use 8+ characters with uppercase, lowercase, a number, and a symbol.",
        statusCode: 422,
      );
    }
    await (await _db).update(
      "users",
      {"password_hash": _hash(next)},
      where: "id=?",
      whereArgs: [user["id"]],
    );
    await _log(
      user["id"] as int,
      "account.password_changed",
      "user",
      user["id"] as int,
    );
    return {"message": "Password updated."};
  }

  Future<JsonMap> updateProfile(JsonMap actor, JsonMap body) async {
    final targetAccountId =
        body["target_account_id"] as String? ?? actor["account_id"] as String;
    final isSelf = targetAccountId == actor["account_id"];
    if (!isSelf && actor["role"] != "admin") {
      throw const ApiException(
        "You are not authorized to edit this account.",
        statusCode: 403,
      );
    }
    final db = await _db;
    final rows = await db.query(
      "users",
      where: "account_id=?",
      whereArgs: [targetAccountId],
      limit: 1,
    );
    if (rows.isEmpty || (!isSelf && rows.first["role"] != "student")) {
      throw const ApiException(
        "Student account was not found.",
        statusCode: 404,
      );
    }
    final target = rows.first;
    final targetId = target["id"] as int;
    final expectedVersion = _int(body["expected_version"]);
    if (expectedVersion < 1 ||
        expectedVersion != _int(target["profile_version"])) {
      throw const ApiException(
        "This profile was changed elsewhere. Refresh it and review the latest values before saving again.",
        statusCode: 409,
      );
    }

    final changes = <String, Object?>{};
    const limits = {
      "full_name": 120,
      "email": 254,
      "contact_number": 32,
      "program_section": 80,
    };
    for (final entry in limits.entries) {
      if (!body.containsKey(entry.key)) continue;
      final value = (body[entry.key] as String? ?? "").trim();
      if (value.length > entry.value ||
          (entry.key == "full_name" && value.isEmpty) ||
          (entry.key == "email" &&
              value.isNotEmpty &&
              !RegExp(r"^[^@\s]+@[^@\s]+\.[^@\s]+$").hasMatch(value))) {
        throw const ApiException(
          "Check the profile information and try again.",
          statusCode: 422,
        );
      }
      changes[entry.key] = entry.key == "email" && value.isEmpty ? null : value;
    }
    if (changes["email"] is String) {
      final duplicates = await db.query(
        "users",
        columns: ["id"],
        where: "email=? AND id<>?",
        whereArgs: [changes["email"], targetId],
        limit: 1,
      );
      if (duplicates.isNotEmpty) {
        throw const ApiException(
          "That email address is already used by another account.",
          statusCode: 409,
        );
      }
    }
    if (body.containsKey("account_status")) {
      final status = body["account_status"];
      if (isSelf || actor["role"] != "admin" || target["role"] != "student") {
        throw const ApiException(
          "Only an administrator can change a Student account status.",
          statusCode: 403,
        );
      }
      if (status != "active" && status != "suspended") {
        throw const ApiException(
          "Choose a valid account status.",
          statusCode: 422,
        );
      }
      changes["account_status"] = status;
    }

    final encodedPhoto = body["profile_photo_base64"];
    Uint8List? photoBytes;
    if (encodedPhoto != null) {
      if (encodedPhoto is! String || encodedPhoto.isEmpty) {
        throw const ApiException(
          "Choose a valid profile photo.",
          statusCode: 422,
        );
      }
      try {
        photoBytes = Uint8List.fromList(base64Decode(encodedPhoto));
      } on FormatException {
        throw const ApiException(
          "The selected profile photo is invalid.",
          statusCode: 422,
        );
      }
      if (photoBytes.length > 1_572_864 ||
          !_isSupportedProfileImage(photoBytes)) {
        throw const ApiException(
          "Choose a JPG, PNG, or WEBP photo under 1.5 MB.",
          statusCode: 422,
        );
      }
      changes["profile_photo"] =
          "offline:${DateTime.now().microsecondsSinceEpoch}";
      changes["profile_photo_data"] = photoBytes;
    } else if (body["remove_profile_photo"] == true) {
      changes["profile_photo"] = null;
      changes["profile_photo_data"] = null;
    }
    if (changes.isEmpty) {
      throw const ApiException(
        "There are no profile changes to save.",
        statusCode: 422,
      );
    }
    final version = expectedVersion + 1;
    changes["profile_version"] = version;
    changes["updated_at"] = _now();
    await db.transaction((txn) async {
      await txn.update("users", changes, where: "id=?", whereArgs: [targetId]);
      final changed = changes.keys
          .where(
            (field) => !const {
              "profile_photo",
              "profile_photo_data",
              "profile_version",
              "updated_at",
            }.contains(field),
          )
          .join(", ");
      await _log(
        actor["id"] as int,
        isSelf ? "account.profile_updated" : "account.student_updated",
        "user",
        targetId,
        detail: "Changed fields: $changed",
        txn: txn,
      );
      if (encodedPhoto != null) {
        await _log(
          actor["id"] as int,
          isSelf ? "account.photo_uploaded" : "account.student_photo_updated",
          "user",
          targetId,
          txn: txn,
        );
      }
      if (body["remove_profile_photo"] == true) {
        await _log(
          actor["id"] as int,
          isSelf ? "account.photo_removed" : "account.student_photo_removed",
          "user",
          targetId,
          txn: txn,
        );
      }
      if (body.containsKey("account_status") &&
          body["account_status"] != target["account_status"]) {
        await _log(
          actor["id"] as int,
          body["account_status"] == "active"
              ? "account.student_activated"
              : "account.student_suspended",
          "user",
          targetId,
          txn: txn,
        );
      }
    });
    final updated = {...target, ...changes};
    return {"message": "Profile updated.", "user": _publicUser(updated)};
  }

  static bool _isSupportedProfileImage(Uint8List bytes) =>
      (bytes.length >= 3 &&
          bytes[0] == 0xff &&
          bytes[1] == 0xd8 &&
          bytes[2] == 0xff) ||
      (bytes.length >= 8 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4e &&
          bytes[3] == 0x47 &&
          bytes[4] == 0x0d &&
          bytes[5] == 0x0a &&
          bytes[6] == 0x1a &&
          bytes[7] == 0x0a) ||
      (bytes.length >= 12 &&
          String.fromCharCodes(bytes.sublist(0, 4)) == "RIFF" &&
          String.fromCharCodes(bytes.sublist(8, 12)) == "WEBP");

  Future<JsonMap> createRequest(JsonMap user, JsonMap body) async {
    if (user["role"] != "student") {
      throw const ApiException(
        "Only student accounts can request equipment.",
        statusCode: 403,
      );
    }
    final db = await _db;
    final code = body["equipment_code"] as String? ?? "";
    return db.transaction((txn) async {
      final equipmentRows = await txn.query(
        "equipment",
        where: "equipment_code=? AND is_active=1 AND LOWER(inventory_status)='active' AND LOWER(item_condition)<>'damaged'",
        whereArgs: [code],
        limit: 1,
      );
      if (equipmentRows.isEmpty) {
        throw const ApiException("Equipment was not found.", statusCode: 404);
      }
      final equipment = equipmentRows.first;
      final equipmentId = equipment["id"] as int;
      if (await _availableStock(equipmentId, txn) < 1) {
        throw const ApiException(
          "This item is currently unavailable.",
          statusCode: 409,
        );
      }
      final existing = await txn.rawQuery(
        '''SELECT r.id FROM borrowing_requests r
           WHERE r.user_id=? AND r.equipment_id=?
             AND (r.status='pending' OR EXISTS (
               SELECT 1 FROM borrowing_transactions b
               WHERE b.request_id=r.id AND b.status IN ('active','return_pending')
             )) LIMIT 1''',
        [user["id"], equipmentId],
      );
      if (existing.isNotEmpty) {
        throw const ApiException(
          "You already have an open request for this item.",
          statusCode: 409,
        );
      }
      final requestId = await txn.insert("borrowing_requests", {
        "request_code":
            body["request_code"] ??
            "TEMP-${DateTime.now().microsecondsSinceEpoch}",
        "user_id": user["id"],
        "equipment_id": equipmentId,
        "status": "pending",
        "request_note": body["note"],
        "requested_at": _now(),
      });
      final requestCode =
          body["request_code"] as String? ?? _yearCode("REQ", requestId);
      await txn.update(
        "borrowing_requests",
        {"request_code": requestCode},
        where: "id=?",
        whereArgs: [requestId],
      );
      await _log(
        user["id"] as int,
        "request.created",
        "borrowing_request",
        requestId,
        detail: equipment["name"] as String,
        txn: txn,
      );
      return {
        "message": "Borrowing request submitted.",
        "request_id": requestId,
        "request_code": requestCode,
      };
    });
  }

  Future<JsonMap> reviewRequest(JsonMap user, JsonMap body) async {
    _requireAdmin(user);
    final requestId = _int(body["request_id"]);
    final decision = body["decision"] as String? ?? "";
    if (decision != "approved" && decision != "rejected") {
      throw const ApiException("Choose approve or decline.", statusCode: 422);
    }
    final db = await _db;
    return db.transaction((txn) async {
      final requests = await txn.query(
        "borrowing_requests",
        where: "id=?",
        whereArgs: [requestId],
        limit: 1,
      );
      final matchedRequests = body["request_code"] is String
          ? await txn.query(
              "borrowing_requests",
              where: "request_code=?",
              whereArgs: [body["request_code"]],
              limit: 1,
            )
          : requests;
      if (matchedRequests.isEmpty ||
          matchedRequests.first["status"] != "pending") {
        throw const ApiException(
          "This request is no longer awaiting review.",
          statusCode: 409,
        );
      }
      final request = matchedRequests.first;
      final resolvedRequestId = request["id"] as int;
      if (decision == "approved") {
        final equipmentId = request["equipment_id"] as int;
        if (await _availableStock(equipmentId, txn) < 1) {
          throw const ApiException(
            "No available stock remains for this request.",
            statusCode: 409,
          );
        }
        final borrowedAt = DateTime.now();
        final transactionId = await txn.insert("borrowing_transactions", {
          "transaction_code": "TEMP-${DateTime.now().microsecondsSinceEpoch}",
          "request_id": resolvedRequestId,
          "user_id": request["user_id"],
          "equipment_id": equipmentId,
          "borrowed_at": borrowedAt.toIso8601String(),
          "due_at": borrowedAt.add(const Duration(hours: 8)).toIso8601String(),
          "status": "active",
        });
        await txn.update(
          "borrowing_transactions",
          {"transaction_code": _yearCode("BOR", transactionId)},
          where: "id=?",
          whereArgs: [transactionId],
        );
      }
      await txn.update(
        "borrowing_requests",
        {
          "status": decision == "rejected" ? "rejected" : "approved",
          "reviewed_at": _now(),
        },
        where: "id=?",
        whereArgs: [resolvedRequestId],
      );
      await _log(
        user["id"] as int,
        "request.$decision",
        "borrowing_request",
        resolvedRequestId,
        txn: txn,
      );
      return {
        "message": decision == "rejected"
            ? "Request declined."
            : "Request approved. Borrowing slip is ready.",
      };
    });
  }

  Future<JsonMap> createReturn(JsonMap user, JsonMap body) async {
    if (user["role"] != "student") {
      throw const ApiException(
        "Only student accounts can submit returns.",
        statusCode: 403,
      );
    }
    var transactionId = _int(body["transaction_id"]);
    final condition = body["condition"] as String? ?? "";
    if (!const ["Good", "Damaged", "Missing"].contains(condition)) {
      throw const ApiException(
        "Choose a valid item condition.",
        statusCode: 422,
      );
    }
    final photoText = body["photo_base64"] as String?;
    final photo = photoText == null || photoText.isEmpty
        ? null
        : base64Decode(photoText);
    if (photo != null && photo.length > 2 * 1024 * 1024) {
      throw const ApiException(
        "Return photos must be smaller than 2 MB.",
        statusCode: 413,
      );
    }
    final db = await _db;
    return db.transaction((txn) async {
      var borrowings = <JsonMap>[];
      if (body["request_code"] is String) {
        borrowings = await txn.rawQuery(
          '''SELECT b.* FROM borrowing_transactions b
             JOIN borrowing_requests q ON q.id=b.request_id
             WHERE q.request_code=? AND b.user_id=? AND b.status='active'
             LIMIT 1''',
          [body["request_code"], user["id"]],
        );
      } else {
        borrowings = await txn.query(
          "borrowing_transactions",
          where: "id=? AND user_id=? AND status='active'",
          whereArgs: [transactionId, user["id"]],
          limit: 1,
        );
      }
      if (borrowings.isNotEmpty) {
        transactionId = borrowings.first["id"] as int;
      }
      if (borrowings.isEmpty) {
        throw const ApiException(
          "This borrowing is not available for return.",
          statusCode: 409,
        );
      }
      final reportId = await txn.insert("return_reports", {
        "transaction_id": transactionId,
        "user_id": user["id"],
        "reported_condition": condition,
        "photo_data": photo,
        "status": "pending",
        "reported_at": _now(),
      });
      await txn.update(
        "borrowing_transactions",
        {"status": "return_pending"},
        where: "id=?",
        whereArgs: [transactionId],
      );
      await _log(
        user["id"] as int,
        "return.submitted",
        "return_report",
        reportId,
        detail: condition,
        txn: txn,
      );
      return {
        "message": "Return report sent for staff review.",
        "report_id": reportId,
      };
    });
  }

  Future<JsonMap> reviewReturn(JsonMap user, JsonMap body) async {
    _requireAdmin(user);
    final id = _int(body["report_id"]);
    final decision = body["decision"] as String? ?? "";
    if (!const ["accept", "reject"].contains(decision)) {
      throw const ApiException(
        "Choose verify or ask the student to resubmit.",
        statusCode: 422,
      );
    }
    final db = await _db;
    return db.transaction((txn) async {
      var reports = <JsonMap>[];
      if (body["request_code"] is String) {
        reports = await txn.rawQuery(
          '''SELECT r.*, b.equipment_id, b.user_id AS borrower_id
             FROM return_reports r
             JOIN borrowing_transactions b ON b.id=r.transaction_id
             JOIN borrowing_requests q ON q.id=b.request_id
             WHERE q.request_code=? AND r.status='pending'
             ORDER BY r.id DESC LIMIT 1''',
          [body["request_code"]],
        );
      } else {
        reports = await txn.rawQuery(
          '''SELECT r.*, b.equipment_id, b.user_id AS borrower_id
             FROM return_reports r JOIN borrowing_transactions b ON b.id=r.transaction_id
             WHERE r.id=?''',
          [id],
        );
      }
      if (reports.isEmpty || reports.first["status"] != "pending") {
        throw const ApiException(
          "This return is no longer awaiting review.",
          statusCode: 409,
        );
      }
      final report = reports.first;
      final resolvedReportId = report["id"] as int;
      if (decision == "reject") {
        await txn.update(
          "return_reports",
          {"status": "rejected", "reviewed_at": _now()},
          where: "id=?",
          whereArgs: [resolvedReportId],
        );
        await txn.update(
          "borrowing_transactions",
          {"status": "active"},
          where: "id=?",
          whereArgs: [report["transaction_id"]],
        );
      } else {
        await txn.update(
          "return_reports",
          {"status": "accepted", "reviewed_at": _now()},
          where: "id=?",
          whereArgs: [resolvedReportId],
        );
        await txn.update(
          "borrowing_transactions",
          {
            "status": report["reported_condition"] == "Missing"
                ? "missing"
                : "returned",
            "returned_at": _now(),
          },
          where: "id=?",
          whereArgs: [report["transaction_id"]],
        );
        final condition = report["reported_condition"] as String;
        if (condition != "Good") {
          await txn.insert("inventory_exceptions", {
            "equipment_id": report["equipment_id"],
            "transaction_id": report["transaction_id"],
            "reported_by": user["id"],
            "exception_type": condition.toLowerCase(),
            "quantity": 1,
            "notes": "Student return report: $condition",
            "status": "open",
            "created_at": _now(),
          });
        }
        if (condition == "Missing") {
          await txn.insert("penalties", {
            "user_id": report["borrower_id"],
            "transaction_id": report["transaction_id"],
            "amount": 200.0,
            "amount_paid": 0.0,
            "reason": "Missing equipment",
            "status": "unpaid",
            "created_at": _now(),
          });
        }
      }
      await _log(
        user["id"] as int,
        "return.$decision",
        "return_report",
        resolvedReportId,
        detail: report["reported_condition"] as String,
        txn: txn,
      );
      return {
        "message": decision == "accept"
            ? "Return verified."
            : "Return declined. The student can resubmit.",
      };
    });
  }

  Future<JsonMap> createPayment(JsonMap user, JsonMap body) async {
    if (user["role"] != "student") {
      throw const ApiException(
        "Only student accounts can submit payments.",
        statusCode: 403,
      );
    }
    final amount = _number(body["amount"]);
    final method = body["method"] as String? ?? "";
    if (amount <= 0 || !const ["GCash", "Maya", "Cash"].contains(method)) {
      throw const ApiException(
        "Enter a valid amount and payment method.",
        statusCode: 422,
      );
    }
    final db = await _db;
    return db.transaction((txn) async {
      final penalties = await txn.query(
        "penalties",
        where: "user_id=? AND status='unpaid'",
        whereArgs: [user["id"]],
      );
      final balance = penalties.fold<double>(
        0,
        (sum, row) =>
            sum + _number(row["amount"]) - _number(row["amount_paid"]),
      );
      final pending = await _sum(
        "payments",
        "amount",
        where: "user_id=${user["id"]} AND status='pending'",
        txn: txn,
      );
      if (amount > balance - pending + 0.001) {
        throw const ApiException(
          "Payment amount exceeds your outstanding balance.",
          statusCode: 409,
        );
      }
      final id = await txn.insert("payments", {
        "payment_code":
            body["payment_code"] ??
            "TEMP-${DateTime.now().microsecondsSinceEpoch}",
        "user_id": user["id"],
        "amount": amount,
        "method": method,
        "status": "pending",
        "reference_note": body["reference_note"],
        "created_at": _now(),
      });
      await txn.update(
        "payments",
        {
          "payment_code":
              body["payment_code"] as String? ?? _yearCode("PAY", id),
        },
        where: "id=?",
        whereArgs: [id],
      );
      await _log(
        user["id"] as int,
        "payment.submitted",
        "payment",
        id,
        detail: method,
        txn: txn,
      );
      return {
        "message": "Payment record sent for staff verification.",
        "payment_id": id,
      };
    });
  }

  Future<JsonMap> reviewPayment(JsonMap user, JsonMap body) async {
    _requireAdmin(user);
    final id = _int(body["payment_id"]);
    final decision = body["decision"] as String? ?? "";
    if (!const ["verify", "reject"].contains(decision)) {
      throw const ApiException("Choose verify or reject.", statusCode: 422);
    }
    final db = await _db;
    return db.transaction((txn) async {
      var rows = <JsonMap>[];
      if (body["payment_code"] is String) {
        rows = await txn.query(
          "payments",
          where: "payment_code=?",
          whereArgs: [body["payment_code"]],
          limit: 1,
        );
      } else {
        rows = await txn.query(
          "payments",
          where: "id=?",
          whereArgs: [id],
          limit: 1,
        );
      }
      if (rows.isEmpty || rows.first["status"] != "pending") {
        throw const ApiException(
          "This payment is no longer awaiting review.",
          statusCode: 409,
        );
      }
      final payment = rows.first;
      final resolvedPaymentId = payment["id"] as int;
      final status = decision == "verify" ? "verified" : "rejected";
      await txn.update(
        "payments",
        {"status": status, "reviewed_at": _now()},
        where: "id=?",
        whereArgs: [resolvedPaymentId],
      );
      if (decision == "verify") {
        var remaining = _number(payment["amount"]);
        final penalties = await txn.query(
          "penalties",
          where: "user_id=? AND status='unpaid'",
          whereArgs: [payment["user_id"]],
          orderBy: "id",
        );
        for (final penalty in penalties) {
          if (remaining <= 0) break;
          final due =
              _number(penalty["amount"]) - _number(penalty["amount_paid"]);
          final paid = remaining < due ? remaining : due;
          final totalPaid = _number(penalty["amount_paid"]) + paid;
          final settled = totalPaid + 0.001 >= _number(penalty["amount"]);
          await txn.update(
            "penalties",
            {
              "amount_paid": totalPaid,
              "status": settled ? "paid" : "unpaid",
              if (settled) "settled_at": _now(),
            },
            where: "id=?",
            whereArgs: [penalty["id"]],
          );
          remaining -= paid;
        }
        if (remaining > 0.01) {
          throw const ApiException(
            "The balance changed; this payment cannot be verified.",
            statusCode: 409,
          );
        }
      }
      await _log(
        user["id"] as int,
        "payment.$status",
        "payment",
        resolvedPaymentId,
        txn: txn,
      );
      return {"message": "Payment $status."};
    });
  }

  Future<JsonMap> markMissing(JsonMap user, JsonMap body) async {
    _requireAdmin(user);
    final code = body["equipment_code"] as String? ?? "";
    final db = await _db;
    final rows = await db.query(
      "equipment",
      where: "equipment_code=? AND is_active=1",
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isEmpty || await _availableStock(rows.first["id"] as int) < 1) {
      throw const ApiException(
        "No available unit can be marked missing.",
        statusCode: 409,
      );
    }
    final id = await db.insert("inventory_exceptions", {
      "equipment_id": rows.first["id"],
      "reported_by": user["id"],
      "exception_type": "missing",
      "quantity": 1,
      "notes": body["notes"] ?? "Marked missing during stock check.",
      "status": "open",
      "created_at": _now(),
    });
    await _log(
      user["id"] as int,
      "inventory.exception.created",
      "inventory_exception",
      id,
      detail: code,
    );
    return {"message": "Equipment marked missing."};
  }

  Future<JsonMap> resolveException(JsonMap user, JsonMap body) async {
    _requireAdmin(user);
    var id = _int(body["exception_id"]);
    final db = await _db;
    var changed = 0;
    if (body["equipment_code"] is String && body["exception_type"] is String) {
      final rows = await db.rawQuery(
        '''SELECT x.id FROM inventory_exceptions x
           JOIN equipment e ON e.id=x.equipment_id
           WHERE e.equipment_code=? AND x.exception_type=? AND x.status='open'
           ORDER BY x.id DESC LIMIT 1''',
        [body["equipment_code"], body["exception_type"]],
      );
      if (rows.isNotEmpty) {
        id = rows.first["id"] as int;
        changed = await db.update(
          "inventory_exceptions",
          {"status": "resolved", "resolved_at": _now()},
          where: "id=? AND status='open'",
          whereArgs: [id],
        );
      }
    } else {
      changed = await db.update(
        "inventory_exceptions",
        {"status": "resolved", "resolved_at": _now()},
        where: "id=? AND status='open'",
        whereArgs: [id],
      );
    }
    if (changed == 0) {
      throw const ApiException(
        "This exception is already resolved or was not found.",
        statusCode: 404,
      );
    }
    await _log(
      user["id"] as int,
      "inventory.exception.resolved",
      "inventory_exception",
      id,
    );
    return {"message": "Inventory exception resolved."};
  }

  Future<JsonMap> adjustStock(JsonMap user, JsonMap body) async {
    _requireAdmin(user);
    final code = body["equipment_code"] as String? ?? "";
    final delta = _int(body["delta"]);
    if (delta == 0) {
      throw const ApiException(
        "Stock adjustment must be non-zero.",
        statusCode: 422,
      );
    }
    final db = await _db;
    return db.transaction((txn) async {
      final rows = await txn.query(
        "equipment",
        where: "equipment_code=? AND is_active=1",
        whereArgs: [code],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw const ApiException("Equipment was not found.", statusCode: 404);
      }
      final item = rows.first;
      final next = (item["total_stock"] as int) + delta;
      final borrowed = await txn.rawQuery(
        "SELECT COUNT(*) n FROM borrowing_transactions WHERE equipment_id=? AND status IN ('active','return_pending')",
        [item["id"]],
      );
      final reserved = await txn.rawQuery(
        "SELECT COALESCE(SUM(quantity),0) n FROM inventory_exceptions WHERE equipment_id=? AND status='open'",
        [item["id"]],
      );
      if (next < _int(borrowed.first["n"]) + _int(reserved.first["n"])) {
        throw const ApiException(
          "Stock cannot be lower than borrowed or missing units.",
          statusCode: 409,
        );
      }
      await txn.update(
        "equipment",
        {"total_stock": next},
        where: "id=?",
        whereArgs: [item["id"]],
      );
      await _log(
        user["id"] as int,
        "inventory.stock_adjusted",
        "equipment",
        item["id"] as int,
        detail: "Delta: $delta",
        txn: txn,
      );
      return {"message": "Stock updated.", "total_stock": next};
    });
  }

  Future<JsonMap> removeEquipment(JsonMap user, JsonMap body) async {
    _requireAdmin(user);
    final code = body["equipment_code"] as String? ?? "";
    final db = await _db;
    final rows = await db.query(
      "equipment",
      where: "equipment_code=? AND is_active=1",
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const ApiException("Equipment was not found.", statusCode: 404);
    }
    final id = rows.first["id"] as int;
    if (await db
        .rawQuery(
          "SELECT id FROM borrowing_transactions WHERE equipment_id=? AND status IN ('active','return_pending') LIMIT 1",
          [id],
        )
        .then((rows) => rows.isNotEmpty)) {
      throw const ApiException(
        "Equipment is borrowed or awaiting return review.",
        statusCode: 409,
      );
    }
    await db.update(
      "equipment",
      {"is_active": 0},
      where: "id=?",
      whereArgs: [id],
    );
    await _log(
      user["id"] as int,
      "inventory.equipment_removed",
      "equipment",
      id,
      detail: code,
    );
    return {"message": "Equipment removed from active inventory."};
  }

  Future<List<JsonMap>> _equipment() async =>
      (await (await _db).rawQuery(_equipmentSelect()));

  Future<JsonMap> getEquipmentDetails(
    String token,
    String equipmentCode,
  ) async {
    final user = await _userForToken(token);
    final db = await _db;
    final rows = await db.rawQuery(
      '''SELECT * FROM (${_equipmentSelect()}) inventory
         WHERE equipment_code=? LIMIT 1''',
      [equipmentCode],
    );
    if (rows.isEmpty) {
      throw const ApiException("Equipment was not found.", statusCode: 404);
    }
    final result = <String, dynamic>{"item": rows.first};
    if (user["role"] == "admin") {
      final id = rows.first["id"];
      result["borrowings"] = await db.rawQuery(
        '''SELECT b.transaction_code, b.borrowed_at, b.due_at, b.returned_at,
                  b.status, r.request_code, r.status AS request_status,
                  r.requested_at, u.account_id, u.full_name AS student_name
           FROM borrowing_transactions b
           JOIN borrowing_requests r ON r.id=b.request_id
           JOIN users u ON u.id=b.user_id
           WHERE b.equipment_id=? ORDER BY b.id DESC LIMIT 100''',
        [id],
      );
      result["returns"] = await db.rawQuery(
        '''SELECT rr.reported_condition, rr.status, rr.reported_at, rr.reviewed_at,
                  b.transaction_code, u.account_id, u.full_name AS student_name
           FROM return_reports rr
           JOIN borrowing_transactions b ON b.id=rr.transaction_id
           JOIN users u ON u.id=rr.user_id
           WHERE b.equipment_id=? ORDER BY rr.id DESC LIMIT 100''',
        [id],
      );
      result["exceptions"] = await db.rawQuery(
        '''SELECT exception_type, quantity, notes, status, created_at, resolved_at
           FROM inventory_exceptions WHERE equipment_id=?
           ORDER BY id DESC LIMIT 100''',
        [id],
      );
    }
    return result;
  }

  String _equipmentSelect() => '''
    SELECT e.id, e.equipment_code, e.name, e.brand, e.model, e.category,
           e.serial_number, e.program, e.location, e.description,
           e.total_stock, e.item_condition, e.inventory_status, e.image_asset,
           e.is_active,
           COALESCE(b.borrowed_quantity,0) AS borrowed_quantity,
           COALESCE(b.overdue_quantity,0) AS overdue_quantity,
           COALESCE(r.pending_quantity,0) AS pending_quantity,
           COALESCE(x.damaged_quantity,0) AS damaged_quantity,
           COALESCE(x.lost_quantity,0) AS lost_quantity,
           COALESCE(x.maintenance_quantity,0) AS maintenance_quantity,
           CASE
             WHEN e.is_active=0 OR LOWER(e.inventory_status) IN
               ('retired','maintenance','under maintenance','under_maintenance','lost','damaged')
               OR LOWER(e.item_condition)='damaged' OR COALESCE(x.damaged_quantity,0)>0 THEN 0
             ELSE MAX(0,e.total_stock-COALESCE(b.borrowed_quantity,0)
             -COALESCE(x.reserved_quantity,0)) END AS available_stock,
           CASE
             WHEN e.is_active=0 OR LOWER(e.inventory_status)='retired' THEN 'Retired'
             WHEN LOWER(e.inventory_status) IN ('maintenance','under maintenance','under_maintenance') THEN 'Under Maintenance'
             WHEN LOWER(e.inventory_status)='lost' THEN 'Lost'
             WHEN LOWER(e.inventory_status)='damaged' THEN 'Damaged'
             WHEN COALESCE(x.lost_quantity,0)>0 AND
                  e.total_stock-COALESCE(b.borrowed_quantity,0)-COALESCE(x.reserved_quantity,0)<=0 THEN 'Lost'
             WHEN COALESCE(x.damaged_quantity,0)>0 OR LOWER(e.item_condition)='damaged' THEN 'Damaged'
             WHEN COALESCE(b.overdue_quantity,0)>0 THEN 'Overdue'
             WHEN COALESCE(b.borrowed_quantity,0)>0 THEN 'Borrowed'
             WHEN COALESCE(r.pending_quantity,0)>0 THEN 'Pending'
             WHEN e.total_stock-COALESCE(x.reserved_quantity,0)>0 THEN 'Available'
             ELSE 'Unavailable'
           END AS status
    FROM equipment e
    LEFT JOIN (
      SELECT equipment_id, COUNT(*) AS borrowed_quantity,
             SUM(CASE WHEN due_at < datetime('now') THEN 1 ELSE 0 END) AS overdue_quantity
      FROM borrowing_transactions
      WHERE status IN ('active','return_pending')
      GROUP BY equipment_id
    ) b ON b.equipment_id=e.id
    LEFT JOIN (
      SELECT equipment_id, SUM(quantity) AS reserved_quantity,
             SUM(CASE WHEN exception_type='damaged' THEN quantity ELSE 0 END) AS damaged_quantity,
             SUM(CASE WHEN exception_type='missing' THEN quantity ELSE 0 END) AS lost_quantity,
             SUM(CASE WHEN LOWER(exception_type)='maintenance' THEN quantity ELSE 0 END) AS maintenance_quantity
      FROM inventory_exceptions WHERE status='open'
      GROUP BY equipment_id
    ) x ON x.equipment_id=e.id
    LEFT JOIN (
      SELECT equipment_id, COUNT(*) AS pending_quantity
      FROM borrowing_requests WHERE status='pending'
      GROUP BY equipment_id
    ) r ON r.equipment_id=e.id
  ''';

  Future<List<JsonMap>> _requests(JsonMap user) async {
    final where = user["role"] == "admin" ? "" : "WHERE r.user_id=?";
    final rows = await (await _db).rawQuery('''
      SELECT r.*, e.equipment_code, e.name AS item_name, e.image_asset, e.category,
             u.id AS student_id, u.account_id, u.full_name AS student_name
      FROM borrowing_requests r
      JOIN equipment e ON e.id=r.equipment_id
      JOIN users u ON u.id=r.user_id
      $where ORDER BY r.id DESC
    ''', user["role"] == "admin" ? [] : [user["id"]]);
    return rows;
  }

  Future<List<JsonMap>> _borrowings(JsonMap user) async {
    final where = user["role"] == "admin" ? "" : "WHERE b.user_id=?";
    return (await _db).rawQuery('''
      SELECT b.*, e.equipment_code, e.name AS item_name, e.image_asset,
             u.account_id, u.full_name AS student_name,
             r.request_code, r.requested_at
      FROM borrowing_transactions b
      JOIN equipment e ON e.id=b.equipment_id
      JOIN users u ON u.id=b.user_id
      JOIN borrowing_requests r ON r.id=b.request_id
      $where ORDER BY b.id DESC
    ''', user["role"] == "admin" ? [] : [user["id"]]);
  }

  Future<List<JsonMap>> _returns(JsonMap user) async {
    final where = user["role"] == "admin" ? "" : "WHERE r.user_id=?";
    return (await _db).rawQuery('''
      SELECT r.*, r.photo_data IS NOT NULL AS has_photo,
             b.transaction_code, b.equipment_id, b.user_id,
             e.equipment_code, e.name AS item_name,
             q.request_code,
             u.account_id, u.full_name AS student_name
      FROM return_reports r
      JOIN borrowing_transactions b ON b.id=r.transaction_id
      JOIN borrowing_requests q ON q.id=b.request_id
      JOIN equipment e ON e.id=b.equipment_id
      JOIN users u ON u.id=r.user_id
      $where ORDER BY r.id DESC
    ''', user["role"] == "admin" ? [] : [user["id"]]);
  }

  Future<List<JsonMap>> _penalties(JsonMap user) async {
    final where = user["role"] == "admin" ? "" : "WHERE p.user_id=?";
    return (await _db).rawQuery('''
      SELECT p.*, b.transaction_code, u.account_id, u.full_name AS student_name
      FROM penalties p JOIN users u ON u.id=p.user_id
      LEFT JOIN borrowing_transactions b ON b.id=p.transaction_id
      $where ORDER BY p.id DESC
    ''', user["role"] == "admin" ? [] : [user["id"]]);
  }

  Future<List<JsonMap>> _payments(JsonMap user) async {
    final where = user["role"] == "admin" ? "" : "WHERE p.user_id=?";
    return (await _db).rawQuery('''
      SELECT p.*, u.account_id, u.full_name AS student_name
      FROM payments p JOIN users u ON u.id=p.user_id
      $where ORDER BY p.id DESC
    ''', user["role"] == "admin" ? [] : [user["id"]]);
  }

  Future<List<JsonMap>> _exceptions() async => (await _db).rawQuery('''
    SELECT x.*, e.equipment_code, e.name AS item_name,
           u.account_id, u.full_name AS reported_by_name
    FROM inventory_exceptions x
    JOIN equipment e ON e.id=x.equipment_id
    JOIN users u ON u.id=x.reported_by
    ORDER BY x.id DESC
  ''');

  Future<List<JsonMap>> getSlips(int userId) async => (await _db).rawQuery(
    '''
        SELECT b.*, e.equipment_code, e.name AS item_name, e.category,
               e.image_asset, u.account_id, u.full_name AS student_name,
               r.request_code, r.requested_at, r.reviewed_at
        FROM borrowing_transactions b
        JOIN equipment e ON e.id=b.equipment_id
        JOIN users u ON u.id=b.user_id
        JOIN borrowing_requests r ON r.id=b.request_id
        WHERE b.user_id=? ORDER BY b.id DESC
      ''',
    [userId],
  );

  Future<JsonMap> _userForToken(String token) async {
    final match = RegExp(r"^offline:(\d+)$").firstMatch(token);
    if (match == null) {
      throw const ApiException("Sign in to continue.", statusCode: 401);
    }
    final rows = await (await _db).query(
      "users",
      where: "id=? AND account_status='active'",
      whereArgs: [int.parse(match.group(1)!)],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const ApiException(
        "Offline account was not found.",
        statusCode: 401,
      );
    }
    return rows.first;
  }

  Future<int> _availableStock(
    int equipmentId, [
    DatabaseExecutor? executor,
  ]) async {
    final db = executor ?? await _db;
    final rows = await db.rawQuery(
      '''
      SELECT MAX(0, e.total_stock
        - (SELECT COUNT(*) FROM borrowing_transactions b
           WHERE b.equipment_id=e.id AND b.status IN ('active','return_pending'))
        - COALESCE((SELECT SUM(x.quantity) FROM inventory_exceptions x
           WHERE x.equipment_id=e.id AND x.status='open'),0)) AS available_stock
      FROM equipment e WHERE e.id=? AND e.is_active=1 AND LOWER(e.inventory_status)='active'
    ''',
      [equipmentId],
    );
    return rows.isEmpty ? 0 : _int(rows.first["available_stock"]);
  }

  Future<int> _count(
    String table, {
    String? where,
    DatabaseExecutor? txn,
  }) async {
    final db = txn ?? await _db;
    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS n FROM $table ${where == null ? "" : "WHERE $where"}",
    );
    return _int(rows.first["n"]);
  }

  Future<double> _sum(
    String table,
    String column, {
    String? where,
    DatabaseExecutor? txn,
  }) async {
    final db = txn ?? await _db;
    final rows = await db.rawQuery(
      "SELECT COALESCE(SUM($column),0) AS n FROM $table ${where == null ? "" : "WHERE $where"}",
    );
    return _number(rows.first["n"]);
  }

  Future<void> _log(
    int? actor,
    String action,
    String type,
    int? id, {
    String? detail,
    DatabaseExecutor? txn,
  }) async {
    await (txn ?? await _db).insert("system_logs", {
      "actor_id": actor,
      "action": action,
      "entity_type": type,
      "entity_id": id,
      "details": detail,
      "created_at": _now(),
    });
  }

  static JsonMap _publicUser(JsonMap user) => {
    for (final entry in user.entries)
      if (entry.key != "password_hash") entry.key: entry.value,
  };

  static void _requireAdmin(JsonMap user) {
    if (user["role"] != "admin") {
      throw const ApiException(
        "Administrator access is required.",
        statusCode: 403,
      );
    }
  }

  static String _now() => DateTime.now().toIso8601String();

  static String _yearCode(String prefix, int id) =>
      "$prefix-${DateTime.now().year}-${id.toString().padLeft(6, "0")}";

  static int _int(dynamic value) => int.tryParse(value?.toString() ?? "") ?? 0;

  static double _number(dynamic value) =>
      double.tryParse(value?.toString() ?? "") ?? 0;

  static bool _strongPassword(String value) =>
      value.length >= 8 &&
      RegExp(r"[A-Z]").hasMatch(value) &&
      RegExp(r"[a-z]").hasMatch(value) &&
      RegExp(r"\d").hasMatch(value) &&
      RegExp(r"[^A-Za-z0-9]").hasMatch(value);

  Future<int> cacheUser(JsonMap user, String password) async {
    final db = await _db;
    final accountId = user["account_id"] as String;
    final existing = await db.query(
      "users",
      where: "account_id=?",
      whereArgs: [accountId],
      limit: 1,
    );
    final values = <String, Object?>{
      "account_id": user["account_id"],
      "full_name": user["full_name"],
      "password_hash": _hash(password),
      "role": user["role"],
      "email": user["email"],
      "program_section": user["program_section"],
      "contact_number": user["contact_number"],
      "account_status": user["account_status"] ?? "active",
      "profile_photo": user["profile_photo"],
      "profile_version": user["profile_version"] ?? 1,
      "updated_at": user["updated_at"],
    };
    if (existing.isEmpty) {
      values["profile_photo_data"] = null;
      return db.insert("users", values);
    }
    final row = existing.first;
    if (row["profile_photo"] != user["profile_photo"]) {
      values["profile_photo_data"] = null;
    }
    final localId = row["id"] as int;
    await db.update("users", values, where: "id=?", whereArgs: [localId]);
    return localId;
  }

  Future<void> cacheSyncedProfile(
    JsonMap user, {
    Uint8List? photoBytes,
    bool removePhoto = false,
  }) async {
    final accountId = user["account_id"] as String?;
    if (accountId == null || accountId.isEmpty) return;
    final db = await _db;
    final existing = await db.query(
      "users",
      where: "account_id=?",
      whereArgs: [accountId],
      limit: 1,
    );
    if (existing.isEmpty) {
      await _ensureUser(db, user);
    }
    final prior = existing.isEmpty ? null : existing.first;
    final serverPhoto = user["profile_photo"];
    final values = <String, Object?>{
      "full_name": user["full_name"],
      "email": user["email"],
      "program_section": user["program_section"],
      "contact_number": user["contact_number"],
      "account_status": user["account_status"] ?? "active",
      "profile_photo": user["profile_photo"],
      "profile_version": user["profile_version"] ?? 1,
      "updated_at": user["updated_at"],
    };
    if (photoBytes != null) values["profile_photo_data"] = photoBytes;
    if (removePhoto ||
        (prior != null && prior["profile_photo"] != serverPhoto)) {
      values["profile_photo_data"] = null;
    }
    await db.update(
      "users",
      values,
      where: "account_id=?",
      whereArgs: [accountId],
    );
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
    _opening = null;
  }
}
