# Stokli

Stokli is a Flutter equipment borrowing and return tracking system. The mobile app can use the PHP API and MySQL database running on XAMPP, with SQLite for offline work. A browser demo is deployed from the same Flutter app and stores its fictional data locally in the browser; it never connects to XAMPP or MySQL. The original Figma Make React preview remains available at the project root.

## Browser demo

The Flutter Web demo is published at <https://winterbanana.github.io/Stokli_Finals/>. Use the **Student demo** or **Admin demo** shortcut on the sign-in screen. The demo accounts and records are fictional, and changes persist only in that browser's local storage. Use **Settings → Reset demo data** to restore the initial browser-only sample records. This is not a live connection to the mobile app or MySQL database.

GitHub Pages builds and deploys the app from [`mobile/`](./mobile/) using the workflow in [`.github/workflows/deploy-web.yml`](./.github/workflows/deploy-web.yml). If Pages has not been enabled for the repository, select **Settings → Pages → GitHub Actions**.

## First run on Windows/XAMPP

1. Keep this project inside `C:\xampp\htdocs\Stokli BMC` (or update the XAMPP path in `launch_stokli.bat`).
2. Import [`database/stokli_bmc.sql`](./database/stokli_bmc.sql) in phpMyAdmin, or run [`launch_stokli.bat`](./launch_stokli.bat). The launcher starts MySQL and Apache and imports the file only when the `stokli_bmc` database does not exist.
3. Open the launcher with an Android emulator running. It starts `flutter run` after the API is ready; the emulator API endpoint is compiled into the API service and is not shown in the app UI.
4. For a physical phone, build/run with the host API URL supplied privately at build time, for example `flutter run --dart-define=STOKLI_API_BASE_URL=http://192.168.1.10/Stokli%20BMC/api/index.php`. Keep the phone and host on the same Wi-Fi and allow Apache through Windows Firewall on a private network if asked.

XAMPP's default MySQL setup is expected to use `root` without a password. If your local credentials differ, set `STOKLI_DB_HOST`, `STOKLI_DB_PORT`, `STOKLI_DB_NAME`, `STOKLI_DB_USER`, and `STOKLI_DB_PASSWORD` in the environment used by Apache; the defaults are in [`api/config.php`](./api/config.php).

The SQL file includes local sample records. Demo sign-in is `STUDENT-001` / `demo-student` for a student or `ADMIN-001` / `demo-admin` for an administrator. Do not use seeded/sample accounts in a real deployment; provision accounts with unique credentials and replace any demonstration passwords before use.

## Flutter commands

Run these commands from `mobile`:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

Build an Android release package with `flutter build apk --release`.
The prebuilt architecture-specific APKs are in `mobile/build/app/outputs/flutter-apk/`; use `app-arm64-v8a-release.apk` for most current Android phones. To regenerate them, run `flutter build apk --release --split-per-abi`.

## Mobile app and local server

The phone app does not run XAMPP on the phone. XAMPP must remain running on the Windows host, and the phone must be able to reach that host over the network. The API endpoint accepts local HTTP for development; do not expose this configuration or the seeded accounts to a public network. For production, use HTTPS, strong credentials, and a properly secured MySQL account.

Student users can browse/scan equipment, submit borrowing requests, report a return with an optional photo, review penalties, and submit payment records for staff verification. Administrator accounts can review borrowing and return requests, adjust inventory, manage missing/damaged exceptions, verify payments, view account records, and inspect the audit log. Payment submissions are records for staff verification; the app does not charge GCash, Maya, or another wallet.

Both roles have a dedicated **Settings** page. Light, dark, and system appearance preferences are saved separately per account and apply app-wide. Users can edit permitted profile fields, change a password, and upload/remove a profile photo. In the Web Demo these changes stay in browser storage; the demo never syncs to MySQL. Administrators can view student account history and edit permitted student fields/status from **Accounts**. Notification categories are saved locally per account, but push/scheduled notification delivery is not configured. API endpoint configuration remains internal to the app build; there is no in-app server URL/test control.

**FAQ & Help Support** is bundled in the app and works offline. Its chat-style helper retrieves role-appropriate answers from the local Stokli guide only; it does not call an external AI provider or access live personal, borrowing, payment, or inventory records. The current schema does not provide an administrator password-reset workflow.

## Inventory browsing

Student and administrator inventory screens use the same MySQL equipment catalogue online and SQLite's cached copy offline. Inventory is requested in 30-record pages (up to 100 per API request), with server-side search across equipment ID/code, name, brand, model, category, serial number, and status. Use **Load more** to reach later records; changing search/category/status filters searches the complete matching inventory. Each fetched page is cached to SQLite for offline browsing; pages not yet fetched remain on the central server. The list loads compact metadata and small image decodes; tap an item for full details, and administrators can open its latest borrowing, return, and exception history there. Retired and otherwise non-borrowable equipment remains visible, while the student borrow action is disabled when current stock/status prohibits a request.

The API applies non-destructive, versioned schema migrations for older databases, including profile email/photo/version fields and inventory/search/history indexes. Account/profile fields use additive changes; existing account, equipment, and transaction rows are not reset or removed. The migration runs when the API is first used after deployment; importing the SQL file is not a substitute for keeping a database backup.

## Offline mode and synchronization

The app persists local sample data and server read snapshots in SQLite. Once an account has been cached on the device, borrowing, approvals, returns, payment records/reviews, supported inventory actions, and profile/photo updates can continue offline. Those writes are kept in a per-account outbox and shown as waiting to sync. Use **Sync** in the app and re-authenticate with the same account when XAMPP is reachable; the outbox replays in order and keeps any failed operation on-device with an error message. Profile changes use an expected server version; a conflict is reported and the queued edit is retained instead of silently overwriting newer data. Server operations carry idempotency keys, so retrying a response-lost operation does not create a second record. Account registration and password changes require a live server connection; passwords are not queued for offline sync. SQLite remains device-local and should not be treated as a backup; protect devices that contain cached personal data.
