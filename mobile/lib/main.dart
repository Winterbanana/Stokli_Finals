import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:image_picker/image_picker.dart";
import "package:mobile_scanner/mobile_scanner.dart";
import "package:pdf/pdf.dart";
import "package:pdf/widgets.dart" as pw;
import "package:printing/printing.dart";
import "package:shared_preferences/shared_preferences.dart";

import "api_exception.dart";
import "api_client.dart";
import "help_support.dart";

const _navy = Color(0xFF123B57);
const _blue = Color(0xFF2599BE);
const _background = Color(0xFFF2F5F9);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = await ApiClient.create();
  runApp(StokliApp(api: api));
}

class StokliApp extends StatefulWidget {
  const StokliApp({super.key, required this.api});

  final ApiClient api;

  @override
  State<StokliApp> createState() => _StokliAppState();
}

class _StokliAppState extends State<StokliApp> {
  JsonMap? _user;
  bool _restoring = true;
  String? _restoreError;
  ThemeMode _themeMode = ThemeMode.system;

  String _themePreferenceKey(JsonMap user) =>
      "stokli_theme_${Uri.encodeComponent(user["account_id"]?.toString() ?? "")}";

  ThemeMode _parseThemeMode(String? value) => switch (value) {
    "light" => ThemeMode.light,
    "dark" => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  Future<void> _loadThemeForUser(JsonMap user) async {
    final preferences = await SharedPreferences.getInstance();
    _themeMode = _parseThemeMode(
      preferences.getString(_themePreferenceKey(user)),
    );
  }

  Future<void> _changeTheme(ThemeMode mode) async {
    final user = _user;
    if (user == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_themePreferenceKey(user), mode.name);
    if (mounted) setState(() => _themeMode = mode);
  }

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    if (widget.api.hasToken) {
      try {
        _user = await widget.api.me();
        await _loadThemeForUser(_user!);
      } on ApiException catch (error) {
        _restoreError = error.message;
      }
    }
    if (mounted) setState(() => _restoring = false);
  }

  Future<void> _signedIn(JsonMap user) async {
    await _loadThemeForUser(user);
    if (!mounted) return;
    setState(() {
      _restoreError = null;
      _user = user;
    });
  }

  Future<void> _signOut() async {
    try {
      await widget.api.logout();
    } on ApiException catch (error) {
      if (mounted) _showMessage(context, error.message);
    }
    if (mounted) {
      setState(() {
        _user = null;
        _themeMode = ThemeMode.system;
      });
    }
  }

