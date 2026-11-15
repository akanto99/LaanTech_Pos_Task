# LaanTech POS — Background Upload/Download Module

A Flutter module for a POS SaaS application that transfers large files (product catalogs, CSV imports, images, videos and reports) reliably in the background on Android.

Built for the **LAAN TECH USA Limited — Android POS Developer** technical assessment.

---

## Contents

1. [Assessment objectives](#1-assessment-objectives)
2. [Implementation status](#2-implementation-status)
3. [Technology stack](#3-technology-stack)
4. [Architecture](#4-architecture)
5. [Folder structure](#5-folder-structure)
6. [API integration](#6-api-integration)
7. [Upload implementation](#7-upload-implementation)
8. [Download implementation](#8-download-implementation)
9. [Global transfer management](#9-global-transfer-management)
10. [Background execution strategy](#10-background-execution-strategy)
11. [Notifications](#11-notifications)
12. [Pause, resume, retry and cancel](#12-pause-resume-retry-and-cancel)
13. [Error handling and resilience](#13-error-handling-and-resilience)
14. [Storage](#14-storage)
15. [Android platform restrictions](#15-android-platform-restrictions)
16. [iOS limitations](#16-ios-limitations)
17. [Dependencies](#17-dependencies)
18. [Installation, running and building](#18-installation-running-and-building)
19. [Testing](#19-testing)
20. [Verification performed](#20-verification-performed)
21. [Known limitations](#21-known-limitations)
22. [Future improvements](#22-future-improvements)

---

## 1. Assessment objectives

- Upload large files (CSV, images, videos and other formats, including files over 50 MB) using `multipart/form-data` with the field `file`.
- List previously uploaded server files and download them with HTTP Range resume.
- Run transfers independently of the current screen and keep them running while the app is minimised.
- Track every transfer centrally, persist it, and restore it after an app restart.
- Show progress, completion and failure notifications that open the relevant screen.
- Handle network, server, authentication and storage errors with sensible retries.
- Follow **Provider + MVVM + Repository**, reusing the structure of the existing `flutter_provider_straterkit`.

## 2. Implementation status

| Area | Status | Notes |
|---|---|---|
| Splash, session restore, routing | Fully implemented | Token and expiry read from secure storage |
| Login | Fully implemented | `POST /token` |
| Registration | Fully implemented | `POST /register` (found by inspecting the live server, not in the brief) |
| Logout | Fully implemented | Local only, because the API has no revoke endpoint |
| Session expiry | Fully implemented | Expiry checked at startup; any authenticated 401/403 triggers a re-login dialog |
| Multi-file upload with progress | Fully implemented | Streamed from disk; never loaded fully into memory |
| Large files (over 50 MB) | Fully implemented | Verified with 55–60 MB files against the live server |
| Server file list, info, delete | Fully implemented | Loading, empty and error states |
| Download with progress | Fully implemented | |
| HTTP Range resumable download | Fully implemented | Pause/resume, auto-retry and app-restart resume all continue from the partial file |
| Safe file naming | Fully implemented | `name (1).ext`; existing files are never overwritten |
| Global transfer manager and dashboard | Fully implemented | Transfer center, details screen and app-wide progress bar |
| Transfer persistence and restore | Fully implemented | JSON history; interrupted downloads resume automatically on next launch |
| Android foreground service | Fully implemented | `dataSync` type, own isolate, survives swipe-away |
| Notifications and tap navigation | Fully implemented | Started, progress, paused, completed, failed |
| Retry with backoff | Fully implemented | Transient errors only; permanent errors fail immediately |
| Upload pause/resume | **Backend limitation** | The server only accepts a single multipart request, so uploads support *cancel* and *restart* only |
| iOS background transfers | **Platform limitation / not implemented** | See [iOS limitations](#16-ios-limitations) |
| Saving to public `Downloads` | **Not implemented** | Files are saved to app-specific external storage (see [Storage](#14-storage)) |

## 3. Technology stack

- Flutter 3.41 / Dart 3.11, Material 3
- **State management:** `provider` (`ChangeNotifier` ViewModels)
- **Networking:** `dio`, used for streamed multipart uploads, upload/download progress, cancellation and streamed Range responses
- **Background execution:** `flutter_foreground_task` (Android foreground service with its own Flutter engine)
- **Notifications:** `flutter_local_notifications`
- **Secure storage:** `flutter_secure_storage` (Android Keystore-backed)
- **Android:** minSdk 24, target/compile SDK 36

## 4. Architecture

### Provider + MVVM + Repository

```
View  ──▶  ViewModel  ──▶  Repository  ──▶  API service / transfer engine  ──▶  Backend
 ▲            │
 └── notifyListeners()
```

- **Views** (`lib/view`) render state and forward user intent. They never touch services directly.
- **ViewModels** (`lib/view_model`) hold presentation state, expose actions and return user-facing messages. They are context-free and unit-tested.
  - `AuthViewModel`: session, login, register and logout.
  - `ServerFilesViewModel`: server listing and deletion, as `ApiResponse<T>` (loading/completed/error).
  - `TransferViewModel`: an app-wide mirror of the transfer queue plus transfer controls, provided at the root.
- **Repositories** (`lib/repository`) are the only entry points to data. `AuthRepository`, `FileRepository` and `TransferRepository` take their dependencies through constructors so they can be tested.
- **Data layer** (`lib/data`):
  - `BaseApiServices` / `NetworkApiService`: a single Dio client with an auth interceptor and centralised exception mapping.
  - `TokenManager`: secure session storage.
  - `TransferManager`, `TransferStore`, `TransferTaskHandler`: the background transfer engine.

### Transfer flow across isolates

```
UI isolate                                          Foreground-service isolate (own FlutterEngine)
──────────                                          ──────────────────────────────────────────────
TransferViewModel                                    TransferTaskHandler
      │  pause / resume / retry / enqueue …               │
      ▼                                                    ▼
TransferRepository ── TransferCommand (JSON) ──▶   TransferManager ──▶ NetworkApiService (Dio) ──▶ API
      ▲                                                    │  queue · concurrency · retries
      └──── snapshot (throttled 500 ms) ◀──────────────────┤
                                                           ├──▶ TransferStore (transfers.json)
                                                           └──▶ NotificationService
```

- The service is running → commands are sent to it over the `flutter_foreground_task` data channel.
- The service is stopped → the repository applies the command to the persisted queue with a non-executing `TransferManager` (the same rules, so there is no duplicated logic). If that leaves pending work, it starts the service, which picks the queue up on start.
- The service stops itself 3 s after the queue becomes idle.

### Reuse of the starter kit

The project keeps the starter kit's conventions:
- Folder layout: `configs/`, `data/`, `model/`, `repository/`, `view/`, `view_model/`, `theme/`.
- `BaseApiServices` / `NetworkApiService` split, the `AppException` hierarchy, and `ApiResponse` + `Status`.
- `Routes` / `RoutesName` and the global `navigatorKey`.
- `AppColors` (static and context-aware colours), `AppTextStyles`, `AppTheme`, `RoundButton`, `CustomTextFormField`, Flushbar-based `Utils`.
- The splash and session-expired service patterns, and the bundled Poppins font.

Deliberate changes:
- **`http` → `dio`.** The starter kit's `MultipartFile.fromBytes` loads the entire file into memory and offers no progress, cancellation or streamed responses. All of these are required here.
- **Token storage moved to `flutter_secure_storage`.** The starter kit's `TokenManager` placeholder now holds the real implementation.
- File and folder names use correct snake_case spelling (`app_exceptions.dart`, `repository/`).
- Starter kit features unrelated to this assessment (sockets, maps, payments, localisation and so on) were not carried over.

## 5. Folder structure

```
lib/
├── configs/
│   ├── buttons/round_button.dart
│   ├── res/                         app_config, app_url, color, text_styles
│   ├── services/
│   │   ├── navigator_services/      navigatorKey + notification deep links
│   │   ├── notification_services/   per-transfer notifications
│   │   └── session_expired_services/
│   ├── utils/                       formatters, routes, utils (flushbar, confirm dialog)
│   ├── validations/auth_validation.dart
│   └── widgets/                     text field, empty/error states, transfer/* widgets
├── data/
│   ├── app_exceptions.dart
│   ├── network/                     base_api_services, network_api_service, token_manager
│   ├── response/                    api_response, status
│   └── transfer/                    transfer_manager, transfer_store, transfer_task_handler
├── model/                           user/session, server_file, transfer/{task, command}
├── repository/                      auth, file, transfer
├── theme/app_theme.dart
├── view/                            splash, auth, home, upload, download, transfers
├── view_model/                      auth, server_files, transfer
└── main.dart
test/                                unit + widget tests
integration_test/                    on-device test against the live API
```

## 6. API integration

Base URL: `http://108.136.142.112:90` (configured in `lib/configs/res/app_url.dart`). The response shapes below were captured from the live server, not assumed.

| Purpose | Request | Response used |
|---|---|---|
| Register | `POST /register` (form: `username`, `password`) | `201 {success, user, token, token_type, expires_in}` |
| Login | `POST /token` (form: `username`, `password`) | `200 {success, user, token, expires_in: 86400}` |
| List files | `GET /get` | `{files: [{id, name, original_name, size, type, uploaded_at, url}]}` |
| Upload | `POST /upload`, multipart field `file` | `201 {file: {name, url, …}}`; the server renames files to unique names |
| Download | `GET /get?file=NAME` (+ `Range: bytes=N-`) | `206` + `Content-Range`, `ETag`; `416` past the end |
| Delete | `DELETE /delete?file=NAME` | `200 {success, file}` |

Observed server rules:
- Usernames must be 3–32 characters from `[A-Za-z0-9_.-]`; passwords at least 6 characters.
- Uploads are restricted to an extension whitelist and anything else returns `415`. The whitelist is mirrored in `AppConfig.uploadExtensions` and enforced by the file picker.
- `HEAD` is not allowed.

### Authentication setup

There are no credentials in the code or the repository. Create an account on the **Create account** screen, or sign in with an existing one. The bearer token is attached by a Dio interceptor to every request except `/token` and `/register`.

## 7. Upload implementation

1. **Select files** opens the system picker (multi-select, filtered to the server whitelist). The picker copies each selection into the app cache and returns a real file path that the background isolate can stream.
2. Each file is validated: supported extension, non-empty, path available. Rejected files are listed to the user.
3. A `TransferTask` is queued, then `MultipartFile.fromFile` streams the file from disk inside the foreground service.
4. Progress comes from Dio's `onSendProgress`, scaled to the file size so multipart framing bytes are excluded.
5. The server's unique file name and URL are stored on the task as the **server file reference**.
6. The temporary picker copy is deleted after a successful upload, or when the entry is removed. Failed and cancelled uploads keep it so they can be restarted.

## 8. Download implementation

1. **Server files** lists the files with name, size, upload date and type icon, with pull-to-refresh and loading/empty/error states.
2. **Download** creates a task targeting `<downloads>/<original name>`. If that name is taken by an existing file or another queued download, it becomes `name (1).ext`, `name (2).ext`, and so on. Unsafe filename characters are replaced.
3. Data streams into `<target>.part`.
   - If the partial file exists, the request sends `Range: bytes=<length>-`.
   - `206` → append.
   - `200` (Range ignored) → restart from zero.
   - `416` → treat as complete if `Content-Range: */total` matches the local length; otherwise discard and restart.
4. When complete, `.part` is renamed to the final name. A short body (received < expected) is treated as an interruption and resumed.

## 9. Global transfer management

`TransferTask` stores: transfer ID, type, file name, local path, total and transferred bytes, status (`pending`, `running`, `paused`, `completed`, `failed`, `cancelled`), created and updated dates, error, server file reference, and remote URL.

- **Queue:** FIFO with up to 2 concurrent transfers (`AppConfig.maxConcurrentTransfers`).
- **Persistence:** atomic JSON writes (temp file + rename), serialised and throttled to 500 ms during progress. History is capped at 100 finished entries.
- **Restore:** on launch, interrupted downloads return to *pending* and resume automatically. Interrupted uploads are marked *failed — retry to upload again*, because the server cannot resume them.
- **UI:**
  - Home dashboard: live counts and recent transfers.
  - **Transfer center**: All / Active / Paused / Completed / Failed filters, plus clear-finished.
  - **Transfer details**: every field, with controls.
  - A persistent **active-transfers bar** under every screen, mounted via `MaterialApp.builder` so it doesn't depend on any route.
- **Lifecycle:** `TransferViewModel` refreshes when the app resumes and re-attaches to the running service.

## 10. Background execution strategy

| Option | Assessment |
|---|---|
| Plain Dio in the UI isolate | Stops when Android kills or destroys the activity. Not sufficient on its own |
| **WorkManager** | Built for deferrable work. The OS decides when it runs and long work can be stopped, so it does **not** guarantee continuous, user-visible transfers |
| **Foreground service (chosen)** | Android's sanctioned mechanism for long-running, user-initiated work with a visible notification |
| Native Kotlin `DownloadManager` / UIDT jobs | Robust, but `DownloadManager` can't attach bearer headers per request flexibly or do multipart uploads, and user-initiated data transfer jobs (UIDT, Android 14+) require native code. Listed as a future improvement |

**Implementation:**
- `flutter_foreground_task` starts a `dataSync` foreground service that creates its **own Flutter engine and isolate**. The `TransferManager` runs there.
- Transfers therefore continue when the app is minimised and also when it is swiped away from Recents (`stopWithTask` is off). This was verified on Android 15.
- Wake lock and Wi-Fi lock are held while the service runs.
- The service notification shows aggregate progress ("1 active · 45% · 2 queued").
- If the OS restarts the service (`START_STICKY`), or the app is relaunched after a kill, the persisted queue is restored and resumed.

## 11. Notifications

Centralised in `NotificationService`, shared by both isolates.

| Event | Notification |
|---|---|
| Started / progress | Ongoing, silent, progress bar (`transfer_progress` channel, low importance) |
| Paused | Non-ongoing "Download paused · N%" |
| Completed | Persistent "Upload/Download complete" (`transfer_results` channel, high importance) |
| Failed | "Upload/Download failed: reason" |
| Service | "Transferring files · N active · P%" (foreground-service channel) |

- **Throttling:** progress notifications update at most once per second per transfer, and only when the percentage changes. The UI snapshot is throttled to 500 ms.
- **Navigation:** tapping a transfer notification opens **Transfer details** for that transfer. This works both when the app is running and from a cold start, using the launch payload and a pending route consumed after the splash/session check. Tapping the service notification opens the app and, if the UI is already running, navigates to the **Transfer center** (this path was not verified on a device).
- **Permissions:** `POST_NOTIFICATIONS` is requested on Android 13+ before the first transfer starts. If it's denied, transfers still run, but notifications are hidden by the OS.

## 12. Pause, resume, retry and cancel

| Action | Upload | Download |
|---|---|---|
| Pause | **Not offered** (backend limitation) | Cancels the request and keeps `.part` |
| Resume | — | `Range` request from the partial length |
| Retry | Restarts the upload from 0% (labelled **Restart upload**) | Resumes from the partial file |
| Cancel | Aborts (with confirmation) | Aborts and deletes the partial file (with confirmation) |

A restarted upload is never presented as a resume.

## 13. Error handling and resilience

All failures become typed `AppException`s in `NetworkApiService`. Each one has a `retryable` flag.

| Condition | Message (example) | Retried automatically |
|---|---|---|
| No connection / connection dropped mid-transfer | "No internet connection…" / "The connection was interrupted…" | Yes |
| Timeout / stalled transfer (no bytes for 60 s) | "The connection timed out…" / "The transfer stalled…" | Yes |
| 5xx, 408, 429 | "Server is temporarily unavailable (503)…" | Yes |
| 401/403 with a token | Session-expired dialog → sign in again | No |
| 401 on login | Server message ("Invalid username or password") | No |
| 404 | "File not found" | No |
| 413 / 415 | "File is too large" / server whitelist message | No |
| Source file deleted | "The selected file is no longer available…" | No |
| Disk full (`ENOSPC`) | "Not enough storage space on this device." | No |
| Unexpected termination | Downloads resume on next launch; uploads are marked for retry | — |

Notes:
- **Backoff:** up to 5 automatic retries at 3, 6, 12, 24 and 48 s (about 1.5 minutes). For downloads, an attempt that made progress resets the budget, so a long download on a flaky link isn't abandoned while it keeps advancing. Permanent errors are never retried.
- **Stall detection:** Dio's `sendTimeout` covers the *entire* request body, which would abort large uploads on slow links. Instead, uploads use a progress watchdog and downloads use a per-chunk idle timeout (`AppConfig.transferIdleTimeout`).

## 14. Storage

- **Downloads:** app-specific external storage, `/storage/emulated/0/Android/data/<package>/files/Downloads/`. It needs no runtime permission on any Android version and can be reached over USB/MTP. The full path is shown on the details screen.
- **Transfer history:** `transfers.json` in the application support directory.
- **Session:** the token, username and expiry are kept in `flutter_secure_storage` (Android Keystore).
- **Picker copies:** kept in the app cache and deleted as described in [Upload implementation](#7-upload-implementation).

## 15. Android platform restrictions

- **Android 8+:** background services are restricted, so a foreground service with a visible notification is required. The service is started only from user actions or app launch, while the app is in the foreground.
- **Android 12+:** apps cannot start foreground services from the background. Auto-resume after a kill therefore happens the next time the user opens the app (or when the OS restarts the sticky service).
- **Android 13+:** the `POST_NOTIFICATIONS` runtime permission is required (requested). Users may still dismiss the service notification from the drawer.
- **Android 14+:** a declared `foregroundServiceType` plus the `FOREGROUND_SERVICE_DATA_SYNC` permission are required (both in the manifest).
- **Android 15+:** `dataSync` services may run for **6 hours in any 24-hour window**, and the timer resets when the user opens the app. On timeout the service is stopped: downloads stay resumable and uploads are marked for retry.
- **OEM battery managers** (Xiaomi, Huawei, Oppo and others) may still kill foreground services. Persistence and auto-resume limit the damage, but no app can fully prevent this.
- **Force stop** from Settings kills the service by design. Transfers resume on the next launch.
- **Cleartext HTTP:** the mock server is HTTP-only, so cleartext is allowed *only* for its host via `network_security_config.xml`.

## 16. iOS limitations

The iOS target was not built or tested, and background transfers are **not implemented** for iOS. iOS has no long-running foreground service equivalent: an app is suspended a few seconds after leaving the foreground. A production iOS version would need native code:

- A `URLSession` with a **background configuration** (`URLSessionConfiguration.background(withIdentifier:)`), so `nsurlsessiond` performs uploads/downloads while the app is suspended or terminated.
- Uploads from a file (`uploadTask(with:fromFile:)`), with the multipart body written to a temporary file first. Background sessions cannot stream from memory.
- `application(_:handleEventsForBackgroundURLSession:completionHandler:)` in the AppDelegate, a platform channel to report progress to Dart, and resume data (`cancel(byProducingResumeData:)`) for downloads.
- `UNUserNotificationCenter` permission for completion notifications.

## 17. Dependencies

| Package | Purpose |
|---|---|
| `provider` | State management (MVVM) |
| `dio` | HTTP client: streamed multipart, progress, cancellation, streamed Range downloads |
| `flutter_foreground_task` | Android foreground service with its own isolate and UI ⇄ service messaging |
| `flutter_local_notifications` | Per-transfer progress/result notifications and tap payloads |
| `flutter_secure_storage` | Encrypted token storage |
| `path_provider` | App support, cache and external storage directories |
| `file_picker` | System file picker (multi-select, extension filter) |
| `intl` | Date formatting |
| `another_flushbar` | In-app messages (same component as the starter kit) |
| `integration_test` *(dev)* | On-device end-to-end test |

## 18. Installation, running and building

Requirements: Flutter 3.41+ (Dart 3.11+), Android SDK 36, and an Android device or emulator running API 24+.

```bash
git clone https://github.com/akanto99/LaanTech_Pos_Task.git
cd LaanTech_Pos_Task
flutter pub get
flutter run                       # select an Android device/emulator
```

Build a debug APK:

```bash
flutter build apk --debug
# → build/app/outputs/flutter-apk/app-debug.apk
```

For a smaller APK on a single-ABI device or emulator: `flutter build apk --debug --target-platform android-arm64`.

## 19. Testing

```bash
flutter analyze
flutter test                      # 43 unit and widget tests
```

| Suite | Covers |
|---|---|
| `test/data/transfer_manager_test.dart` | Upload success/server reference, retry with backoff, retry limit, permanent errors, manual retry, no upload pause, download pause/resume from partial, cancel cleanup, safe naming, restore after crash, offline command application, history clearing, progress-reset retry budget, temp-copy cleanup |
| `test/data/network_api_service_test.dart` | Bearer header on protected endpoints only, status → exception mapping (401 session hook, 415, 503, 404), Range resume (206 append, 200 restart, 416 complete), mid-stream connection drop, missing upload source |
| `test/view_model/*` | `AuthViewModel` (login/register/logout/errors), `TransferViewModel` (snapshot mirroring, stats, upload selection, download enqueue, controls) |
| `test/repository/auth_repository_test.dart` | Form-encoded credentials, session persistence, logout |
| `test/view/*`, `test/widgets/*` | Splash routing (no/expired/valid session), login validation, `TransferTile` states and controls, cancel confirmation |

**Integration test (live server, Android device/emulator).** It logs in through the UI, uploads through the foreground service, downloads from the Server files screen, and compares the bytes. Use your own account; credentials are passed at run time and never stored:

```bash
flutter test integration_test/transfer_flow_test.dart -d <device-id> \
  --dart-define=TEST_USERNAME=<username> --dart-define=TEST_PASSWORD=<password>
```

It is skipped when no credentials are provided.

## 20. Verification performed

All of the following ran on an **Android 15 (API 35) emulator against the live mock server**:

- Splash → login → registration-backed account → Home. Wrong-password errors show the server message.
- Integration test passed: UI login, background upload, UI-triggered download, identical bytes.
- **55 MB upload** chosen in the system file picker completed while the app was minimised (server-reported size matched exactly).
- **60 MB download** went through all of the following and stayed byte-identical (SHA-1 match):
  - started from the UI;
  - continued with the app **minimised** and after it was **swiped away from Recents** (the Activity was destroyed, the service kept downloading);
  - **paused** (service stopped, partial kept) and **resumed** (Range append).
- Notifications showed progress, then "Download complete" and "Upload complete". Tapping a notification after swipe-away cold-started the app directly on **Transfer details**.
- **Airplane mode mid-download:** "No internet connection… Retrying in 12s (3/5)". After reconnecting, the transfer resumed from the partial file and the result was byte-identical.
- **Force-stop mid-download:** the partial file stayed frozen; on relaunch the download resumed automatically.
- Re-downloading an existing file saved it as `big60 (1).zip`; the original was untouched.
- **Logout with an active transfer:** confirmation shown, transfer cancelled, partial file deleted, service stopped.

Not verified on a physical device: OEM-specific battery killers, the Android 15 six-hour `dataSync` timeout, and session expiry on device (24 h token lifetime). Session-expiry handling is covered by unit tests.

## 21. Known limitations

- Upload pause/resume is not possible with this backend. Uploads restart from zero after cancellation or interruption.
- Downloads go to app-specific storage, not the public `Downloads` collection. On Android 11+ that folder is hidden from some file manager apps.
- The API has no token refresh or revoke. Sessions last 24 h, after which the user signs in again; background transfers that hit an expired token fail with a clear message.
- The integrity check compares the final size with `Content-Range`/`Content-Length`. The server's `ETag` is not used with `If-Range`, because server file names are unique and immutable.
- Transfer history is stored per device and cleared on logout.
- iOS background execution is not implemented.
- The Android application ID is still the template's `com.example.laantech_pos_task`.

## 22. Future improvements

- Android 14+ **user-initiated data transfer jobs** (native) as an alternative to the `dataSync` foreground service, avoiding the Android 15 six-hour limit.
- Resumable uploads (chunked or tus protocol), if the backend adds support.
- Saving completed downloads to public `Downloads` via `MediaStore`, plus "Open file" / share actions.
- Connectivity-aware scheduling (pause on network loss, resume on reconnect) and Wi-Fi-only mode for large files.
- Native iOS `URLSession` background transfers via a platform channel.
- Transfer speed and ETA display, plus checksum validation if the API exposes hashes.
