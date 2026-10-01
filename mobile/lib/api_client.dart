import "dart:async";
import "dart:convert";
import "dart:math";

import "package:flutter/foundation.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:http/http.dart" as http;
import "package:shared_preferences/shared_preferences.dart";

import "api_exception.dart";
import "local_store.dart";

typedef JsonMap = Map<String, dynamic>;

String normalizeApiEndpoint(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !uri.hasAuthority ||
      !const ["http", "https"].contains(uri.scheme) ||
      uri.host.isEmpty) {
    throw const ApiException("Enter a valid HTTP or HTTPS server URL.");
  }

  var path = uri.path;
  if (!path.endsWith("/index.php")) {
    if (path.isEmpty || path == "/") {
      path = "/Stokli BMC/api/index.php";
    } else if (path.endsWith("/api")) {
      path = "$path/index.php";
    } else {
      path = "${path.replaceFirst(RegExp(r"/+$"), "")}/api/index.php";
    }
  }
  return Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: path,
  ).toString();
}

class ApiClient {
  ApiClient._(this._preferences);

  static const _tokenKey = "stokli_session_token";
  static const _offlineKey = "stokli_offline_mode";
  static const _offlineUserKey = "stokli_offline_user_id";
  static const _accountIdKey = "stokli_account_id";
  static const _serverTokenKey = "stokli_server_session_token";
  static const defaultEndpoint = String.fromEnvironment(
    "STOKLI_API_BASE_URL",
    defaultValue: kIsWeb ? "" : "http://10.0.2.2/Stokli%20BMC/api/index.php",
  );

  final SharedPreferences _preferences;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final http.Client _client = http.Client();
  final LocalStore localStore = LocalStore();
  final Map<String, Future<JsonMap>> _equipmentRequests = {};
  final Map<String, Future<JsonMap>> _equipmentDetailRequests = {};
  String? _token;
  String? _serverToken;
  String? _accountId;
  bool _offlineMode = false;

  bool get hasToken => _token != null;

  static Future<ApiClient> create() async {
    final preferences = await SharedPreferences.getInstance();
    final client = ApiClient._(preferences);
    client._offlineMode = kIsWeb || (preferences.getBool(_offlineKey) ?? false);
    client._token = await client._secureStorage.read(key: _tokenKey);
    client._serverToken = await client._secureStorage.read(
      key: _serverTokenKey,
    );
    client._accountId = preferences.getString(_accountIdKey);
    await client.localStore.initialize();
    return client;
  }

  bool get isOffline => _offlineMode;
  bool get isWebDemo => kIsWeb;
  Future<int> get pendingSyncCount => localStore.pendingOperationCount();

  Future<JsonMap> getCachedEquipmentPage({int limit = 30}) =>
      localStore.getCachedEquipmentPage(limit: limit);

  Future<JsonMap> health() async {
    if (_offlineMode) {
      return localStore.get("health", _token ?? "");
    }
    try {
      return await _remoteRequest("GET", "health");
    } on ApiException catch (error) {
      if (error.statusCode != null && error.statusCode! < 500) rethrow;
      return {"ok": true, "service": "stokli-local", "database": "offline"};
    }
  }

  Future<JsonMap> login({
    required String role,
    required String accountId,
    required String password,
  }) async {
    final body = {"role": role, "account_id": accountId, "password": password};
    late JsonMap result;
    if (_offlineMode) {
      result = await localStore.post("login", body, "");
    } else {
      try {
        result = await _remoteRequest("POST", "login", body: body);
        final remoteUser = _asMap(result["user"]);
        final localUserId = await localStore.cacheUser(remoteUser, password);
        await _preferences.setInt(_offlineUserKey, localUserId);
        _accountId = remoteUser["account_id"] as String;
        _serverToken = result["token"] as String?;
        await _preferences.setString(_accountIdKey, _accountId!);
        await _secureStorage.write(key: _serverTokenKey, value: _serverToken);
      } on ApiException catch (error) {
        if (error.statusCode != null && error.statusCode! < 500) rethrow;
        result = await localStore.post("login", body, "");
        _offlineMode = true;
        await _preferences.setBool(_offlineKey, true);
      }
    }
    final token = result["token"];
    if (token is! String || token.isEmpty) {
      throw const ApiException(
        "The server returned an invalid sign-in response.",
      );
    }
    _token = token;
    await _secureStorage.write(key: _tokenKey, value: token);
    if (_offlineMode) {
      _accountId = _asMap(result["user"])["account_id"] as String?;
      if (_accountId != null) {
        await _preferences.setString(_accountIdKey, _accountId!);
      }
    }
    return _asMap(result["user"]);
  }

