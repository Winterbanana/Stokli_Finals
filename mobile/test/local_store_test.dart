import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:sqflite_common_ffi/sqflite_ffi.dart";
import "package:stokli_mobile/api_exception.dart";
import "package:stokli_mobile/local_store.dart";

void main() {
  late Directory tempDirectory;
  late Database database;
  late LocalStore store;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp("stokli-test-");
    database = await databaseFactory.openDatabase(
      "${tempDirectory.path}\\stokli_test.db",
    );
    await LocalStore.createSchema(database);
    await LocalStore.seed(database);
    store = LocalStore(database: database);
  });

  tearDown(() async {
    await store.close();
    await tempDirectory.delete(recursive: true);
  });

  test(
    "seeds all student/admin accounts and the full equipment catalogue",
    () async {
      final student = await store.login({
        "role": "student",
        "account_id": "STUDENT-001",
        "password": "demo-student",
      });
      final equipment = await store.get(
        "equipment",
        student["token"] as String,
      );
      final items = equipment["items"] as List<JsonMap>;
      expect(items, hasLength(8));
      expect(items.map((item) => item["equipment_code"]).toSet(), {
        "STK-001",
        "STK-002",
        "STK-003",
        "STK-004",
        "STK-005",
        "STK-006",
        "STK-007",
        "STK-008",
      });

      await expectLater(
        store.login({
          "role": "student",
          "account_id": "ADMIN-001",
          "password": "demo-admin",
        }),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test("caches MySQL snapshots and preserves queued local changes", () async {
    final student = await store.login({
      "role": "student",
      "account_id": "STUDENT-001",
      "password": "demo-student",
    });
    final token = student["token"] as String;
    final user = student["user"] as JsonMap;
    const requestCode = "REQ-OFFLINE-TEST-0001";
    final request = await store.post("create_request", {
      "equipment_code": "STK-005",
      "request_code": requestCode,
    }, token);
    await store.queuePendingOperation(
      operationId: "0123456789abcdef0123456789abcdef",
      accountId: user["account_id"] as String,
      action: "create_request",
      body: {"equipment_code": "STK-005", "request_code": requestCode},
      token: token,
      result: request,
    );

    await store.cacheRemoteResponse("equipment", user["account_id"] as String, {
      "items": [
        {
          "equipment_code": "STK-005",
          "name": "Updated from MySQL",
          "category": "Audio",
          "available_stock": 9,
          "total_stock": 10,
        },
      ],
    });
    final localEquipment = await store.get("equipment", token);
    final equipment = await store.overlayRemoteSnapshot(
      "equipment",
      user["account_id"] as String,
      localEquipment,
      user,
    );
    expect(
      (equipment["items"] as List<JsonMap>).single["name"],
      "Updated from MySQL",
    );

    await store.cacheRemoteResponse("requests", user["account_id"] as String, {
      "requests": <JsonMap>[],
    });
    final requests = await store.overlayRemoteSnapshot(
      "requests",
      user["account_id"] as String,
      await store.get("requests", token),
      user,
    );
    expect(
      (requests["requests"] as List<JsonMap>).singleWhere(
        (row) => row["request_code"] == requestCode,
      )["status"],
      "pending",
    );
    expect(await store.pendingOperationCount(), 1);
    await store.removePendingOperation("0123456789abcdef0123456789abcdef");
    expect(await store.pendingOperationCount(), 0);
  });

  test(
    "caches MySQL borrowings and return reports over seeded SQLite records",
    () async {
      final student = await store.login({
        "role": "student",
        "account_id": "STUDENT-001",
        "password": "demo-student",
      });
      const requestCode = "REQ-2026-0048";
      const transactionCode = "BOR-2026-0001";
      const borrowedAt = "2026-10-01 12:00:00";
      const dueAt = "2026-10-01 20:00:00";
      const reportedAt = "2026-10-01 14:00:00";
      final studentUser = student["user"] as JsonMap;
      final accountId = studentUser["account_id"] as String;
      final borrowing = {
        "transaction_code": transactionCode,
        "request_code": requestCode,
        "account_id": accountId,
        "student_name": studentUser["full_name"],
        "equipment_code": "STK-001",
        "item_name": "Laptop",
        "status": "return_pending",
        "borrowed_at": borrowedAt,
        "due_at": dueAt,
        "returned_at": null,
      };

      await store.cacheRemoteResponse("borrowings", accountId, {
        "borrowings": [borrowing],
      });
      await store.cacheRemoteResponse("returns", accountId, {
        "returns": [
          {
            ...borrowing,
            "id": 901,
            "transaction_id": 901,
            "reported_condition": "Good",
            "status": "pending",
            "borrowing_status": "return_pending",
            "reported_at": reportedAt,
            "reviewed_at": null,
          },
        ],
      });

      final transactions = await database.rawQuery(
        '''SELECT b.id, b.transaction_code, b.status, b.borrowed_at, b.due_at
           FROM borrowing_transactions b
           JOIN borrowing_requests r ON r.id=b.request_id
           WHERE r.request_code=?''',
        [requestCode],
      );
      expect(transactions, hasLength(1));
      expect(transactions.single["transaction_code"], transactionCode);
      expect(transactions.single["status"], "return_pending");
      expect(transactions.single["borrowed_at"], borrowedAt);
      expect(transactions.single["due_at"], dueAt);

      final reports = await database.query("return_reports");
      expect(reports, hasLength(1));
      expect(reports.single["transaction_id"], transactions.single["id"]);
      expect(reports.single["status"], "pending");
    },
  );

  test(
    "paginates every inventory record and searches beyond the loaded page",
    () async {
      final student = await store.login({
        "role": "student",
        "account_id": "STUDENT-001",
        "password": "demo-student",
      });
      final token = student["token"] as String;
      final batch = database.batch();
      for (var index = 0; index < 1000; index++) {
        final serial = index.toString().padLeft(4, "0");
        batch.insert("equipment", {
          "equipment_code": "LOAD-$serial",
          "name": index == 997
              ? "Remote camera sensor"
              : "Load test item $serial",
          "brand": "Load Test",
          "model": "Model $serial",
          "category": index.isEven ? "Sensors" : "Peripherals",
          "serial_number": "SERIAL-$serial",
          "program": "Performance test",
          "location": "Storage $serial",
          "description": "Synthetic test fixture",
          "total_stock": 5,
          "item_condition": index == 996 ? "Damaged" : "Good",
          "inventory_status": switch (index) {
            998 => "maintenance",
            999 => "retired",
            _ => "active",
          },
          "is_active": index == 999 ? 0 : 1,
        });
      }
      await batch.commit(noResult: true);

      final allItems = <JsonMap>[];
      var offset = 0;
      var hasMore = true;
      while (hasMore) {
        final page = await store.getEquipmentPage(
          token,
          limit: 30,
          offset: offset,
        );
        final items = page["items"] as List<JsonMap>;
        allItems.addAll(items);
        offset += items.length;
        hasMore = page["has_more"] as bool;
      }
      expect(allItems, hasLength(1008));
      expect(
        allItems.map((item) => item["equipment_code"]).toSet(),
        hasLength(1008),
      );
      for (final threshold in [10, 100, 500, 1000]) {
        expect(allItems.take(threshold), hasLength(threshold));
      }
      final admin = await store.login({
        "role": "admin",
        "account_id": "ADMIN-001",
        "password": "demo-admin",
      });
      final statsResponse = await store.get(
        "admin_stats",
        admin["token"] as String,
      );
      final stats = statsResponse["stats"] as JsonMap;
      expect(stats["equipment_count"], allItems.length);
      expect(
        stats["available_quantity"],
        allItems.fold<int>(
          0,
          (sum, item) => sum + int.parse(item["available_stock"].toString()),
        ),
      );

      final search = await store.getEquipmentPage(token, search: "SERIAL-0999");
      final retired = (search["items"] as List<JsonMap>).single;
      expect(retired["equipment_code"], "LOAD-0999");
      expect(retired["status"], "Retired");
      expect(retired["available_stock"], 0);

      final maintenanceSearch = await store.getEquipmentPage(
        token,
        search: "SERIAL-0998",
      );
      expect(
        (maintenanceSearch["items"] as List<JsonMap>).single["status"],
        "Under Maintenance",
      );
      expect(
        (maintenanceSearch["items"] as List<JsonMap>).single["available_stock"],
        0,
      );

      final damagedSearch = await store.getEquipmentPage(
        token,
        search: "SERIAL-0996",
      );
      expect(
        (damagedSearch["items"] as List<JsonMap>).single["status"],
        "Damaged",
      );
      expect(
        (damagedSearch["items"] as List<JsonMap>).single["available_stock"],
        0,
      );

      final nameSearch = await store.getEquipmentPage(
        token,
        search: "Remote camera sensor",
      );
      expect(
        (nameSearch["items"] as List<JsonMap>).single["equipment_code"],
        "LOAD-0997",
      );
      final categoryFilter = await store.getEquipmentPage(
        token,
        category: "Sensors",
      );
      expect(categoryFilter["total_count"], greaterThan(1));
    },
  );

  test(
    "queues a complete workflow with stable cross-database references",
    () async {
      final student = await store.login({
        "role": "student",
        "account_id": "STUDENT-001",
        "password": "demo-student",
      });
      final admin = await store.login({
        "role": "admin",
        "account_id": "ADMIN-001",
        "password": "demo-admin",
      });
      final studentToken = student["token"] as String;
      final adminToken = admin["token"] as String;
      final studentAccount = student["user"]["account_id"] as String;
      final adminAccount = admin["user"]["account_id"] as String;

      const requestCode = "REQ-OFFLINE-SYNC-0001";
      final request = await store.post("create_request", {
        "equipment_code": "STK-006",
        "request_code": requestCode,
      }, studentToken);
      await store.queuePendingOperation(
        operationId: "11111111111111111111111111111111",
        accountId: studentAccount,
        action: "create_request",
        body: {"equipment_code": "STK-006", "request_code": requestCode},
        token: studentToken,
        result: request,
      );

      await store.post("review_request", {
        "request_id": request["request_id"],
        "decision": "approved",
      }, adminToken);
      await store.queuePendingOperation(
        operationId: "22222222222222222222222222222222",
        accountId: adminAccount,
        action: "review_request",
        body: {"request_id": request["request_id"], "decision": "approved"},
        token: adminToken,
      );
      final borrowing = (await store.get(
        "borrowings",
        studentToken,
      ))["borrowings"].singleWhere((row) => row["request_code"] == requestCode);
      final returnResult = await store.post("create_return", {
        "transaction_id": borrowing["id"],
        "condition": "Good",
      }, studentToken);
      await store.queuePendingOperation(
        operationId: "33333333333333333333333333333333",
        accountId: studentAccount,
        action: "create_return",
        body: {"transaction_id": borrowing["id"], "condition": "Good"},
        token: studentToken,
        result: returnResult,
      );
      final report = (await store.get(
        "returns",
        adminToken,
      ))["returns"].singleWhere((row) => row["request_code"] == requestCode);
      await store.post("review_return", {
        "report_id": report["id"],
        "decision": "accept",
      }, adminToken);
      await store.queuePendingOperation(
        operationId: "44444444444444444444444444444444",
        accountId: adminAccount,
        action: "review_return",
        body: {"report_id": report["id"], "decision": "accept"},
        token: adminToken,
      );

      final studentOperations = await store.pendingOperations(studentAccount);
      final adminOperations = await store.pendingOperations(adminAccount);
      expect(studentOperations, hasLength(2));
      expect(adminOperations, hasLength(2));
      for (final operation in [...studentOperations, ...adminOperations]) {
        final payload = jsonDecode(operation["payload"] as String) as JsonMap;
        expect(payload["request_code"], requestCode);
      }
    },
  );

  test(
    "persists complete borrow, declined return, resubmission, and slip flow",
    () async {
      final studentLogin = await store.login({
        "role": "student",
        "account_id": "STUDENT-001",
        "password": "demo-student",
      });
      final studentToken = studentLogin["token"] as String;
      final adminLogin = await store.login({
        "role": "admin",
        "account_id": "ADMIN-001",
        "password": "demo-admin",
      });
      final adminToken = adminLogin["token"] as String;

      final declinedRequest = await store.post("create_request", {
        "equipment_code": "STK-005",
      }, studentToken);
      final declinedRequestId = declinedRequest["request_id"] as int;
      expect(declinedRequest["request_code"], startsWith("REQ-"));
      await store.post("review_request", {
        "request_id": declinedRequestId,
        "decision": "rejected",
      }, adminToken);
      var requests =
          (await store.get("requests", studentToken))["requests"]
              as List<JsonMap>;
      expect(
        requests.singleWhere((row) => row["id"] == declinedRequestId)["status"],
        "rejected",
      );

      final request = await store.post("create_request", {
        "equipment_code": "STK-005",
      }, studentToken);
      final requestId = request["request_id"] as int;

      await store.post("review_request", {
        "request_id": requestId,
        "decision": "approved",
      }, adminToken);
      requests =
          (await store.get("requests", studentToken))["requests"]
              as List<JsonMap>;
      expect(
        requests.singleWhere((row) => row["id"] == requestId)["status"],
        "approved",
      );
      final borrowings =
          (await store.get("borrowings", studentToken))["borrowings"]
              as List<JsonMap>;
      final borrowing = borrowings.singleWhere(
        (row) => row["request_code"] == request["request_code"],
      );
      expect(borrowing["status"], "active");
      expect(borrowing["student_name"], "Demo Student 1");

      const photo = "aGVsbG8=";
      await store.post("create_return", {
        "transaction_id": borrowing["id"],
        "condition": "Good",
        "photo_base64": photo,
      }, studentToken);
      var returns =
          (await store.get("returns", adminToken))["returns"] as List<JsonMap>;
      var report = returns.singleWhere(
        (row) => row["transaction_id"] == borrowing["id"],
      );
      expect(report["has_photo"], 1);
      expect(
        (await store.post("return_photo", {
          "report_id": report["id"],
        }, adminToken))["photo_base64"],
        photo,
      );

      await store.post("review_return", {
        "report_id": report["id"],
        "decision": "reject",
      }, adminToken);
      expect(
        (await store.get("borrowings", studentToken))["borrowings"].singleWhere(
          (row) => row["id"] == borrowing["id"],
        )["status"],
        "active",
      );
      await store.post("create_return", {
        "transaction_id": borrowing["id"],
        "condition": "Good",
      }, studentToken);
      returns =
          (await store.get("returns", adminToken))["returns"] as List<JsonMap>;
      report = returns.firstWhere(
        (row) =>
            row["transaction_id"] == borrowing["id"] &&
            row["status"] == "pending",
      );
      await store.post("review_return", {
        "report_id": report["id"],
        "decision": "accept",
      }, adminToken);
      final slips = await store.getSlips(studentLogin["user"]["id"] as int);
      final slip = slips.singleWhere((row) => row["id"] == borrowing["id"]);
      expect(slip["transaction_code"], borrowing["transaction_code"]);
      expect(slip["status"], "returned");

      final nextRequest = await store.post("create_request", {
        "equipment_code": "STK-005",
      }, studentToken);
      expect(nextRequest["request_id"], isNot(requestId));
      requests =
          (await store.get("requests", studentToken))["requests"]
              as List<JsonMap>;
      expect(
        requests.singleWhere(
          (row) => row["id"] == nextRequest["request_id"],
        )["status"],
        "pending",
      );
    },
  );

  test(
    "uses stable codes when cached MySQL IDs differ from SQLite IDs",
    () async {
      final student = await store.login({
        "role": "student",
        "account_id": "STUDENT-001",
        "password": "demo-student",
      });
      final admin = await store.login({
        "role": "admin",
        "account_id": "ADMIN-001",
        "password": "demo-admin",
      });
      final studentToken = student["token"] as String;
      final adminToken = admin["token"] as String;
      final studentAccount = student["user"]["account_id"] as String;
      final adminAccount = admin["user"]["account_id"] as String;
      const requestCode = "REQ-SERVER-REMOTE-1";

      await store.cacheRemoteResponse("equipment", studentAccount, {
        "items": [
          {
            "id": 900,
            "equipment_code": "STK-002",
            "name": "Server RGB Keyboard",
            "category": "Peripherals",
            "total_stock": 3,
            "available_stock": 3,
          },
        ],
      });
      final remoteRequest = {
        "id": 901,
        "request_code": requestCode,
        "student_id": 902,
        "account_id": studentAccount,
        "student_name": "Demo Student 1",
        "equipment_code": "STK-002",
        "item_name": "Server RGB Keyboard",
        "status": "pending",
        "requested_at": "2026-10-01 12:00:00",
      };
      await store.cacheRemoteResponse("requests", studentAccount, {
        "requests": [remoteRequest],
      });
      await store.cacheRemoteResponse("requests", adminAccount, {
        "requests": [remoteRequest],
      });
      await store.post("review_request", {
        "request_id": 901,
        "request_code": requestCode,
        "decision": "approved",
      }, adminToken);
      var borrowings =
          (await store.get("borrowings", studentToken))["borrowings"]
              as List<JsonMap>;
      expect(
        borrowings.singleWhere(
          (row) => row["request_code"] == requestCode,
        )["status"],
        "active",
      );

      await store.post("create_return", {
        "transaction_id": 903,
        "request_code": requestCode,
        "condition": "Good",
      }, studentToken);
      final returns =
          (await store.get("returns", adminToken))["returns"] as List<JsonMap>;
      final report = returns.singleWhere(
        (row) => row["request_code"] == requestCode,
      );
      expect(report["status"], "pending");
      await store.post("review_return", {
        "report_id": 904,
        "request_code": requestCode,
        "decision": "accept",
      }, adminToken);
      borrowings =
          (await store.get("borrowings", studentToken))["borrowings"]
              as List<JsonMap>;
      expect(
        borrowings.singleWhere(
          (row) => row["request_code"] == requestCode,
        )["status"],
        "returned",
      );

      const paymentCode = "PAY-SERVER-REMOTE-1";
      await store.cacheRemoteResponse("payments", studentAccount, {
        "payments": [
          {
            "id": 905,
            "payment_code": paymentCode,
            "account_id": studentAccount,
            "student_name": "Demo Student 1",
            "amount": 50.0,
            "method": "Cash",
            "status": "pending",
            "created_at": "2026-10-01 12:00:00",
          },
        ],
      });
      await store.post("review_payment", {
        "payment_id": 905,
        "payment_code": paymentCode,
        "decision": "verify",
      }, adminToken);
      final payments =
          (await store.get("payments", studentToken))["payments"]
              as List<JsonMap>;
      expect(
        payments.singleWhere(
          (row) => row["payment_code"] == paymentCode,
        )["status"],
        "verified",
      );

      await store.cacheRemoteResponse("exceptions", adminAccount, {
        "exceptions": [
          {
            "id": 906,
            "equipment_code": "STK-002",
            "item_name": "Server RGB Keyboard",
            "account_id": adminAccount,
            "reported_by_name": "Demo Admin 1",
            "exception_type": "damaged",
            "quantity": 1,
            "notes": "Server-side inspection",
            "status": "open",
            "created_at": "2026-10-01 12:00:00",
          },
        ],
      });
      await store.post("resolve_exception", {
        "exception_id": 906,
        "equipment_code": "STK-002",
        "exception_type": "damaged",
      }, adminToken);
      final exceptions =
          (await store.get("exceptions", adminToken))["exceptions"]
              as List<JsonMap>;
      expect(
        exceptions.singleWhere(
          (row) =>
              row["equipment_code"] == "STK-002" &&
              row["notes"] == "Server-side inspection",
        )["status"],
        "resolved",
      );
    },
  );

  test(
    "records partial payments and clears penalties only after verification",
    () async {
      final student = await store.login({
        "role": "student",
        "account_id": "STUDENT-001",
        "password": "demo-student",
      });
      final studentToken = student["token"] as String;
      final admin = await store.login({
        "role": "admin",
        "account_id": "ADMIN-001",
        "password": "demo-admin",
      });
      final adminToken = admin["token"] as String;

      await store.post("create_payment", {
        "amount": 50,
        "method": "GCash",
        "reference_note": "TEST-50",
      }, studentToken);
      await expectLater(
        store.post("create_payment", {
          "amount": 151,
          "method": "Maya",
        }, studentToken),
        throwsA(isA<ApiException>()),
      );
      var payments =
          (await store.get("payments", adminToken))["payments"]
              as List<JsonMap>;
      var payment = payments.singleWhere(
        (row) => row["reference_note"] == "TEST-50",
      );
      await store.post("review_payment", {
        "payment_id": payment["id"],
        "decision": "verify",
      }, adminToken);
      var penalties =
          (await store.get("penalties", studentToken))["penalties"]
              as List<JsonMap>;
      expect(penalties.single["amount_paid"], 50.0);
      expect(penalties.single["status"], "unpaid");

      await store.post("create_payment", {
        "amount": 150,
        "method": "Cash",
      }, studentToken);
      payments =
          (await store.get("payments", adminToken))["payments"]
              as List<JsonMap>;
      payment = payments.singleWhere((row) => row["method"] == "Cash");
      await store.post("review_payment", {
        "payment_id": payment["id"],
        "decision": "verify",
      }, adminToken);
      final result = await store.get("penalties", studentToken);
      penalties = result["penalties"] as List<JsonMap>;
      expect(penalties.single["status"], "paid");
      expect(result["outstanding_balance"], 0.0);
    },
  );

  test(
    "queues offline profile/photo edits and rejects stale versions",
    () async {
      final student = await store.login({
        "role": "student",
        "account_id": "STUDENT-001",
        "password": "demo-student",
      });
      final token = student["token"] as String;
      final user = student["user"] as JsonMap;
      final photo = [0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46];
      final body = {
        "expected_version": 1,
        "full_name": "Updated Student",
        "email": "student-profile@example.test",
        "contact_number": "09123456789",
        "program_section": "BSIT 204",
        "profile_photo_base64": base64Encode(photo),
      };

      final result = await store.post("update_profile", body, token);
      final updatedUser = result["user"] as JsonMap;
      expect(updatedUser["full_name"], "Updated Student");
      expect(updatedUser["profile_version"], 2);
      expect(updatedUser["profile_photo_data"], photo);
      await store.queuePendingOperation(
        operationId: "abcdef0123456789abcdef0123456789",
        accountId: user["account_id"] as String,
        action: "update_profile",
        body: body,
        token: token,
        result: result,
      );
      expect(await store.pendingOperationCount(), 1);
      final queued = (await store.pendingOperations(
        user["account_id"] as String,
      )).single;
      expect(queued["payload"], isNot(contains("demo-student")));

      await expectLater(
        store.post("update_profile", body, token),
        throwsA(
          isA<ApiException>().having(
            (error) => error.statusCode,
            "statusCode",
            409,
          ),
        ),
      );
      await expectLater(
        store.post("update_profile", {
          ...body,
          "expected_version": 2,
          "target_account_id": "STUDENT-002",
        }, token),
        throwsA(
          isA<ApiException>().having(
            (error) => error.statusCode,
            "statusCode",
            403,
          ),
        ),
      );
    },
  );

  test("admin edits a Student and can inspect related local records", () async {
    final admin = await store.login({
      "role": "admin",
      "account_id": "ADMIN-001",
      "password": "demo-admin",
    });
    final adminToken = admin["token"] as String;
    final result = await store.post("update_profile", {
      "target_account_id": "STUDENT-002",
      "expected_version": 1,
      "full_name": "Admin Edited Student",
      "email": "admin-edited@example.test",
      "contact_number": "",
      "program_section": "BSCS 301",
      "account_status": "suspended",
    }, adminToken);
    final profile = result["user"] as JsonMap;
    expect(profile["full_name"], "Admin Edited Student");
    expect(profile["account_status"], "suspended");
    expect(profile["role"], "student");

    final detail = await store.getStudentAccount("STUDENT-002", adminToken);
    expect((detail["profile"] as JsonMap)["profile_version"], 2);
    expect(detail["requests"], isA<List<JsonMap>>());
    expect(detail["borrowings"], isA<List<JsonMap>>());
    expect(detail["returns"], isA<List<JsonMap>>());
    expect(detail["penalties"], isA<List<JsonMap>>());
    expect(detail["payments"], isA<List<JsonMap>>());
    expect(detail["activities"], isA<List<JsonMap>>());
    final logs = await database.query(
      "system_logs",
      where: "action=?",
      whereArgs: ["account.student_suspended"],
    );
    expect(logs, hasLength(1));
  });

  test(
    "resets only the browser demo database and reseeds its sample data",
    () async {
      final student = await store.login({
        "role": "student",
        "account_id": "STUDENT-001",
        "password": "demo-student",
      });
      final token = student["token"] as String;
      await store.post("create_request", {"equipment_code": "STK-005"}, token);
      expect(await store.pendingOperationCount(), 0);

      await store.resetDemoData();

      expect(await database.query("equipment"), hasLength(8));
      expect(await database.query("users"), hasLength(8));
      expect(await database.query("borrowing_requests"), hasLength(4));
      expect(await database.query("borrowing_transactions"), hasLength(1));
      expect(await database.query("payments"), isEmpty);
      final reseededStudent = await store.login({
        "role": "student",
        "account_id": "STUDENT-001",
        "password": "demo-student",
      });
      expect(reseededStudent["user"]["account_id"], "STUDENT-001");
    },
  );
}