  ThemeData _buildTheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: _blue,
      brightness: brightness,
      primary: _blue,
      surface: dark ? const Color(0xFF17232D) : Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? const Color(0xFF101820) : _background,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF202E39) : const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      textTheme: ThemeData(brightness: brightness).textTheme
          .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Stokli",
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _themeMode,
      home: _restoring
          ? const _LoadingScreen()
          : _user == null
          ? LoginScreen(
              api: widget.api,
              initialError: _restoreError,
              onSignedIn: _signedIn,
            )
          : HomeShell(
              api: widget.api,
              user: _user!,
              onSignOut: _signOut,
              themeMode: _themeMode,
              onThemeChanged: _changeTheme,
            ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.api,
    required this.onSignedIn,
    this.initialError,
  });

  final ApiClient api;
  final Future<void> Function(JsonMap user) onSignedIn;
  final String? initialError;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _id = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String _role = "student";
  bool _registering = false;
  bool _working = false;
  bool _showPassword = false;
  String? _message;
  bool _isError = true;

  @override
  void initState() {
    super.initState();
    _message = widget.initialError;
  }

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      if (_registering) {
        await widget.api.register(
          accountId: _id.text.trim(),
          fullName: _name.text.trim(),
          password: _password.text,
        );
        if (!mounted) return;
        setState(() {
          _registering = false;
          _password.clear();
          _confirm.clear();
          _message = "Account created. Sign in with your new credentials.";
          _isError = false;
        });
      } else {
        final user = await widget.api.login(
          role: _role,
          accountId: _id.text.trim(),
          password: _password.text,
        );
        await widget.onSignedIn(user);
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.message;
          _isError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _BrandHeader(),
                  const SizedBox(height: 26),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _registering
                                  ? "Create student account"
                                  : "Sign in to your account",
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _registering
                                  ? "Register with your student ID."
                                  : "Choose your account type to continue.",
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 20),
                            if (!_registering) ...[
                              SegmentedButton<String>(
                                segments: const [
                                  ButtonSegment(
                                    value: "student",
                                    label: Text("Student"),
                                    icon: Icon(Icons.school_outlined),
                                  ),
                                  ButtonSegment(
                                    value: "admin",
                                    label: Text("Admin"),
                                    icon: Icon(
                                      Icons.admin_panel_settings_outlined,
                                    ),
                                  ),
                                ],
                                selected: {_role},
                                onSelectionChanged: (value) =>
                                    setState(() => _role = value.first),
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (_registering) ...[
                              TextFormField(
                                controller: _name,
                                textCapitalization: TextCapitalization.words,
                                decoration: const InputDecoration(
                                  labelText: "Full name",
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                    ? "Enter your full name."
                                    : null,
                              ),
                              const SizedBox(height: 13),
                            ],
                            TextFormField(
                              controller: _id,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: _registering || _role == "student"
                                    ? "Student ID"
                                    : "Admin ID",
                                prefixIcon: const Icon(Icons.badge_outlined),
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? "Enter your account ID."
                                  : null,
                            ),
                            const SizedBox(height: 13),
                            TextFormField(
                              controller: _password,
                              obscureText: !_showPassword,
                              textInputAction: _registering
                                  ? TextInputAction.next
                                  : TextInputAction.done,
                              onFieldSubmitted: (_) =>
                                  _registering ? null : _submit(),
                              decoration: InputDecoration(
                                labelText: _registering
                                    ? "New password"
                                    : "Password",
                                prefixIcon: const Icon(Icons.key_outlined),
                                suffixIcon: IconButton(
                                  onPressed: () => setState(
                                    () => _showPassword = !_showPassword,
                                  ),
                                  icon: Icon(
                                    _showPassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return "Enter your password.";
                                }
                                if (_registering &&
                                    !_strongPassword.hasMatch(value)) {
                                  return "Use 8+ characters with upper, lower, number, and symbol.";
                                }
                                return null;
                              },
                            ),
                            if (_registering) ...[
                              const SizedBox(height: 13),
                              TextFormField(
                                controller: _confirm,
                                obscureText: !_showPassword,
                                decoration: const InputDecoration(
                                  labelText: "Confirm password",
                                  prefixIcon: Icon(Icons.lock_outline),
                                ),
                                validator: (value) => value != _password.text
                                    ? "Passwords do not match."
                                    : null,
                              ),
                            ],
                            const SizedBox(height: 16),
                            if (_message != null) ...[
                              const SizedBox(height: 4),
                              _MessageBanner(
                                message: _message!,
                                isError: _isError,
                              ),
                            ],
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _working ? null : _submit,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                                child: _working
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        _registering
                                            ? "Create account"
                                            : "Sign in",
                                      ),
                              ),
                            ),
                            if (_role == "student" || _registering)
                              TextButton(
                                onPressed: _working
                                    ? null
                                    : () => setState(() {
                                        _registering = !_registering;
                                        _message = null;
                                      }),
                                child: Text(
                                  _registering
                                      ? "Already registered? Sign in"
                                      : "Create a student account",
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final _strongPassword = RegExp(
  r"^(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[^A-Za-z0-9]).{8,}$",
);

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.api,
    required this.user,
    required this.onSignOut,
    required this.themeMode,
    required this.onThemeChanged,
  });

  final ApiClient api;
  final JsonMap user;
  final Future<void> Function() onSignOut;
  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode mode) onThemeChanged;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final bool _admin = widget.user["role"] == "admin";
  int _tab = 0;
  bool _loading = true;
  int _pendingSyncCount = 0;
  String? _error;
  String _requestFilter = "All";
  List<JsonMap> _equipment = [];
  List<JsonMap> _requests = [];
  List<JsonMap> _borrowings = [];
  List<JsonMap> _returns = [];
  List<JsonMap> _penalties = [];
  List<JsonMap> _payments = [];
  List<JsonMap> _exceptions = [];
  List<JsonMap> _users = [];
  List<JsonMap> _logs = [];
  JsonMap _stats = {};
  JsonMap _reports = {};
  int _equipmentTotal = 0;
  bool _equipmentHasMore = true;
  List<String> _equipmentCategories = [];
  Future<void>? _refreshTask;
  bool _savingProfile = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  List<JsonMap> _list(JsonMap response, String key) {
    final value = response[key];
    if (value is! List) return [];
    return value.whereType<Map<String, dynamic>>().toList();
  }

  Future<void> _refresh() {
    final active = _refreshTask;
    if (active != null) return active;
    final task = _performRefresh();
    _refreshTask = task;
    return task.whenComplete(() => _refreshTask = null);
  }

  Future<void> _performRefresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cachedEquipment = await widget.api.getCachedEquipmentPage();
      if (mounted && _equipment.isEmpty) {
        setState(() {
          _equipment = _list(cachedEquipment, "items");
          _equipmentTotal = _integer(cachedEquipment["total_count"]);
          _equipmentHasMore = cachedEquipment["has_more"] == true;
          _equipmentCategories = _stringList(cachedEquipment["categories"]);
        });
      }
      if (_admin) {
        final results = await Future.wait([
          widget.api.getEquipmentPage(),
          widget.api.get("requests"),
          widget.api.get("borrowings"),
          widget.api.get("returns"),
          widget.api.get("payments"),
          widget.api.get("exceptions"),
          widget.api.get("admin_stats"),
          widget.api.get("admin_users"),
          widget.api.get("admin_logs"),
          widget.api.get("report_summary"),
        ]);
        if (!mounted) return;
        setState(() {
          _equipment = _list(results[0], "items");
          _equipmentTotal = _integer(results[0]["total_count"]);
          _equipmentHasMore = results[0]["has_more"] == true;
          _equipmentCategories = _stringList(results[0]["categories"]);
          _requests = _list(results[1], "requests");
          _borrowings = _list(results[2], "borrowings");
          _returns = _list(results[3], "returns");
          _payments = _list(results[4], "payments");
          _exceptions = _list(results[5], "exceptions");
          _stats = _map(results[6]["stats"]);
          _users = _list(results[7], "users");
          _logs = _list(results[8], "logs");
          _reports = _map(results[9]["summary"]);
        });
      } else {
        final results = await Future.wait([
          widget.api.getEquipmentPage(),
          widget.api.get("requests"),
          widget.api.get("borrowings"),
          widget.api.get("returns"),
          widget.api.get("penalties"),
          widget.api.get("payments"),
        ]);
        if (!mounted) return;
        setState(() {
          _equipment = _list(results[0], "items");
          _equipmentTotal = _integer(results[0]["total_count"]);
          _equipmentHasMore = results[0]["has_more"] == true;
          _equipmentCategories = _stringList(results[0]["categories"]);
          _requests = _list(results[1], "requests");
          _borrowings = _list(results[2], "borrowings");
          _returns = _list(results[3], "returns");
          _penalties = _list(results[4], "penalties");
          _payments = _list(results[5], "payments");
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      final pendingCount = await widget.api.pendingSyncCount;
      if (mounted) {
        setState(() {
          _loading = false;
          _pendingSyncCount = pendingCount;
        });
      }
    }
  }

  Future<void> _action(Future<JsonMap> Function() action) async {
    try {
      final result = await action();
      if (!mounted) return;
      final message = result["message"] as String? ?? "Saved.";
      _showMessage(
        context,
        result["sync_pending"] == true
            ? "$message Saved locally and queued for MySQL sync."
            : message,
      );
      await _refresh();
    } on ApiException catch (error) {
      if (mounted) _showMessage(context, error.message);
    }
  }

  Future<void> _syncOfflineChanges() async {
    final password = TextEditingController();
    final enteredPassword = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Connect and sync"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Sign in to MySQL as ${widget.user["account_id"]} to send this device's queued changes.",
            ),
            const SizedBox(height: 14),
            TextField(
              controller: password,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: "Account password"),
              onSubmitted: (_) => Navigator.pop(dialogContext, password.text),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, password.text),
            child: const Text("Sync"),
          ),
        ],
      ),
    );
    password.dispose();
    if (enteredPassword == null || enteredPassword.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.api.reconnectAndSync(
        role: widget.user["role"] as String,
        accountId: widget.user["account_id"] as String,
        password: enteredPassword,
      );
      if (!mounted) return;
      _showMessage(context, "Offline changes synchronized to MySQL.");
      await _refresh();
    } on ApiException catch (error) {
      if (error.statusCode == 409 && mounted) {
        await _resolveQueuedProfileConflict(error);
      } else if (mounted) {
        _showMessage(context, error.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolveQueuedProfileConflict(ApiException syncError) async {
    try {
      final conflict = await widget.api.getPendingProfileConflict();
      if (!mounted) return;
      if (conflict == null) {
        _showMessage(context, syncError.message);
        return;
      }
      final payload = _map(conflict["payload"]);
      final latest = _map(conflict["profile"]);
      final targetAccountId =
          payload["target_account_id"]?.toString() ??
          widget.user["account_id"]?.toString() ??
          "";
      final fields = payload.keys
          .where(
            (key) =>
                !const {"expected_version", "target_account_id"}.contains(key),
          )
          .toList();
      final keepChanges = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Resolve pending profile edit"),
          content: SizedBox(
            width: 460,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  "${latest["full_name"] ?? targetAccountId} has a newer server profile. "
                  "Your queued change was not applied. Compare the latest values before choosing:",
                ),
                const SizedBox(height: 8),
                for (final field in fields)
                  ListTile(
                    dense: true,
                    title: Text(
                      field == "profile_photo_base64"
                          ? "Profile photo"
                          : _humanize(field),
                    ),
                    subtitle: Text(
                      field == "profile_photo_base64"
                          ? "Your saved edit: Replace with selected photo\nCurrent server value: ${latest["profile_photo"] == null ? "No photo" : "Photo on file"}"
                          : field == "remove_profile_photo"
                          ? "Your saved edit: ${payload[field] == true ? "Remove photo" : "Keep photo"}\nCurrent server value: ${latest["profile_photo"] == null ? "No photo" : "Photo on file"}"
                          : "Your saved edit: ${payload[field] ?? "—"}\n"
                                "Current server value: ${latest[field] ?? "—"}",
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Use server profile"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Apply my saved edits"),
            ),
          ],
        ),
      );
      if (keepChanges == null || !mounted) return;
      await widget.api.resolvePendingProfileConflict(
        operationId: conflict["operation_id"] as String,
        payload: payload,
        latestProfile: latest,
        keepLocalChanges: keepChanges,
      );
      if (targetAccountId == widget.user["account_id"]) {
        widget.user.addAll(await widget.api.me());
      } else {
        final index = _users.indexWhere(
          (row) => row["account_id"] == targetAccountId,
        );
        if (index >= 0) {
          final refreshed = _map(
            (await widget.api.getStudentAccount(targetAccountId))["profile"],
          );
          _users[index] = {..._users[index], ...refreshed};
        }
      }
      if (mounted) {
        _showMessage(
          context,
          keepChanges ? "The profile edit was reconciled and synchronized." : "The queued edit was discarded; the server profile is now current.",
        );
        await _refresh();
      }
    } on ApiException catch (error) {
      if (mounted) _showMessage(context, error.message);
    }
  }

  Future<void> _requestItem(JsonMap item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Request ${item["name"]}"),
        content: Text(
          "${item["available_stock"]} available • 8-hour borrowing period\n\n"
          "Your request must be approved by an administrator before pickup.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Submit request"),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _action(
        () => widget.api.post("create_request", {
          "equipment_code": item["equipment_code"],
        }),
      );
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const _QrScannerScreen()));
    if (code == null || !mounted) return;
    final normalized = code.trim().toUpperCase();
    JsonMap? match;
    for (final item in _equipment) {
      if (normalized.contains(
        (item["equipment_code"] as String).toUpperCase(),
      )) {
        match = item;
        break;
      }
    }
    if (match == null) {
      _showMessage(context, "No active Stokli equipment matches that QR code.");
      return;
    }
    await _requestItem(match);
  }

  Future<void> _returnItem(JsonMap borrowing) async {
    String condition = "Good";
    XFile? photo;
    final picker = ImagePicker();
    final shouldSubmit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Report equipment return"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "${borrowing["item_name"]} • ${borrowing["transaction_code"]}",
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: condition,
                decoration: const InputDecoration(labelText: "Item condition"),
                items: const ["Good", "Damaged", "Missing"]
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => condition = value);
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    final source = await showModalBottomSheet<ImageSource>(
                      context: context,
                      builder: (context) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.camera_alt_outlined),
                              title: const Text("Take a photo"),
                              onTap: () =>
                                  Navigator.pop(context, ImageSource.camera),
                            ),
                            ListTile(
                              leading: const Icon(Icons.photo_library_outlined),
                              title: const Text("Choose from gallery"),
                              onTap: () =>
                                  Navigator.pop(context, ImageSource.gallery),
                            ),
                          ],
                        ),
                      ),
                    );
                    if (source == null || !context.mounted) return;
                    final selected = await picker.pickImage(
                      source: source,
                      maxWidth: 1280,
                      imageQuality: 70,
                    );
                    if (selected != null && context.mounted) {
                      setDialogState(() => photo = selected);
                    }
                  } on PlatformException catch (error) {
                    if (!context.mounted) return;
                    _showMessage(
                      context,
                      error.message ?? "Camera access failed.",
                    );
                  }
                },
                icon: Icon(
                  photo == null ? Icons.camera_alt_outlined : Icons.check,
                ),
                label: Text(photo?.name ?? "Add condition photo (optional)"),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text("Send for review"),
            ),
          ],
        ),
      ),
    );
    if (shouldSubmit != true) return;
    String? photoBase64;
    if (photo != null) {
      try {
        photoBase64 = base64Encode(await File(photo!.path).readAsBytes());
      } on FileSystemException catch (error) {
        if (mounted) {
          _showMessage(
            context,
            "Could not read the selected photo: ${error.message}",
          );
        }
        return;
      }
    }
    await _action(
      () => widget.api.post("create_return", {
        "transaction_id": borrowing["id"],
        "request_code": borrowing["request_code"],
        "condition": condition,
        "photo_base64": ?photoBase64,
      }),
    );
  }

  Future<void> _showBorrowingSlip(JsonMap borrowing) async {
    final document = pw.Document();
    final status = borrowing["status"] as String? ?? "active";
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(30),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              "STOKLI",
              style: pw.TextStyle(
                fontSize: 25,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex("#123B57"),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text("EQUIPMENT BORROWING SLIP"),
            pw.Divider(),
            pw.SizedBox(height: 10),
            _slipLine("Slip / transaction no.", borrowing["transaction_code"]),
            _slipLine("Request no.", borrowing["request_code"]),
            _slipLine("Borrower", borrowing["student_name"]),
            _slipLine("Student ID", borrowing["account_id"]),
            _slipLine("Equipment", borrowing["item_name"]),
            _slipLine("Equipment code", borrowing["equipment_code"]),
            _slipLine("Category", borrowing["category"]),
            _slipLine("Borrowed", _date(borrowing["borrowed_at"])),
            _slipLine("Due", _date(borrowing["due_at"])),
            _slipLine("Current status", status.toUpperCase()),
            pw.SizedBox(height: 18),
            pw.Text(
              "Present this slip to the IT Laboratory staff when collecting or returning the item.",
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.Spacer(),
            pw.Divider(),
            pw.Text(
              "Generated from Stokli • ${DateTime.now().toLocal()}",
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
      ),
    );
    await Printing.layoutPdf(
      name: "stokli-${borrowing["transaction_code"] ?? "borrowing-slip"}.pdf",
      onLayout: (_) async => document.save(),
    );
  }

  pw.Widget _slipLine(String label, dynamic value) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 5),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 115,
          child: pw.Text(
            label,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Expanded(child: pw.Text(value?.toString() ?? "—")),
      ],
    ),
  );

  Widget _slipButton(JsonMap borrowing) => OutlinedButton.icon(
    onPressed: () => _showBorrowingSlip(borrowing),
    icon: const Icon(Icons.receipt_long_outlined, size: 18),
    label: const Text("Borrowing slip"),
  );

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final values = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Change password"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: current,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Current password"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: next,
              obscureText: true,
              decoration: const InputDecoration(labelText: "New password"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Confirm password"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () {
              if (!_strongPassword.hasMatch(next.text)) {
                _showMessage(
                  context,
                  "Use 8+ characters with uppercase, lowercase, a number, and a symbol.",
                );
                return;
              }
              if (next.text != confirm.text) {
                _showMessage(context, "Passwords do not match.");
                return;
              }
              Navigator.pop(context, [current.text, next.text]);
            },
            child: const Text("Update"),
          ),
        ],
      ),
    );
    current.dispose();
    next.dispose();
    confirm.dispose();
    if (values == null) return;
    await _action(
      () => widget.api.post("change_password", {
        "current_password": values[0],
        "new_password": values[1],
      }),
    );
  }

  Future<void> _openHelp() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => HelpSupportPage(isAdmin: _admin)),
    );
  }

  Future<void> _editProfile({JsonMap? account}) async {
    final target = account ?? widget.user;
    final targetAccountId = target["account_id"]?.toString() ?? "";
    final isSelf = targetAccountId == widget.user["account_id"];
    if (!isSelf && (!_admin || target["role"] != "student")) {
      _showMessage(context, "You are not authorized to edit this account.");
      return;
    }
    final name = TextEditingController(
      text: target["full_name"]?.toString() ?? "",
    );
    final email = TextEditingController(
      text: target["email"]?.toString() ?? "",
    );
    final contact = TextEditingController(
      text: target["contact_number"]?.toString() ?? "",
    );
    final programSection = TextEditingController(
      text: target["program_section"]?.toString() ?? "",
    );
    XFile? selectedPhoto;
    String status = target["account_status"]?.toString() ?? "active";
    bool removePhoto = false;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(isSelf ? "Edit profile" : "Edit Student account"),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: selectedPhoto == null
                          ? _AccountAvatar(
                              api: widget.api,
                              user: target,
                              radius: 44,
                            )
                          : ClipOval(
                              child: Image.file(
                                File(selectedPhoto!.path),
                                width: 88,
                                height: 88,
                                fit: BoxFit.cover,
                              ),
                            ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            final source =
                                await showModalBottomSheet<ImageSource>(
                                  context: dialogContext,
                                  builder: (context) => SafeArea(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ListTile(
                                          leading: const Icon(
                                            Icons.photo_library_outlined,
                                          ),
                                          title: const Text(
                                            "Choose from gallery",
                                          ),
                                          onTap: () => Navigator.pop(
                                            context,
                                            ImageSource.gallery,
                                          ),
                                        ),
                                        ListTile(
                                          leading: const Icon(
                                            Icons.camera_alt_outlined,
                                          ),
                                          title: const Text("Take a photo"),
                                          onTap: () => Navigator.pop(
                                            context,
                                            ImageSource.camera,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                            if (source == null || !dialogContext.mounted) {
                              return;
                            }
                            try {
                              final image = await ImagePicker().pickImage(
                                source: source,
                                maxWidth: 700,
                                maxHeight: 700,
                                imageQuality: 78,
                              );
                              if (image != null && dialogContext.mounted) {
                                setDialogState(() {
                                  selectedPhoto = image;
                                  removePhoto = false;
                                });
                              }
                            } on PlatformException catch (error) {
                              if (dialogContext.mounted) {
                                _showMessage(
                                  dialogContext,
                                  error.message ??
                                      "Photo access was not granted.",
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.add_a_photo_outlined),
                          label: const Text("Choose photo"),
                        ),
                        if (target["profile_photo"] != null ||
                            target["profile_photo_data"] != null)
                          TextButton.icon(
                            onPressed: () => setDialogState(() {
                              selectedPhoto = null;
                              removePhoto = true;
                            }),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text("Remove"),
                          ),
                      ],
                    ),
                    const Text(
                      "JPG, PNG, or WEBP • maximum 1.5 MB",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: name,
                      maxLength: 120,
                      decoration: const InputDecoration(labelText: "Full name"),
                    ),
                    TextField(
                      controller: email,
                      maxLength: 254,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: "Email (optional)",
                      ),
                    ),
                    TextField(
                      controller: contact,
                      maxLength: 32,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: "Contact number",
                      ),
                    ),
                    TextField(
                      controller: programSection,
                      maxLength: 80,
                      decoration: InputDecoration(
                        labelText: _admin && !isSelf
                            ? "Course / year / section"
                            : "Program / section",
                      ),
                    ),
                    if (_admin && !isSelf)
                      DropdownButtonFormField<String>(
                        initialValue: status,
                        decoration: const InputDecoration(
                          labelText: "Student account status",
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: "active",
                            child: Text("Active"),
                          ),
                          DropdownMenuItem(
                            value: "suspended",
                            child: Text("Suspended"),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => status = value);
                          }
                        },
                      ),
                    if (!isSelf)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          "Student ID and account role are protected and cannot be changed here.",
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text("Cancel"),
              ),
              FilledButton(
                onPressed: () {
                  if (name.text.trim().isEmpty) {
                    _showMessage(dialogContext, "Full name cannot be empty.");
                    return;
                  }
                  if (email.text.trim().isNotEmpty &&
                      !RegExp(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
                          .hasMatch(email.text.trim())) {
                    _showMessage(dialogContext, "Enter a valid email address.");
                    return;
                  }
                  Navigator.pop(dialogContext, true);
                },
                child: const Text("Save profile"),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
      if (_savingProfile) return;

      final body = <String, dynamic>{
        "expected_version": _integer(target["profile_version"])
            .clamp(1, 1 << 30),
        if (!isSelf) "target_account_id": targetAccountId,
        if (name.text.trim() != target["full_name"])
          "full_name": name.text.trim(),
        if (email.text.trim() != (target["email"]?.toString() ?? ""))
          "email": email.text.trim(),
        if (contact.text.trim() != (target["contact_number"]?.toString() ?? ""))
          "contact_number": contact.text.trim(),
        if (programSection.text.trim() !=
            (target["program_section"]?.toString() ?? ""))
          "program_section": programSection.text.trim(),
        if (_admin &&
            !isSelf &&
            status != (target["account_status"]?.toString() ?? "active"))
          "account_status": status,
        if (removePhoto) "remove_profile_photo": true,
      };
      if (selectedPhoto != null) {
        final photoBytes = await selectedPhoto!.readAsBytes();
        if (!mounted) return;
        if (photoBytes.length > 1_572_864 || !_isProfileImage(photoBytes)) {
          _showMessage(
            context,
            "Choose a valid JPG, PNG, or WEBP photo under 1.5 MB.",
          );
          return;
        }
        body["profile_photo_base64"] = base64Encode(photoBytes);
      }
      if (body.length <= (isSelf ? 1 : 2)) {
        _showMessage(context, "No profile changes to save.");
        return;
      }

      setState(() => _savingProfile = true);
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Expanded(child: Text("Saving profile…")),
              ],
            ),
          ),
        ),
      );
      try {
        final result = await widget.api.post("update_profile", body);
        final updatedUser = _map(result["user"]);
        if (mounted && updatedUser.isNotEmpty) {
          setState(() {
            if (isSelf) {
              widget.user.addAll(updatedUser);
            } else {
              final index = _users.indexWhere(
                (row) => row["account_id"] == targetAccountId,
              );
              if (index >= 0) {
                _users[index] = {..._users[index], ...updatedUser};
              }
            }
          });
        }
        if (mounted) {
          final message = result["sync_pending"] == true
              ? "Profile saved on this device and queued for MySQL sync."
              : "Profile updated.";
          _showMessage(context, message);
          await _refresh();
        }
      } on ApiException catch (error) {
        if (error.statusCode == 409 && mounted) {
          await _resolveDirectProfileConflict(
            body: body,
            accountId: targetAccountId,
            isSelf: isSelf,
          );
        } else if (mounted) {
          _showMessage(context, error.message);
        }
      } on FileSystemException catch (error) {
        if (mounted) {
          _showMessage(context, "Could not read photo: ${error.message}");
        }
      } finally {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          setState(() => _savingProfile = false);
        }
      }
    } finally {
      name.dispose();
      email.dispose();
      contact.dispose();
      programSection.dispose();
    }
  }

  Future<void> _resolveDirectProfileConflict({
    required JsonMap body,
    required String accountId,
    required bool isSelf,
  }) async {
    try {
      final latest = isSelf
          ? await widget.api.me()
          : _map((await widget.api.getStudentAccount(accountId))["profile"]);
      if (!mounted) return;
      final keepEdits = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Profile changed on another device"),
          content: Text(
            "The server now has a newer version for ${latest["full_name"] ?? accountId} "
            "(${latest["account_id"] ?? accountId}). "
            "Latest program/section: ${latest["program_section"] ?? "—"}; "
            "latest contact: ${latest["contact_number"] ?? "—"}. "
            "Your edit has not been applied. You can explicitly apply only the fields you changed to this newer version.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Discard my edits"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Apply my edits"),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (keepEdits != true) {
        if (isSelf) {
          widget.user.addAll(latest);
        } else {
          final index = _users.indexWhere(
            (row) => row["account_id"] == accountId,
          );
          if (index >= 0) _users[index] = {..._users[index], ...latest};
        }
        setState(() {});
        _showMessage(context, "Your profile was not changed.");
        await _refresh();
        return;
      }
      final rebased = {...body, "expected_version": latest["profile_version"]};
      final result = await widget.api.post("update_profile", rebased);
      final updated = _map(result["user"]);
      if (isSelf) {
        widget.user.addAll(updated);
      } else {
        final index = _users.indexWhere(
          (row) => row["account_id"] == accountId,
        );
        if (index >= 0) _users[index] = {..._users[index], ...updated};
      }
      if (mounted) {
        _showMessage(context, "Your edits were applied to the latest profile.");
        await _refresh();
      }
    } on ApiException catch (error) {
      if (mounted) _showMessage(context, error.message);
    }
  }

  Future<void> _payPenalty() async {
    final balance = _penalties
        .where((row) => row["status"] == "unpaid")
        .fold<double>(
          0,
          (sum, row) =>
              sum + _number(row["amount"]) - _number(row["amount_paid"]),
        );
    if (balance <= 0) {
      _showMessage(context, "There is no outstanding balance.");
      return;
    }
    final reserved = _payments
        .where((row) => row["status"] == "pending")
        .fold<double>(0, (sum, row) => sum + _number(row["amount"]));
    final available = (balance - reserved).clamp(0, balance).toDouble();
    if (available <= 0) {
      _showMessage(
        context,
        "Your available balance is already covered by a payment awaiting staff verification.",
      );
      return;
    }
    String method = "GCash";
    final reference = TextEditingController();
    final amount = TextEditingController(text: available.toStringAsFixed(2));
    final formKey = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Submit a payment record"),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Outstanding: ${_peso(balance)}"),
                  if (reserved > 0) ...[
                    const SizedBox(height: 5),
                    Text(
                      "${_peso(reserved)} awaiting staff verification",
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  Text(
                    "Available to submit: ${_peso(available)}",
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r"^\d*\.?\d{0,2}"),
                      ),
                    ],
                    decoration: const InputDecoration(
                      labelText: "Payment amount",
                      prefixText: "₱ ",
                    ),
                    validator: (value) {
                      final parsed = double.tryParse(value ?? "");
                      if (parsed == null || parsed <= 0) {
                        return "Enter a valid payment amount.";
                      }
                      if (parsed > available + 0.001) {
                        return "Amount exceeds ${_peso(available)} available.";
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: method,
                    decoration: const InputDecoration(
                      labelText: "Payment method",
                    ),
                    items: const ["GCash", "Maya", "Cash"]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setDialogState(() => method = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reference,
                    decoration: const InputDecoration(
                      labelText: "Receipt/reference (optional)",
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "This creates a payment record for staff verification; the app does not charge a wallet.",
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text("Submit record"),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await _action(
        () => widget.api.post("create_payment", {
          "amount": double.parse(amount.text).toStringAsFixed(2),
          "method": method,
          "reference_note": reference.text.trim(),
        }),
      );
    }
    reference.dispose();
    amount.dispose();
  }

  Future<void> _adminAction(
    String action, {
    required String idKey,
    required dynamic id,
    required String decision,
    String? referenceKey,
    dynamic reference,
  }) => _action(
    () => widget.api.post(action, {
      idKey: id,
      ?referenceKey: reference,
      "decision": decision,
    }),
  );

  Future<void> _viewReturnPhoto(dynamic reportId) async {
    try {
      final response = await widget.api.post("return_photo", {
        "report_id": reportId,
      });
      if (!mounted) return;
      final encoded = response["photo_base64"];
      if (encoded is! String) {
        throw const ApiException("The server returned an invalid photo.");
      }
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Image.memory(
              base64Decode(encoded),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Padding(
                padding: EdgeInsets.all(24),
                child: Text("The return photo could not be displayed."),
              ),
            ),
          ),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) _showMessage(context, error.message);
    } on FormatException {
      if (mounted) _showMessage(context, "The return photo data is invalid.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = _admin
        ? const [
            "Overview",
            "Inventory",
            "Requests",
            "Returns",
            "Payments",
            "Exceptions",
            "Accounts",
            "Reports",
            "Activity",
            "Settings",
          ]
        : const [
            "Home",
            "Inventory",
            "Requests",
            "Returns",
            "Profile",
            "Settings",
          ];
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                "assets/stokli/stokli-logo.jpg",
                width: 36,
                height: 36,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            Text("STOKLI  ·  ${titles[_tab]}"),
          ],
        ),
        actions: [
          IconButton(
            tooltip: "Refresh",
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == "password") _changePassword();
              if (value == "logout") widget.onSignOut();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: "password",
                child: ListTile(
                  leading: Icon(Icons.key_outlined),
                  title: Text("Change password"),
                ),
              ),
              PopupMenuItem(
                value: "logout",
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text("Sign out"),
                ),
              ),
            ],
          ),
        ],
      ),
      body: _error != null && _equipment.isEmpty
          ? _ErrorState(message: _error!, retry: _refresh)
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  if (_error != null) ...[
                    _MessageBanner(message: _error!, isError: true),
                    const SizedBox(height: 10),
                  ],
                  if (_loading && _equipment.isEmpty)
                    const LinearProgressIndicator(),
                  if (_admin) ...[
                    _adminNavigation(),
                    const SizedBox(height: 14),
                  ],
                  if (widget.api.isOffline || _pendingSyncCount > 0) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const Icon(Icons.cloud_off_outlined, color: _blue),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                widget.api.isOffline
                                    ? "$_pendingSyncCount changes waiting to sync. Saved on this device."
                                    : "$_pendingSyncCount changes still need MySQL sync.",
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: _syncOfflineChanges,
                              child: const Text("Sync"),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (_admin) _adminPage() else _studentPage(),
                ],
              ),
            ),
      bottomNavigationBar: _admin
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (index) => setState(() => _tab = index),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: "Home",
                ),
                NavigationDestination(
                  icon: Icon(Icons.inventory_2_outlined),
                  label: "Inventory",
                ),
                NavigationDestination(
                  icon: Icon(Icons.assignment_outlined),
                  label: "Requests",
                ),
                NavigationDestination(
                  icon: Icon(Icons.assignment_return_outlined),
                  label: "Returns",
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  label: "Profile",
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  label: "Settings",
                ),
              ],
            ),
    );
  }

  Widget _adminNavigation() {
    const tabs = [
      ("Overview", Icons.dashboard_outlined),
      ("Inventory", Icons.inventory_2_outlined),
      ("Requests", Icons.assignment_outlined),
      ("Returns", Icons.assignment_return_outlined),
      ("Payments", Icons.payments_outlined),
      ("Exceptions", Icons.warning_amber_outlined),
      ("Accounts", Icons.people_outline),
      ("Reports", Icons.assessment_outlined),
      ("Activity", Icons.history),
      ("Settings", Icons.settings_outlined),
    ];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (label, icon) = tabs[index];
          return ChoiceChip(
            avatar: Icon(icon, size: 18),
            label: Text(label),
            selected: _tab == index,
            onSelected: (_) => setState(() => _tab = index),
          );
        },
      ),
    );
  }

  Widget _studentPage() {
    switch (_tab) {
      case 0:
        return _studentHome();
      case 1:
        return _inventory();
      case 2:
        return _studentRequests();
      case 3:
        return _studentReturns();
      case 4:
        return _profile();
      default:
        return _settings();
    }
  }

  Widget _adminPage() {
    switch (_tab) {
      case 0:
        return _adminOverview();
      case 1:
        return _adminInventory();
      case 2:
        return _adminRequests();
      case 3:
        return _adminReturns();
      case 4:
        return _adminPayments();
      case 5:
        return _adminExceptions();
      case 6:
        return _adminAccounts();
      case 7:
        return _adminReports();
      case 8:
        return _adminActivity();
      default:
        return _settings();
    }
  }

  Widget _settings() => _SettingsPage(
    api: widget.api,
    user: widget.user,
    isAdmin: _admin,
    themeMode: widget.themeMode,
    onThemeChanged: widget.onThemeChanged,
    onChangePassword: _changePassword,
    onEditProfile: () => _editProfile(),
    onHelp: _openHelp,
    onSync: _syncOfflineChanges,
    onSignOut: widget.onSignOut,
    offline: widget.api.isOffline,
    pendingSyncCount: _pendingSyncCount,
  );

  Widget _studentHome() {
    final active = _borrowings
        .where((row) => row["status"] == "active")
        .toList();
    final pending = _requests.where((row) => row["status"] == "pending").length;
    final balance = _penalties
        .where((row) => row["status"] == "unpaid")
        .fold<double>(
          0,
          (sum, row) =>
              sum + _number(row["amount"]) - _number(row["amount_paid"]),
        );
    final name = (widget.user["full_name"] as String? ?? "Student")
        .split(" ")
        .first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          title: "Good day, $name",
          subtitle: "Your equipment activity at a glance",
        ),
        if (active.isNotEmpty) _activeBorrowingCard(active.first),
        if (active.isEmpty)
          const _EmptyCard(
            icon: Icons.inventory_2_outlined,
            title: "Nothing borrowed right now",
            detail: "Browse the inventory to request equipment.",
          ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                icon: Icons.inventory_2_outlined,
                label: "Borrowed",
                value: "${active.length}",
                tone: _blue,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _MetricCard(
                icon: Icons.schedule,
                label: "Pending",
                value: "$pending",
                tone: const Color(0xFFD18A11),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _MetricCard(
                icon: Icons.check_circle_outline,
                label: "Returned",
                value:
                    "${_borrowings.where((row) => row["status"] == "returned").length}",
                tone: const Color(0xFF22945E),
              ),
            ),
          ],
        ),
        if (balance > 0) ...[
          const SizedBox(height: 14),
          _NoticeCard(
            icon: Icons.warning_amber_rounded,
            title: "${_peso(balance)} outstanding",
            detail: "Open your profile to submit a payment record.",
            warning: true,
            onTap: () => setState(() => _tab = 4),
          ),
        ],
        const SizedBox(height: 22),
        _SectionTitle(
          title: "Quick actions",
          trailing: IconButton.filledTonal(
            tooltip: "Scan equipment QR",
            onPressed: _scan,
            icon: const Icon(Icons.qr_code_scanner),
          ),
        ),
        _QuickButton(
          icon: Icons.search,
          title: "Browse equipment",
          detail: "${_equipment.length} items in the lab inventory",
          onTap: () => setState(() => _tab = 1),
        ),
        const SizedBox(height: 12),
        _SectionTitle(title: "Recent requests"),
        if (_requests.isEmpty)
          const _EmptyCard(
            icon: Icons.assignment_outlined,
            title: "No borrowing requests yet",
            detail: "Your requests will appear here.",
          )
        else
          ..._requests.take(3).map(_requestTile),
      ],
    );
  }

  Widget _inventory() => _InventoryView(
    key: const ValueKey("student-inventory"),
    items: _equipment,
    totalCount: _equipmentTotal,
    hasMore: _equipmentHasMore,
    categories: _equipmentCategories,
    offline: widget.api.isOffline,
    updating: _loading,
    isAdmin: false,
    loadPage:
        ({
          required limit,
          required offset,
          required search,
          required category,
          required status,
        }) => widget.api.getEquipmentPage(
          limit: limit,
          offset: offset,
          search: search,
          category: category,
          status: status,
        ),
    onDetails: _showEquipmentDetails,
    onScan: _scan,
  );

  Future<void> _showEquipmentDetails(JsonMap preview) async {
    try {
      final result = await widget.api.getEquipmentDetails(
        preview["equipment_code"] as String,
      );
      if (!mounted) return;
      final item = _map(result["item"]);
      final canBorrow =
          widget.user["role"] == "student" &&
          _integer(item["available_stock"]) > 0 &&
          _integer(item["is_active"]) != 0 &&
          !const {
            "Retired",
            "Under Maintenance",
            "Lost",
            "Damaged",
          }.contains(item["status"]);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.82,
            maxChildSize: 0.95,
            builder: (context, controller) => ListView(
              controller: controller,
              padding: const EdgeInsets.all(20),
              children: [
                SizedBox(
                  height: 180,
                  child: _EquipmentImage(asset: item["image_asset"] as String?),
                ),
                const SizedBox(height: 16),
                Text(
                  item["name"]?.toString() ?? "Equipment",
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                _StatusTag(status: item["status"]?.toString() ?? "Unknown"),
                const SizedBox(height: 12),
                for (final entry in <String, Object?>{
                  "Equipment ID": item["equipment_code"],
                  "Brand": item["brand"],
                  "Model": item["model"],
                  "Category": item["category"],
                  "Serial number": item["serial_number"],
                  "Quantity": item["total_stock"],
                  "Available": item["available_stock"],
                  "Borrowed": item["borrowed_quantity"],
                  "Pending": item["pending_quantity"],
                  "Condition": item["item_condition"],
                  "Location": item["location"] ?? item["program"],
                  "Description": item["description"],
                }.entries)
                  if (entry.value != null && entry.value.toString().isNotEmpty)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(entry.key),
                      subtitle: Text(entry.value.toString()),
                    ),
                if (widget.user["role"] == "admin") ...[
                  _SectionTitle(
                    title: "Borrowing history",
                    subtitle: "Latest 100 records",
                  ),
                  ..._list(result, "borrowings").map(
                    (row) => ListTile(
                      dense: true,
                      title: Text(
                        "${row["transaction_code"]} • ${row["student_name"]}",
                      ),
                      subtitle: Text(
                        "${row["status"]} • due ${_date(row["due_at"])}",
                      ),
                    ),
                  ),
                  _SectionTitle(title: "Return history"),
                  ..._list(result, "returns").map(
                    (row) => ListTile(
                      dense: true,
                      title: Text(
                        "${row["reported_condition"]} • ${row["status"]}",
                      ),
                      subtitle: Text(
                        "${row["transaction_code"]} • ${_date(row["reported_at"])}",
                      ),
                    ),
                  ),
                  _SectionTitle(title: "Damage and maintenance history"),
                  ..._list(result, "exceptions").map(
                    (row) => ListTile(
                      dense: true,
                      title: Text(
                        "${row["exception_type"]} • ${row["status"]}",
                      ),
                      subtitle: Text(
                        "${row["notes"] ?? "No notes"} • Qty ${row["quantity"]}",
                      ),
                    ),
                  ),
                ],
                if (widget.user["role"] == "student")
                  FilledButton(
                    onPressed: canBorrow
                        ? () {
                            Navigator.pop(sheetContext);
                            _requestItem(item);
                          }
                        : null,
                    child: Text(
                      canBorrow
                          ? "Request to borrow"
                          : "Not available to borrow",
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) _showMessage(context, error.message);
    }
  }

  Widget _studentRequests() {
    final pending = _requests
        .where((row) => row["status"] == "pending")
        .toList();
    final approved = _requests
        .where((row) => row["status"] == "approved")
        .toList();
    final declined = _requests
        .where((row) => row["status"] == "rejected")
        .toList();
    final visibleRequests = _requestFilter == "All"
        ? _requests
        : _requests.where((row) {
            final status = row["status"] as String? ?? "";
            return _requestFilter == "Declined"
                ? status == "rejected"
                : status == _requestFilter.toLowerCase();
          }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle(
          title: "My requests",
          subtitle: "Pending, approved, and declined decisions",
        ),
        _MetricRow(
          values: [
            ("Pending", pending.length, const Color(0xFFD18A11)),
            ("Approved", approved.length, const Color(0xFF22945E)),
            ("Declined", declined.length, const Color(0xFFCB5353)),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: ["All", "Pending", "Approved", "Declined"]
              .map(
                (filter) => ChoiceChip(
                  label: Text(filter),
                  selected: _requestFilter == filter,
                  onSelected: (_) => setState(() => _requestFilter = filter),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 15),
        if (_requests.isEmpty)
          const _EmptyCard(
            icon: Icons.assignment_outlined,
            title: "No requests found",
            detail: "Select an item from inventory to get started.",
          )
        else if (visibleRequests.isEmpty)
          _EmptyCard(
            icon: Icons.filter_list_off,
            title: "No $_requestFilter requests",
            detail: "Requests in this status will appear here.",
          )
        else
          ...visibleRequests.map(_requestTile),
      ],
    );
  }

  Widget _requestTile(JsonMap row) {
    final status = row["status"] as String? ?? "pending";
    return _InfoCard(
      leading: _EquipmentThumb(asset: row["image_asset"] as String?),
      title: row["item_name"] as String? ?? "Equipment",
      subtitle:
          "${row["request_code"] ?? ""}  •  ${_date(row["requested_at"])}",
      trailing: _StatusTag(status: status),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            status == "pending"
                ? "Awaiting staff review"
                : status == "approved"
                ? "Approved — collect from the IT Laboratory"
                : status == "rejected"
                ? "Declined by staff"
                : "Request $status",
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (status == "approved")
            ..._borrowings
                .where(
                  (borrow) => borrow["request_code"] == row["request_code"],
                )
                .map(
                  (borrow) => Align(
                    alignment: Alignment.centerRight,
                    child: _slipButton(borrow),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _studentReturns() {
    final active = _borrowings
        .where((row) => row["status"] == "active")
        .toList();
    final awaiting = _borrowings
        .where((row) => row["status"] == "return_pending")
        .toList();
    final past = _borrowings
        .where(
          (row) => row["status"] == "returned" || row["status"] == "missing",
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle(
          title: "Return equipment",
          subtitle: "Submit your condition for staff verification",
        ),
        if (active.isEmpty && awaiting.isEmpty)
          const _EmptyCard(
            icon: Icons.assignment_return_outlined,
            title: "No active borrowings",
            detail: "Approved equipment will appear here.",
          ),
        ...active.map(
          (row) => _InfoCard(
            leading: _EquipmentThumb(asset: row["image_asset"] as String?),
            title: row["item_name"] as String? ?? "Equipment",
            subtitle:
                "${row["transaction_code"]}  •  Due ${_date(row["due_at"])}",
            trailing: _StatusTag(status: "active"),
            footer: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 6,
              children: [
                _slipButton(row),
                FilledButton.tonalIcon(
                  onPressed: () => _returnItem(row),
                  icon: const Icon(Icons.assignment_return_outlined, size: 18),
                  label: const Text("Report return"),
                ),
              ],
            ),
          ),
        ),
        ...awaiting.map(
          (row) => _InfoCard(
            leading: _EquipmentThumb(asset: row["image_asset"] as String?),
            title: row["item_name"] as String? ?? "Equipment",
            subtitle: "Return report submitted — awaiting staff review",
            trailing: const _StatusTag(status: "return_pending"),
          ),
        ),
        if (past.isNotEmpty) ...[
          const SizedBox(height: 12),
          const _SectionTitle(title: "Borrowing history"),
          ...past.map(
            (row) => _InfoCard(
              leading: _EquipmentThumb(asset: row["image_asset"] as String?),
              title: row["item_name"] as String? ?? "Equipment",
              subtitle: "${row["transaction_code"]} • ${row["status"]}",
              trailing: _StatusTag(status: row["status"] as String),
              footer: Align(
                alignment: Alignment.centerRight,
                child: _slipButton(row),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _profile() {
    final balance = _penalties
        .where((row) => row["status"] == "unpaid")
        .fold<double>(
          0,
          (sum, row) =>
              sum + _number(row["amount"]) - _number(row["amount_paid"]),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle(
          title: "My account",
          subtitle: "Profile and payment records",
        ),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: _AccountAvatar(
                  api: widget.api,
                  user: widget.user,
                  radius: 26,
                ),
                title: Text(widget.user["full_name"] as String? ?? "Student"),
                subtitle: Text(
                  "${widget.user["account_id"]}  •  ${widget.user["program_section"] ?? "Student"}",
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _editProfile,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text("Edit profile"),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _NoticeCard(
          icon: balance > 0
              ? Icons.account_balance_wallet_outlined
              : Icons.verified_user_outlined,
          title: balance > 0
              ? "${_peso(balance)} outstanding"
              : "Account in good standing",
          detail: balance > 0
              ? "Submit a payment record. Staff verification is required before your balance is cleared."
              : "There are no unsettled penalties on your account.",
          warning: balance > 0,
          onTap: balance > 0 ? _payPenalty : null,
        ),
        const SizedBox(height: 20),
        const _SectionTitle(title: "Penalties"),
        if (_penalties.isEmpty)
          const _EmptyCard(
            icon: Icons.receipt_long_outlined,
            title: "No penalty records",
            detail: "Any penalties will appear here.",
          )
        else
          ..._penalties.map(
            (row) => _InfoCard(
              leading: const Icon(Icons.receipt_long_outlined),
              title: row["reason"] as String? ?? "Penalty",
              subtitle:
                  "${_peso(_number(row["amount"]))} • ${_date(row["created_at"])}",
              trailing: _StatusTag(status: row["status"] as String),
            ),
          ),
        const SizedBox(height: 12),
        const _SectionTitle(title: "Payment records"),
        if (_payments.isEmpty)
          const _EmptyCard(
            icon: Icons.payments_outlined,
            title: "No payment records",
            detail: "Payment submissions will be listed here.",
          )
        else
          ..._payments.map(
            (row) => _InfoCard(
              leading: const Icon(Icons.payments_outlined),
              title: "${row["method"]} • ${_peso(_number(row["amount"]))}",
              subtitle: "${row["payment_code"]} • ${_date(row["created_at"])}",
              trailing: _StatusTag(status: row["status"] as String),
            ),
          ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: widget.onSignOut,
          icon: const Icon(Icons.logout),
          label: const Text("Sign out"),
        ),
      ],
    );
  }

  Widget _adminOverview() {
    final pendingRequests = _requests
        .where((row) => row["status"] == "pending")
        .length;
    final pendingReturns = _returns
        .where((row) => row["status"] == "pending")
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          title:
              "Welcome, ${(widget.user["full_name"] as String? ?? "Admin").split(" ").first}",
          subtitle: "Equipment control center",
        ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.75,
          children: [
            _MetricCard(
              icon: Icons.inventory_2_outlined,
              label: "Equipment",
              value: "${_integer(_stats["equipment_count"])}",
              tone: _blue,
            ),
            _MetricCard(
              icon: Icons.assignment_outlined,
              label: "Pending requests",
              value: "$pendingRequests",
              tone: const Color(0xFFD18A11),
            ),
            _MetricCard(
              icon: Icons.assignment_return_outlined,
              label: "Pending returns",
              value: "$pendingReturns",
              tone: const Color(0xFF7A66C2),
            ),
            _MetricCard(
              icon: Icons.warning_amber_outlined,
              label: "Open exceptions",
              value: "${_integer(_stats["open_exceptions"])}",
              tone: const Color(0xFFCB5353),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _SectionTitle(
          title: "Review queue",
          trailing: TextButton(
            onPressed: () => setState(() => _tab = 2),
            child: const Text("Requests"),
          ),
        ),
        if (pendingRequests == 0)
          const _EmptyCard(
            icon: Icons.check_circle_outline,
            title: "All requests reviewed",
            detail: "New borrowing requests will appear here.",
          )
        else
          ..._requests
              .where((row) => row["status"] == "pending")
              .take(3)
              .map(_adminRequestCard),
        const SizedBox(height: 16),
        _QuickButton(
          icon: Icons.assessment_outlined,
          title: "System report",
          detail: "${_integer(_reports["audit_events"])} audit events recorded",
          onTap: () => setState(() => _tab = 7),
        ),
      ],
    );
  }

  Widget _adminInventory() => _InventoryView(
    key: const ValueKey("admin-inventory"),
    items: _equipment,
    totalCount: _equipmentTotal,
    hasMore: _equipmentHasMore,
    categories: _equipmentCategories,
    offline: widget.api.isOffline,
    updating: _loading,
    isAdmin: true,
    loadPage:
        ({
          required limit,
          required offset,
          required search,
          required category,
          required status,
        }) => widget.api.getEquipmentPage(
          limit: limit,
          offset: offset,
          search: search,
          category: category,
          status: status,
        ),
    onDetails: _showEquipmentDetails,
    itemBuilder: _adminEquipmentCard,
    onScan: _scan,
  );

  Widget _adminEquipmentCard(JsonMap item) => _InfoCard(
    leading: _EquipmentThumb(asset: item["image_asset"] as String?),
    title: item["name"] as String,
    subtitle:
        "${item["equipment_code"]} • ${item["brand"] ?? "—"} • ${item["category"]} • ${item["available_stock"]} available / ${item["total_stock"]} total",
    trailing: PopupMenuButton<String>(
      onSelected: (value) async {
        if (value == "missing") {
          await _action(
            () => widget.api.post("mark_missing", {
              "equipment_code": item["equipment_code"],
            }),
          );
        } else if (value == "remove") {
          final ok = await _confirm(
            context,
            "Remove ${item["name"]}?",
            "The record is kept in history but removed from active inventory.",
          );
          if (ok) {
            await _action(
              () => widget.api.post("remove_equipment", {
                "equipment_code": item["equipment_code"],
              }),
            );
          }
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: "missing", child: Text("Mark one missing")),
        PopupMenuItem(value: "remove", child: Text("Remove from inventory")),
      ],
    ),
    footer: Row(
      children: [
        IconButton.filledTonal(
          tooltip: "Reduce stock",
          onPressed: () => _action(
            () => widget.api.post("adjust_stock", {
              "equipment_code": item["equipment_code"],
              "delta": -1,
            }),
          ),
          icon: const Icon(Icons.remove, size: 18),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: "Add stock",
          onPressed: () => _action(
            () => widget.api.post("adjust_stock", {
              "equipment_code": item["equipment_code"],
              "delta": 1,
            }),
          ),
          icon: const Icon(Icons.add, size: 18),
        ),
        const Spacer(),
        Text(
          "Condition: ${item["item_condition"]} • ${item["status"] ?? "Unknown"}",
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );

  Widget _adminRequests() {
    final pending = _requests
        .where((row) => row["status"] == "pending")
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          title: "Borrowing requests",
          subtitle: "${pending.length} awaiting review",
        ),
        if (pending.isEmpty)
          const _EmptyCard(
            icon: Icons.check_circle_outline,
            title: "All requests reviewed",
            detail: "There are no requests in the approval queue.",
          )
        else
          ...pending.map(_adminRequestCard),
        const SizedBox(height: 16),
        const _SectionTitle(title: "Recent decisions"),
        ..._requests
            .where((row) => row["status"] != "pending")
            .take(10)
            .map(_requestTile),
      ],
    );
  }

  Widget _adminRequestCard(JsonMap row) => _InfoCard(
    leading: _EquipmentThumb(asset: row["image_asset"] as String?),
    title: row["item_name"] as String? ?? "Equipment request",
    subtitle:
        "${row["request_code"]} • ${row["student_name"]} (${row["account_id"]})",
    trailing: _StatusTag(status: row["status"] as String? ?? "pending"),
    footer: Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _adminAction(
              "review_request",
              idKey: "request_id",
              id: row["id"],
              decision: "rejected",
              referenceKey: "request_code",
              reference: row["request_code"],
            ),
            icon: const Icon(Icons.close, size: 18),
            label: const Text("Reject"),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: FilledButton.icon(
            onPressed: () => _adminAction(
              "review_request",
              idKey: "request_id",
              id: row["id"],
              decision: "approved",
              referenceKey: "request_code",
              reference: row["request_code"],
            ),
            icon: const Icon(Icons.check, size: 18),
            label: const Text("Approve"),
          ),
        ),
      ],
    ),
  );

  Widget _adminReturns() {
    final pending = _returns
        .where((row) => row["status"] == "pending")
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          title: "Return verification",
          subtitle: "${pending.length} reports awaiting staff review",
        ),
        if (pending.isEmpty)
          const _EmptyCard(
            icon: Icons.assignment_turned_in_outlined,
            title: "No returns to review",
            detail: "Student return reports appear in this queue.",
          )
        else
          ...pending.map(
            (row) => _InfoCard(
              leading: const Icon(Icons.assignment_return_outlined),
              title: row["item_name"] as String,
              subtitle:
                  "${row["student_name"]} • Reported ${row["reported_condition"]} • ${row["transaction_code"]}",
              trailing: _StatusTag(
                status: (row["reported_condition"] as String).toLowerCase(),
              ),
              footer: Row(
                children: [
                  if (_integer(row["has_photo"]) == 1)
                    IconButton(
                      tooltip: "View return photo",
                      onPressed: () => _viewReturnPhoto(row["id"]),
                      icon: const Icon(Icons.image_outlined),
                    ),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _adminAction(
                        "review_return",
                        idKey: "report_id",
                        id: row["id"],
                        decision: "reject",
                        referenceKey: "request_code",
                        reference: row["request_code"],
                      ),
                      child: const Text("Ask to resubmit"),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _adminAction(
                        "review_return",
                        idKey: "report_id",
                        id: row["id"],
                        decision: "accept",
                        referenceKey: "request_code",
                        reference: row["request_code"],
                      ),
                      child: const Text("Verify return"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        const _SectionTitle(title: "Active borrowings"),
        ..._borrowings
            .where((row) => row["status"] == "active")
            .take(10)
            .map(
              (row) => _InfoCard(
                leading: _EquipmentThumb(asset: row["image_asset"] as String?),
                title: row["item_name"] as String,
                subtitle:
                    "${row["student_name"]} • Due ${_date(row["due_at"])}",
                trailing: const _StatusTag(status: "active"),
              ),
            ),
      ],
    );
  }

  Widget _adminPayments() {
    final pending = _payments.where((row) => row["status"] == "pending");
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          title: "Payment verification",
          subtitle: "${pending.length} payment records awaiting review",
        ),
        if (pending.isEmpty)
          const _EmptyCard(
            icon: Icons.verified_outlined,
            title: "No payments awaiting review",
            detail: "New student payment records appear here.",
          ),
        ..._payments.map(
          (row) => _InfoCard(
            leading: const Icon(Icons.payments_outlined),
            title: "${row["student_name"]} • ${_peso(_number(row["amount"]))}",
            subtitle:
                "${row["method"]} • ${row["payment_code"]} • ${row["reference_note"] ?? "No reference"}",
            trailing: _StatusTag(status: row["status"] as String),
            footer: row["status"] != "pending"
                ? null
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _adminAction(
                            "review_payment",
                            idKey: "payment_id",
                            id: row["id"],
                            decision: "reject",
                            referenceKey: "payment_code",
                            reference: row["payment_code"],
                          ),
                          child: const Text("Reject"),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => _adminAction(
                            "review_payment",
                            idKey: "payment_id",
                            id: row["id"],
                            decision: "verify",
                            referenceKey: "payment_code",
                            reference: row["payment_code"],
                          ),
                          child: const Text("Verify"),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _adminExceptions() {
    final open = _exceptions.where((row) => row["status"] == "open");
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          title: "Inventory exceptions",
          subtitle: "${open.length} missing or damaged records need attention",
        ),
        if (open.isEmpty)
          const _EmptyCard(
            icon: Icons.verified_outlined,
            title: "No open exceptions",
            detail: "Missing and damaged items will appear here.",
          ),
        ..._exceptions.map(
          (row) => _InfoCard(
            leading: const Icon(Icons.warning_amber_outlined),
            title: "${row["item_name"]} • ${row["exception_type"]}",
            subtitle:
                "${row["reported_by_name"] ?? "Staff"} • ${row["notes"] ?? "No notes"} • Qty ${row["quantity"] ?? 1}",
            trailing: _StatusTag(status: row["status"] as String),
            footer: row["status"] == "open"
                ? Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonal(
                      onPressed: () => _action(
                        () => widget.api.post("resolve_exception", {
                          "exception_id": row["id"],
                          "equipment_code": row["equipment_code"],
                          "exception_type": row["exception_type"],
                        }),
                      ),
                      child: const Text("Resolve exception"),
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  Widget _adminAccounts() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _SectionTitle(
        title: "Account directory",
        subtitle: "${_users.length} registered students and administrators",
      ),
      ..._users.map(
        (row) => _InfoCard(
          leading: row["role"] == "student"
              ? _AccountAvatar(api: widget.api, user: row, radius: 22)
              : const Icon(Icons.admin_panel_settings_outlined),
          title: row["full_name"] as String? ?? "Account",
          subtitle:
              "${row["account_id"]} • ${row["program_section"] ?? row["role"]}${row["contact_number"] == null ? "" : " • ${row["contact_number"]}"}",
          trailing: _StatusTag(
            status: row["account_status"] as String? ?? "active",
          ),
          footer: row["role"] == "student"
              ? Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _viewStudentAccount(row),
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text("View account"),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _editProfile(account: row),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text("Edit"),
                    ),
                  ],
                )
              : null,
        ),
      ),
    ],
  );

  Future<void> _viewStudentAccount(JsonMap row) async {
    final accountId = row["account_id"]?.toString() ?? "";
    try {
      final detail = await widget.api.getStudentAccount(accountId);
      if (!mounted) return;
      final profile = _map(detail["profile"]);
      List<JsonMap> history(String key) => _list(detail, key);
      Widget historySection(
        String title,
        String key,
        String Function(JsonMap) label,
      ) {
        final records = history(key);
        return ExpansionTile(
          title: Text("$title (${records.length})"),
          children: records.isEmpty
              ? const [ListTile(title: Text("No records"))]
              : records
                    .map(
                      (record) => ListTile(
                        dense: true,
                        title: Text(label(record)),
                        subtitle: Text(
                          "${record["status"] ?? ""} • ${_date(record["created_at"] ?? record["requested_at"] ?? record["borrowed_at"] ?? record["reported_at"])}",
                        ),
                      ),
                    )
                    .toList(),
        );
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              _AccountAvatar(api: widget.api, user: profile, radius: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(profile["full_name"]?.toString() ?? accountId),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            height: 620,
            child: ListView(
              children: [
                Text("${profile["account_id"]} • ${profile["account_status"]}"),
                if (profile["email"] != null) Text("${profile["email"]}"),
                if (profile["contact_number"] != null)
                  Text("${profile["contact_number"]}"),
                if (profile["program_section"] != null)
                  Text("${profile["program_section"]}"),
                const Divider(),
                historySection("Borrowing requests", "requests", (record) {
                  return "${record["item_name"]} • ${record["request_code"]}";
                }),
                historySection("Borrowing history", "borrowings", (record) {
                  return "${record["item_name"]} • ${record["transaction_code"]}";
                }),
                historySection("Return history", "returns", (record) {
                  return "${record["item_name"]} • ${record["reported_condition"]}";
                }),
                historySection("Penalties", "penalties", (record) {
                  return "${record["reason"]} • ${_peso(_number(record["amount"]))}";
                }),
                historySection("Payments", "payments", (record) {
                  return "${record["payment_code"]} • ${_peso(_number(record["amount"]))}";
                }),
                historySection("Account activity", "activities", (record) {
                  return "${record["action"]}${record["details"] == null ? "" : " • ${record["details"]}"}";
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Close"),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                unawaited(_editProfile(account: {...row, ...profile}));
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text("Edit Student"),
            ),
          ],
        ),
      );
    } on ApiException catch (error) {
      if (mounted) _showMessage(context, error.message);
    }
  }

  Widget _adminReports() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _SectionTitle(
        title: "System reports",
        subtitle: "Live operational totals from the connected database",
      ),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.65,
        children: _reports.entries
            .map(
              (entry) => _MetricCard(
                icon: Icons.assessment_outlined,
                label: _humanize(entry.key),
                value: "${entry.value}",
                tone: _blue,
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 18),
      const _SectionTitle(title: "Operational totals"),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _stats.entries
            .map(
              (entry) =>
                  Chip(label: Text("${_humanize(entry.key)}: ${entry.value}")),
            )
            .toList(),
      ),
    ],
  );

  Widget _adminActivity() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _SectionTitle(
        title: "Audit activity",
        subtitle: "Recent changes and account activity in the system",
      ),
      if (_logs.isEmpty)
        const _EmptyCard(
          icon: Icons.history,
          title: "No activity recorded",
          detail: "System events will appear here as they happen.",
        ),
      ..._logs.map(
        (row) => _InfoCard(
          leading: const Icon(Icons.history),
          title: row["action"] as String,
          subtitle:
              "${row["actor_name"] ?? "System"} • ${_date(row["created_at"])}",
          footer: row["details"] == null
              ? null
              : Text(
                  row["details"] as String,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
        ),
      ),
    ],
  );

  Widget _activeBorrowingCard(JsonMap row) => Card(
    clipBehavior: Clip.antiAlias,
    child: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_navy, Color(0xFF1A719D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "ACTIVE BORROWING",
            style: TextStyle(
              color: Color(0xFFADE9F1),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            row["item_name"] as String,
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            "Due ${_date(row["due_at"])}",
            style: const TextStyle(color: Color(0xFFD0E8F0)),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() => _tab = 3),
              child: const Text(
                "Return item  →",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({
    required this.api,
    required this.user,
    required this.isAdmin,
    required this.themeMode,
    required this.onThemeChanged,
    required this.onChangePassword,
    required this.onEditProfile,
    required this.onHelp,
    required this.onSync,
    required this.onSignOut,
    required this.offline,
    required this.pendingSyncCount,
  });

  final ApiClient api;
  final JsonMap user;
  final bool isAdmin;
  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode mode) onThemeChanged;
  final VoidCallback onChangePassword;
  final VoidCallback onEditProfile;
  final VoidCallback onHelp;
  final VoidCallback onSync;
  final Future<void> Function() onSignOut;
  final bool offline;
  final int pendingSyncCount;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  static const _notificationOptions = <(String, String)>[
    ("borrow_requests", "Borrowing approvals and rejections"),
    ("due_reminders", "Due-date reminders"),
    ("overdue", "Overdue notices"),
    ("returns", "Return updates"),
    ("penalties", "Penalty updates"),
    ("payments", "Payment verification updates"),
    ("announcements", "System announcements"),
  ];

  late final String _preferencePrefix =
      "stokli_${Uri.encodeComponent(widget.user["account_id"]?.toString() ?? "")}_";
  final Map<String, bool> _notifications = {};
  bool _loadingPreferences = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      for (final (key, _) in _notificationOptions) {
        _notifications[key] =
            preferences.getBool("$_preferencePrefix$key") ?? true;
      }
      _loadingPreferences = false;
    });
  }

  Future<void> _setNotification(String key, bool value) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setBool("$_preferencePrefix$key", value);
    if (!saved) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("The notification preference was not saved."),
          ),
        );
      }
      return;
    }
    if (mounted) setState(() => _notifications[key] = value);
  }

  Future<void> _selectTheme(ThemeMode mode) async {
    try {
      await widget.onThemeChanged(mode);
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Unable to save appearance: $error")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fullName = widget.user["full_name"]?.toString() ?? "Account";
    final accountId = widget.user["account_id"]?.toString() ?? "—";
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          title: widget.isAdmin ? "Administrator settings" : "Student settings",
          subtitle: "Account, appearance, and preferences for $accountId",
        ),
        Card(
          child: ListTile(
            leading: _AccountAvatar(
              api: widget.api,
              user: widget.user,
              radius: 28,
            ),
            title: Text(fullName),
            subtitle: Text(
              "$accountId • ${widget.isAdmin ? "Administrator" : widget.user["program_section"] ?? "Student"}",
            ),
          ),
        ),
        const SizedBox(height: 12),
        const _SectionTitle(title: "Customization", subtitle: "Appearance"),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  "Theme",
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text("Light"),
                      icon: Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text("Dark"),
                      icon: Icon(Icons.dark_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text("System"),
                      icon: Icon(Icons.settings_brightness_outlined),
                    ),
                  ],
                  selected: {widget.themeMode},
                  onSelectionChanged: (value) => _selectTheme(value.first),
                ),
                const SizedBox(height: 8),
                Text(
                  "This preference is saved for this account and applies across the app.",
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const _SectionTitle(
          title: "Notifications",
          subtitle: "Saved as private preferences for this account",
        ),
        Card(
          child: _loadingPreferences
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: LinearProgressIndicator(),
                )
              : Column(
                  children: [
                    for (final (key, label) in _notificationOptions)
                      SwitchListTile(
                        value: _notifications[key] ?? true,
                        title: Text(label),
                        onChanged: (value) => _setNotification(key, value),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: Text(
                        "These choices are stored locally. Push or scheduled notification delivery is not configured in this build.",
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        if (widget.isAdmin) ...[
          const SizedBox(height: 12),
          const _SectionTitle(title: "System settings"),
          const _MessageBanner(
            message: "System-wide settings such as borrowing limits, penalty rates, and school branding are not configured in the current MySQL schema/API.",
            isError: false,
          ),
        ],
        const SizedBox(height: 12),
        _SectionTitle(
          title: widget.isAdmin ? "Administrator account" : "Account",
        ),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: const Text("Change password"),
                trailing: const Icon(Icons.chevron_right),
                onTap: widget.onChangePassword,
              ),
              ListTile(
                leading: const Icon(Icons.manage_accounts_outlined),
                title: const Text("Edit profile"),
                subtitle: const Text(
                  "Update permitted account information and photo",
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: widget.onEditProfile,
              ),
              ListTile(
                leading: const Icon(Icons.support_agent_outlined),
                title: const Text("FAQ & Help Support"),
                subtitle: const Text(
                  "Search the guide or ask a how-to question",
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: widget.onHelp,
              ),
              if (widget.offline || widget.pendingSyncCount > 0)
                ListTile(
                  leading: Icon(
                    widget.offline ? Icons.cloud_off_outlined : Icons.sync,
                  ),
                  title: Text(
                    widget.offline
                        ? "Offline — saved on this device"
                        : "${widget.pendingSyncCount} changes waiting to sync",
                  ),
                  subtitle: Text(
                    widget.offline
                        ? "Reconnect to the server to synchronize queued changes."
                        : "Queued changes are retained until synchronization succeeds.",
                  ),
                  trailing: widget.pendingSyncCount > 0 && !widget.offline
                      ? TextButton(
                          onPressed: widget.onSync,
                          child: const Text("Sync now"),
                        )
                      : null,
                ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text("Sign out"),
                onTap: widget.onSignOut,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InventoryView extends StatefulWidget {
  const _InventoryView({
    super.key,
    required this.items,
    required this.totalCount,
    required this.hasMore,
    required this.categories,
    required this.offline,
    required this.updating,
    required this.isAdmin,
    required this.loadPage,
    required this.onDetails,
    required this.onScan,
    this.itemBuilder,
  });

  final List<JsonMap> items;
  final int totalCount;
  final bool hasMore;
  final List<String> categories;
  final bool offline;
  final bool updating;
  final bool isAdmin;
  final Future<JsonMap> Function({
    required int limit,
    required int offset,
    required String search,
    required String category,
    required String status,
  })
  loadPage;
  final Future<void> Function(JsonMap item) onDetails;
  final VoidCallback onScan;
  final Widget Function(JsonMap item)? itemBuilder;

  @override
  State<_InventoryView> createState() => _InventoryViewState();
}

class _InventoryViewState extends State<_InventoryView> {
  static const _pageSize = 30;
  final _query = TextEditingController();
  Timer? _searchDebounce;
  late List<JsonMap> _items;
  late int _totalCount;
  late bool _hasMore;
  late List<String> _categories;
  late bool _offline;
  String _category = "All";
  String _status = "All";
  bool _loadingPage = false;
  bool _searching = false;
  String? _error;
  int _queryGeneration = 0;

  @override
  void initState() {
    super.initState();
    _items = List<JsonMap>.from(widget.items);
    _totalCount = widget.totalCount;
    _hasMore = widget.hasMore;
    _categories = widget.categories;
    _offline = widget.offline;
  }

  @override
  void didUpdateWidget(covariant _InventoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.items, oldWidget.items)) {
      _items = List<JsonMap>.from(widget.items);
      _totalCount = widget.totalCount;
      _hasMore = widget.hasMore;
      _categories = widget.categories;
    }
    _offline = widget.offline;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 300),
      () => _loadFirstPage(),
    );
  }

  Future<void> _loadFirstPage() async {
    final generation = ++_queryGeneration;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final result = await widget.loadPage(
        limit: _pageSize,
        offset: 0,
        search: _query.text.trim(),
        category: _category,
        status: _status,
      );
      if (!mounted || generation != _queryGeneration) return;
      setState(() {
        _items = _list(result);
        _totalCount = _integer(result["total_count"]);
        _hasMore = result["has_more"] == true;
        _categories = _stringList(result["categories"]);
        _offline = result["offline"] == true || widget.offline;
      });
    } on ApiException catch (error) {
      if (mounted && generation == _queryGeneration) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted && generation == _queryGeneration) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingPage || _searching || !_hasMore) return;
    setState(() {
      _loadingPage = true;
      _error = null;
    });
    try {
      final result = await widget.loadPage(
        limit: _pageSize,
        offset: _items.length,
        search: _query.text.trim(),
        category: _category,
        status: _status,
      );
      if (!mounted) return;
      final combined = <String, JsonMap>{
        for (final item in _items)
          item["equipment_code"]?.toString() ?? "${item["id"]}": item,
        for (final item in _list(result))
          item["equipment_code"]?.toString() ?? "${item["id"]}": item,
      };
      setState(() {
        _items = combined.values.toList();
        _totalCount = _integer(result["total_count"]);
        _hasMore = result["has_more"] == true;
        _categories = _stringList(result["categories"]);
        _offline = result["offline"] == true || widget.offline;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loadingPage = false);
    }
  }

  List<JsonMap> _list(JsonMap response) {
    final rows = response["items"];
    if (rows is! List) return [];
    return rows.whereType<Map<String, dynamic>>().toList();
  }

  @override
  Widget build(BuildContext context) {
    const statuses = [
      "All",
      "Available",
      "Borrowed",
      "Pending",
      "Overdue",
      "Damaged",
      "Lost",
      "Under Maintenance",
      "Retired",
      "Unavailable",
    ];
    final categories = ["All", ..._categories.where((value) => value != "All")];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          title: widget.isAdmin
              ? "Complete equipment inventory"
              : "Equipment inventory",
          subtitle: "$_totalCount records • ${_items.length} loaded",
          trailing: IconButton.filledTonal(
            tooltip: "Scan equipment QR",
            onPressed: widget.onScan,
            icon: const Icon(Icons.qr_code_scanner),
          ),
        ),
        TextField(
          controller: _query,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: "Search all inventory by ID, name, brand, model, serial",
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.text.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _query.clear();
                      setState(() {});
                      _loadFirstPage();
                    },
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        if (_offline)
          const _MessageBanner(
            message: "Offline — showing locally synchronized inventory.",
            isError: false,
          )
        else
          Text(
            widget.updating
                ? "Online • Updating from the central inventory…"
                : "Online • connected to the central inventory.",
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        if (widget.updating && !_offline) ...[
          const SizedBox(height: 6),
          const LinearProgressIndicator(),
        ],
        if (_searching) ...[
          const SizedBox(height: 6),
          const LinearProgressIndicator(),
          const Text("Updating inventory…", style: TextStyle(fontSize: 11)),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: categories
              .map(
                (category) => ChoiceChip(
                  label: Text(category),
                  selected: _category == category,
                  onSelected: (_) {
                    _searchDebounce?.cancel();
                    setState(() => _category = category);
                    _loadFirstPage();
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: statuses
              .map(
                (status) => ChoiceChip(
                  label: Text(status),
                  selected: _status == status,
                  onSelected: (_) {
                    _searchDebounce?.cancel();
                    setState(() => _status = status);
                    _loadFirstPage();
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 10),
        if (_error != null) ...[
          _MessageBanner(message: _error!, isError: true),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _loadFirstPage,
              icon: const Icon(Icons.refresh),
              label: const Text("Retry"),
            ),
          ),
        ],
        if (_items.isEmpty && _searching)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_items.isEmpty && _error != null)
          const _EmptyCard(
            icon: Icons.cloud_off_outlined,
            title: "Unable to load inventory",
            detail: "Retry to reconnect and load equipment records.",
          )
        else if (_items.isEmpty)
          const _EmptyCard(
            icon: Icons.search_off,
            title: "No matching equipment",
            detail: "Try another search or category.",
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _items.length + (_hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _items.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: _loadingPage
                        ? const CircularProgressIndicator()
                        : OutlinedButton.icon(
                            onPressed: _loadMore,
                            icon: const Icon(Icons.expand_more),
                            label: Text(
                              "Load more (${(_totalCount - _items.length).clamp(0, _totalCount)} remaining)",
                            ),
                          ),
                  ),
                );
              }
              final item = _items[index];
              if (widget.isAdmin && widget.itemBuilder != null) {
                return InkWell(
                  onTap: () => widget.onDetails(item),
                  child: widget.itemBuilder!(item),
                );
              }
              final stock = _integer(item["available_stock"]);
              return Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: SizedBox(
                    width: 56,
                    height: 56,
                    child: _EquipmentImage(
                      asset: item["image_asset"] as String?,
                      cacheWidth: 112,
                    ),
                  ),
                  title: Text(
                    item["name"]?.toString() ?? "Equipment",
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      "${item["equipment_code"]} • ${item["brand"] ?? "—"} • ${item["model"] ?? item["category"] ?? "—"}",
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: _StatusTag(
                          status: item["status"]?.toString() ?? "Unknown",
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "$stock / ${_integer(item["total_stock"])}",
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                  onTap: () => widget.onDetails(item),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _QrScannerScreen extends StatefulWidget {
  const _QrScannerScreen();

  @override
  State<_QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<_QrScannerScreen> {
  bool _handled = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan equipment QR")),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (_handled || capture.barcodes.isEmpty) return;
              final value = capture.barcodes.first.rawValue;
              if (value == null || value.trim().isEmpty) return;
              _handled = true;
              Navigator.of(context).pop(value);
            },
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? "Allow camera access to scan equipment QR codes."
                      : "Camera could not start: ${error.errorCode.name}",
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          const Positioned(
            left: 32,
            right: 32,
            bottom: 56,
            child: Text(
              "Center the equipment label inside the frame.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 8, color: Colors.black)],
              ),
            ),
          ),
          if (_error != null)
            Center(
              child: Text(_error!, style: const TextStyle(color: Colors.white)),
            ),
        ],
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Image.asset(
          "assets/stokli/stokli-logo.jpg",
          width: 86,
          height: 86,
          fit: BoxFit.cover,
        ),
      ),
      const SizedBox(height: 14),
      Text(
        "STOKLI",
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 25,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.1,
        ),
      ),
      Text(
        "Equipment borrowing & return tracking",
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ],
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 13, 2, 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tone, size: 19),
          const SizedBox(height: 9),
          Text(
            value,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
        ],
      ),
    ),
  );
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.values});

  final List<(String, int, Color)> values;

  @override
  Widget build(BuildContext context) => Row(
    children: values
        .map(
          (value) => Expanded(
            child: _MetricCard(
              icon: Icons.circle_outlined,
              label: value.$1,
              value: "${value.$2}",
              tone: value.$3,
            ),
          ),
        )
        .toList(),
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.leading,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.footer,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              leading is Icon
                  ? Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF4F8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: leading,
                    )
                  : leading,
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 6), trailing!],
            ],
          ),
          if (footer != null) ...[const SizedBox(height: 11), footer!],
        ],
      ),
    ),
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(icon, color: _blue, size: 28),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    ),
  );
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final color = switch (normalized) {
      "available" ||
      "approved" ||
      "returned" ||
      "good" ||
      "verified" ||
      "paid" ||
      "active" => const Color(0xFF188453),
      "pending" || "return_pending" || "damaged" => const Color(0xFFAD7200),
      "missing" ||
      "rejected" ||
      "unpaid" ||
      "unavailable" ||
      "suspended" => const Color(0xFFB43D3D),
      _ => const Color(0xFF526479),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        status.replaceAll("_", " "),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EquipmentThumb extends StatelessWidget {
  const _EquipmentThumb({this.asset});

  final String? asset;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: SizedBox(
      width: 44,
      height: 44,
      child: _EquipmentImage(asset: asset, cacheWidth: 96),
    ),
  );
}