  Future<JsonMap> me() async {
    if (_offlineMode) {
      final user = _asMap((await localStore.me(_token ?? ""))["user"]);
      _accountId = user["account_id"] as String?;
      return user;
    }
    try {
      final user = _asMap((await _remoteRequest("GET", "me"))["user"]);
      _accountId = user["account_id"] as String?;
      if (_accountId != null) {
        await _preferences.setString(_accountIdKey, _accountId!);
      }
      return user;
    } on ApiException catch (error) {
      if (error.statusCode != null && error.statusCode! < 500) rethrow;
      await _switchToOffline();
      return _asMap((await localStore.me(_token ?? ""))["user"]);
    }
  }

  Uri profilePhotoUri(int userId) => Uri.parse(
    defaultEndpoint,
  ).replace(queryParameters: {"action": "profile_photo", "user_id": "$userId"});

  Map<String, String> get authenticatedImageHeaders => {
    if (_token != null) "Authorization": "Bearer $_token",
  };

  Future<JsonMap> register({
    required String accountId,
    required String fullName,
    required String password,
  }) async {
    final body = {
      "account_id": accountId,
      "full_name": fullName,
      "password": password,
    };
    if (_offlineMode) {
      if (kIsWeb) {
        return localStore.register(body);
      }
      throw const ApiException(
        "Connect to the server before creating a new account.",
        statusCode: 503,
      );
    }
    try {
      final response = await _remoteRequest("POST", "register", body: body);
      await localStore.cacheRegisteredUser(
        accountId: accountId,
        fullName: fullName,
        password: password,
      );
      return response;
    } on ApiException catch (error) {
      if (error.statusCode != null && error.statusCode! < 500) rethrow;
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      if (_token != null && !_offlineMode) {
        await _remoteRequest("POST", "logout", body: const {});
      }
    } finally {
      _token = null;
      _offlineMode = kIsWeb;
      await _preferences.setBool(_offlineKey, kIsWeb);
      await _preferences.remove(_offlineUserKey);
      await _secureStorage.delete(key: _tokenKey);
    }
  }

  Future<void> resetWebDemoData() async {
    if (!kIsWeb) {
      throw const ApiException(
        "Reset demo data is only available in the public Web Demo.",
        statusCode: 403,
      );
    }
    await localStore.resetDemoData();
    _token = null;
    _serverToken = null;
    _accountId = null;
    _offlineMode = true;
    await _preferences.setBool(_offlineKey, true);
    await _preferences.remove(_offlineUserKey);
    await _preferences.remove(_accountIdKey);
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _serverTokenKey);
  }

  Future<JsonMap> get(String action) async {
    if (_offlineMode) {
      final local = await localStore.get(action, _token ?? "");
      final user = _asMap((await localStore.me(_token ?? ""))["user"]);
      return localStore.overlayRemoteSnapshot(
        action,
        _accountId ?? user["account_id"] as String? ?? "",
        local,
        user,
      );
    }
    try {
      final response = await _remoteRequest("GET", action);
      if (_accountId != null) {
        await localStore.cacheRemoteResponse(action, _accountId!, response);
      }
      return response;
    } on ApiException catch (error) {
      if (error.statusCode != null && error.statusCode! < 500) rethrow;
      await _switchToOffline();
      final local = await localStore.get(action, _token ?? "");
      final user = _asMap((await localStore.me(_token ?? ""))["user"]);
      return localStore.overlayRemoteSnapshot(
        action,
        _accountId ?? user["account_id"] as String? ?? "",
        local,
        user,
      );
    }
  }

  Future<JsonMap> getEquipmentPage({
    int limit = 30,
    int offset = 0,
    String search = "",
    String category = "",
    String status = "",
  }) {
    final normalizedLimit = limit.clamp(1, 100).toInt();
    final normalizedOffset = offset < 0 ? 0 : offset;
    final normalizedSearch = search.trim();
    final key = [
      _offlineMode,
      normalizedLimit,
      normalizedOffset,
      normalizedSearch.toLowerCase(),
      category,
      status,
    ].join("|");
    final active = _equipmentRequests[key];
    if (active != null) return active;

    final request = _loadEquipmentPage(
      limit: normalizedLimit,
      offset: normalizedOffset,
      search: normalizedSearch,
      category: category,
      status: status,
    );
    _equipmentRequests[key] = request;
    return request.whenComplete(() => _equipmentRequests.remove(key));
  }

  Future<JsonMap> _loadEquipmentPage({
    required int limit,
    required int offset,
    required String search,
    required String category,
    required String status,
  }) async {
    if (_offlineMode) {
      return {
        ...await localStore.getEquipmentPage(
          _token ?? "",
          limit: limit,
          offset: offset,
          search: search,
          category: category,
          status: status,
        ),
        "offline": true,
      };
    }

    final query = <String, String>{
      "limit": "$limit",
      "offset": "$offset",
      if (search.isNotEmpty) "search": search,
      if (category.isNotEmpty && category.toLowerCase() != "all")
        "category": category,
      if (status.isNotEmpty && status.toLowerCase() != "all") "status": status,
    };
    try {
      final response = await _remoteRequest(
        "GET",
        "equipment",
        queryParameters: query,
      );
      if (_accountId != null) {
        await localStore.cacheRemoteResponse(
          "equipment",
          _accountId!,
          response,
        );
      }
      return {...response, "offline": false};
    } on ApiException catch (error) {
      if (error.statusCode != null && error.statusCode! < 500) rethrow;
      await _switchToOffline();
      return {
        ...await localStore.getEquipmentPage(
          _token ?? "",
          limit: limit,
          offset: offset,
          search: search,
          category: category,
          status: status,
        ),
        "offline": true,
      };
    }
  }

  Future<JsonMap> getEquipmentDetails(String equipmentCode) {
    final key = "$_offlineMode|$equipmentCode";
    final active = _equipmentDetailRequests[key];
    if (active != null) return active;
    final request = _loadEquipmentDetails(equipmentCode);
    _equipmentDetailRequests[key] = request;
    return request.whenComplete(() => _equipmentDetailRequests.remove(key));
  }

  Future<JsonMap> getStudentAccount(String accountId) async {
    if (_offlineMode) {
      return localStore.getStudentAccount(accountId, _token ?? "");
    }
    try {
      return await _remoteRequest(
        "GET",
        "student_account",
        queryParameters: {"account_id": accountId},
      );
    } on ApiException catch (error) {
      if (error.statusCode != null && error.statusCode! < 500) rethrow;
      await _switchToOffline();
      return localStore.getStudentAccount(accountId, _token ?? "");
    }
  }

  Future<JsonMap?> getPendingProfileConflict() async {
    if (_offlineMode) return null;
    final accountId = _accountId;
    if (accountId == null) return null;
    final operations = await localStore.pendingOperations(accountId);
    for (final operation in operations) {
      if (operation["action"] != "update_profile") continue;
      final decoded = jsonDecode(operation["payload"] as String);
      if (decoded is! Map<String, dynamic>) {
        throw const ApiException("The queued profile edit is invalid.");
      }
      final targetAccountId =
          decoded["target_account_id"] as String? ?? accountId;
      final latest = targetAccountId == accountId
          ? _asMap((await _remoteRequest("GET", "me"))["user"])
          : _asMap(
              (await _remoteRequest(
                "GET",
                "student_account",
                queryParameters: {"account_id": targetAccountId},
              ))["profile"],
            );
      return {
        "operation_id": operation["operation_id"],
        "payload": decoded,
        "profile": latest,
      };
    }
    return null;
  }

  Future<void> resolvePendingProfileConflict({
    required String operationId,
    required JsonMap payload,
    required JsonMap latestProfile,
    required bool keepLocalChanges,
  }) async {
    final accountId = _accountId;
    final token = _serverToken;
    if (accountId == null || token == null || _offlineMode) {
      throw const ApiException(
        "Connect and sign in to MySQL before resolving this profile conflict.",
        statusCode: 503,
      );
    }
    if (!keepLocalChanges) {
      await localStore.cacheSyncedProfile(latestProfile, removePhoto: true);
      await localStore.removePendingOperation(operationId);
    } else {
      final rebased = {
        ...payload,
        "expected_version": latestProfile["profile_version"],
      };
      await localStore.replacePendingOperationPayload(operationId, rebased);
      try {
        final result = await _remoteRequest(
          "POST",
          "update_profile",
          body: rebased,
          idempotencyKey: operationId,
        );
        final photoBytes = _photoBytes(rebased["profile_photo_base64"]);
        final updatedUser = _asMap(result["user"]);
        if (photoBytes != null) {
          updatedUser["profile_photo_data"] = photoBytes;
        }
        await localStore.cacheSyncedProfile(
          updatedUser,
          photoBytes: photoBytes,
          removePhoto: rebased["remove_profile_photo"] == true,
        );
        await localStore.removePendingOperation(operationId);
      } on ApiException {
        rethrow;
      }
    }
    await _replayOutbox();
  }

  Future<JsonMap> _loadEquipmentDetails(String equipmentCode) async {
    if (_offlineMode) {
      return localStore.getEquipmentDetails(_token ?? "", equipmentCode);
    }
    try {
      return await _remoteRequest(
        "GET",
        "equipment_detail",
        queryParameters: {"equipment_code": equipmentCode},
      );
    } on ApiException catch (error) {
      if (error.statusCode != null && error.statusCode! < 500) rethrow;
      await _switchToOffline();
      return localStore.getEquipmentDetails(_token ?? "", equipmentCode);
    }
  }

  Future<JsonMap> post(String action, JsonMap body) async {
    if (action == "return_photo") {
      if (_offlineMode) return localStore.post(action, body, _token ?? "");
      return _remoteRequest("POST", action, body: body);
    }
    if (action == "change_password") {
      if (_offlineMode) {
        if (kIsWeb) return localStore.post(action, body, _token ?? "");
        throw const ApiException(
          "Internet connection required to change your password.",
          statusCode: 503,
        );
      }
      return _remoteRequest("POST", action, body: body);
    }
    const supported = {
      "update_profile",
      "create_request",
      "review_request",
      "create_return",
      "review_return",
      "create_payment",
      "review_payment",
      "mark_missing",
      "resolve_exception",
      "adjust_stock",
      "remove_equipment",
    };
    if (!supported.contains(action) && _offlineMode) {
      throw ApiException(
        "The $action action requires a connection to MySQL.",
        statusCode: 503,
      );
    }
    final operationId = _newOperationId();
    final operationBody = Map<String, dynamic>.from(body);
    if (action == "create_request") {
      operationBody["request_code"] = "REQ-${operationId.substring(0, 24)}";
    } else if (action == "create_payment") {
      operationBody["payment_code"] = "PAY-${operationId.substring(0, 24)}";
    }
    if (_offlineMode) {
      final result = await localStore.post(action, operationBody, _token ?? "");
      await _queueLocalAction(action, operationBody, result, operationId);
      return {...result, "sync_pending": true};
    }
    try {
      final result = await _remoteRequest(
        "POST",
        action,
        body: operationBody,
        idempotencyKey: operationId,
      );
      if (action == "update_profile") {
        final photoBytes = _photoBytes(operationBody["profile_photo_base64"]);
        final updatedUser = _asMap(result["user"]);
        if (photoBytes != null) {
          updatedUser["profile_photo_data"] = photoBytes;
        } else if (operationBody["remove_profile_photo"] == true) {
          updatedUser["profile_photo_data"] = null;
        }
        result["user"] = updatedUser;
        await localStore.cacheSyncedProfile(
          updatedUser,
          photoBytes: photoBytes,
          removePhoto: operationBody["remove_profile_photo"] == true,
        );
      }
      return result;
    } on ApiException catch (error) {
      if (error.statusCode != null && error.statusCode! < 500) rethrow;
      if (!supported.contains(action)) rethrow;
      await _switchToOffline();
      final result = await localStore.post(action, operationBody, _token ?? "");
      await _queueLocalAction(action, operationBody, result, operationId);
      return {...result, "sync_pending": true};
    }
  }

  Future<void> _queueLocalAction(
    String action,
    JsonMap body,
    JsonMap result,
    String operationId,
  ) async {
    await localStore.queuePendingOperation(
      operationId: operationId,
      accountId: _accountId ?? "",
      action: action,
      body: body,
      token: _token ?? "",
      result: result,
    );
  }

  Future<void> reconnectAndSync({
    required String role,
    required String accountId,
    required String password,
  }) async {
    if (kIsWeb) {
      throw const ApiException(
        "The public Web Demo uses browser storage and never connects to MySQL.",
        statusCode: 503,
      );
    }
    final response = await _remoteRequest(
      "POST",
      "login",
      body: {"role": role, "account_id": accountId, "password": password},
    );
    final remoteUser = _asMap(response["user"]);
    if (remoteUser["account_id"] != (_accountId ?? accountId)) {
      throw const ApiException(
        "Sign in with the same account used for offline work before syncing.",
        statusCode: 403,
      );
    }
    final token = response["token"];
    if (token is! String || token.isEmpty) {
      throw const ApiException(
        "The server returned an invalid sign-in response.",
      );
    }
    _accountId = accountId;
    _serverToken = token;
    _token = token;
    _offlineMode = false;
    await _preferences.setString(_accountIdKey, accountId);
    await _preferences.setBool(_offlineKey, false);
    await _secureStorage.write(key: _serverTokenKey, value: token);
    await _secureStorage.write(key: _tokenKey, value: token);
    await _replayOutbox();
    final current = _asMap((await _remoteRequest("GET", "me"))["user"]);
    final localUserId = await localStore.cacheUser(current, password);
    await _preferences.setInt(_offlineUserKey, localUserId);
  }

  Future<void> _replayOutbox() async {
    final accountId = _accountId;
    final token = _serverToken;
    if (accountId == null || token == null) {
      throw const ApiException(
        "Sign in online to the same account to synchronize offline changes.",
        statusCode: 401,
      );
    }
    for (final operation in await localStore.pendingOperations(accountId)) {
      final operationId = operation["operation_id"] as String;
      final action = operation["action"] as String;
      final payload = jsonDecode(operation["payload"] as String);
      if (payload is! Map<String, dynamic>) {
        throw const ApiException("A queued offline operation is invalid.");
      }
      try {
        final result = await _remoteRequest(
          "POST",
          action,
          body: payload,
          idempotencyKey: operationId,
        );
        if (action == "update_profile") {
          await localStore.cacheSyncedProfile(
            _asMap(result["user"]),
            photoBytes: _photoBytes(payload["profile_photo_base64"]),
            removePhoto: payload["remove_profile_photo"] == true,
          );
        }
        await localStore.removePendingOperation(operationId);
      } on ApiException catch (error) {
        throw ApiException(
          "Sync stopped at $action. The operation is still saved on this device. ${error.message}",
          statusCode: error.statusCode,
        );
      }
    }
  }

  static String _newOperationId() {
    final random = Random.secure();
    return List.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }

  static Uint8List? _photoBytes(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    try {
      return Uint8List.fromList(base64Decode(value));
    } on FormatException {
      throw const ApiException("The queued profile photo is invalid.");
    }
  }

  Future<JsonMap> _remoteRequest(
    String method,
    String action, {
    JsonMap? body,
    String? idempotencyKey,
    Map<String, String>? queryParameters,
  }) async {
    final endpointUri = Uri.parse(defaultEndpoint);
    final uri = endpointUri.replace(
      queryParameters: {"action": action, ...?queryParameters},
    );
    final headers = <String, String>{"Accept": "application/json"};
    if (_token != null) headers["Authorization"] = "Bearer $_token";
    if (body != null) headers["Content-Type"] = "application/json";

    if (idempotencyKey != null) headers["Idempotency-Key"] = idempotencyKey;

    late http.Response response;
    try {
      switch (method) {
        case "GET":
          response = await _client
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 20));
        case "POST":
          response = await _client
              .post(uri, headers: headers, body: jsonEncode(body))
              .timeout(const Duration(seconds: 20));
        default:
          throw const ApiException("Unsupported API request.");
      }
    } on http.ClientException {
      throw const ApiException(
        "The server connection failed. Check your network and server URL.",
      );
    } on TimeoutException {
      throw const ApiException(
        "The Stokli server did not respond in time. Try again.",
      );
    } on FormatException {
      throw const ApiException("The configured server URL is invalid.");
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw ApiException(
        "The server returned an invalid response (${response.statusCode}).",
        statusCode: response.statusCode,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw ApiException(
        "The server returned an unexpected response (${response.statusCode}).",
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded["error"];
      throw ApiException(
        error is String ? error : "Request failed (${response.statusCode}).",
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  Future<void> _switchToOffline() async {
    final userId = _preferences.getInt(_offlineUserKey);
    if (userId == null) {
      throw const ApiException(
        "The server is unavailable and no offline account is cached. Connect to XAMPP once to cache your account.",
      );
    }
    if (_token != null && !_token!.startsWith("offline:")) {
      _serverToken = _token;
      await _secureStorage.write(key: _serverTokenKey, value: _serverToken);
    }
    _offlineMode = true;
    _token = "offline:$userId";
    await _preferences.setBool(_offlineKey, true);
    await _secureStorage.write(key: _tokenKey, value: _token);
  }

  static JsonMap _asMap(dynamic value) =>
      value is Map<String, dynamic> ? value : <String, dynamic>{};

  Future<void> dispose() async {
    _client.close();
    await localStore.close();
  }
}