class _EquipmentImage extends StatelessWidget {
  const _EquipmentImage({this.asset, this.cacheWidth = 480});

  final String? asset;
  final int cacheWidth;

  @override
  Widget build(BuildContext context) {
    if (asset == null || asset!.isEmpty) {
      return const ColoredBox(
        color: Color(0xFFEAF5F8),
        child: Icon(Icons.inventory_2_outlined, color: _blue),
      );
    }
    return Image.asset(
      "assets/stokli/$asset",
      fit: BoxFit.cover,
      cacheWidth: cacheWidth,
      cacheHeight: cacheWidth,
      errorBuilder: (context, error, stackTrace) => const ColoredBox(
        color: Color(0xFFEAF5F8),
        child: Icon(Icons.inventory_2_outlined, color: _blue),
      ),
    );
  }
}

class _QuickButton extends StatelessWidget {
  const _QuickButton({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFE5F6FA),
        child: Icon(icon, color: _blue),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(detail),
      trailing: const Icon(Icons.chevron_right),
    ),
  );
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.title,
    required this.detail,
    this.warning = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool warning;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).brightness == Brightness.dark
        ? warning
              ? const Color(0xFF493914)
              : const Color(0xFF193B32)
        : warning
        ? const Color(0xFFFFF7E2)
        : const Color(0xFFEAF7F2),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: warning
                  ? const Color(0xFFAD7200)
                  : const Color(0xFF188453),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            ?onTap == null
                ? null
                : Icon(
                    Icons.chevron_right,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
          ],
        ),
      ),
    ),
  );
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).brightness == Brightness.dark
          ? (isError ? const Color(0xFF48282A) : const Color(0xFF193B32))
          : (isError ? const Color(0xFFFFEEEE) : const Color(0xFFE8F7EE)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      message,
      style: TextStyle(
        color: Theme.of(context).brightness == Brightness.dark
            ? (isError ? const Color(0xFFFFB4AB) : const Color(0xFF8CE0B7))
            : (isError ? const Color(0xFFAA3030) : const Color(0xFF167346)),
        fontSize: 12,
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.retry});

  final String message;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, color: _blue, size: 42),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: const Text("Try again"),
          ),
        ],
      ),
    ),
  );
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Confirm"),
          ),
        ],
      ),
    ) ??
    false;

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({
    required this.api,
    required this.user,
    this.radius = 24,
  });

  final ApiClient api;
  final JsonMap user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final bytes = user["profile_photo_data"];
    if (bytes is List<int> && bytes.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        child: ClipOval(
          child: Image.memory(
            Uint8List.fromList(bytes),
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.person_outline),
          ),
        ),
      );
    }
    final userId = _integer(user["id"]);
    if (!api.isOffline && user["profile_photo"] is String && userId > 0) {
      return CircleAvatar(
        radius: radius,
        child: ClipOval(
          child: Image.network(
            api.profilePhotoUri(userId).toString(),
            headers: api.authenticatedImageHeaders,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.person_outline),
          ),
        ),
      );
    }
    final name = user["full_name"]?.toString() ?? "";
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      child: Text(
        name.isEmpty ? "?" : _initials(name),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

JsonMap _map(dynamic value) =>
    value is Map<String, dynamic> ? value : <String, dynamic>{};

List<String> _stringList(dynamic value) =>
    value is List ? value.whereType<String>().toList() : <String>[];

int _integer(dynamic value) => int.tryParse(value?.toString() ?? "") ?? 0;

double _number(dynamic value) => double.tryParse(value?.toString() ?? "") ?? 0;

String _peso(double value) => "₱${value.toStringAsFixed(2)}";

String _date(dynamic value) {
  if (value == null) return "—";
  final parsed = DateTime.tryParse(value.toString());
  if (parsed == null) return value.toString();
  final local = parsed.toLocal();
  return "${local.day.toString().padLeft(2, "0")}/"
      "${local.month.toString().padLeft(2, "0")}/${local.year} "
      "${local.hour.toString().padLeft(2, "0")}:"
      "${local.minute.toString().padLeft(2, "0")}";
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r"\s+"))
      .where((part) => part.isNotEmpty);
  return parts.take(2).map((part) => part[0].toUpperCase()).join();
}

bool _isProfileImage(List<int> bytes) =>
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

String _humanize(String value) => value
    .replaceAll("_", " ")
    .replaceAllMapped(RegExp(r"[A-Z]"), (match) => " ${match[0]}")
    .trim();
