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
| Server files auto-reload after network loss | Fully implemented | Reloads on reconnect / app resume, with backoff when the network is up but the API is not yet reachable (see [Server files: automatic recovery](#server-files-automatic-recovery-after-network-loss)) |
| In-app video playback | Fully implemented | Authenticated HTTP Range streaming with a download-first fallback (see [Playing uploaded videos](#playing-uploaded-videos)) |
| Download with progress | Fully implemented | |
| HTTP Range resumable download | Fully implemented | Pause/resume, auto-retry and app-restart resume all continue from the partial file |
| Safe file naming | Fully implemented | `name (1).ext`; existing files are never overwritten |
| Global transfer manager and dashboard | Fully implemented | Transfer center, details screen and app-wide progress bar |
| Transfer persistence and restore | Fully implemented | JSON history; interrupted downloads resume automatically on next launch |
| Android foreground service | Fully implemented | `dataSync` type, own isolate, survives swipe-away |
| Notifications and tap navigation | Fully implemented | Started, progress, paused, completed, failed |
| Retry with backoff | Fully implemented | Transient errors only; permanent errors fail immediately |
| Network health monitoring and recovery | Fully implemented | Four labels only (Good Connection, Poor Connection, Reconnecting, Connection Lost) with matching progress colors on every transfer screen and in notifications; a transfer is retried as soon as the network returns (see [Network health and transfer recovery](#network-health-and-transfer-recovery)) |
| Responsive UI | Fully implemented | The project's `ResPonsiveUi` and `SizedboxSpaccing` utilities on every screen; overflow-audited on 9 screen configurations (see [Responsive UI and spacing](#responsive-ui-and-spacing)) |
| Upload pause/resume | **Backend limitation** | The server only accepts a single multipart request, so uploads support *cancel* and *restart* only |
| iOS background transfers | **Platform limitation / not implemented** | See [iOS limitations](#16-ios-limitations) |
| Saving to public `Download/LaanTech` | Fully implemented | MediaStore on Android 10+, legacy shared storage on Android 7–9 (see [Storage](#14-storage)) |

## 3. Technology stack

- Flutter 3.41 / Dart 3.11, Material 3
- **State management:** `provider` (`ChangeNotifier` ViewModels)
- **Networking:** `dio`, used for streamed multipart uploads, upload/download progress, cancellation and streamed Range responses
- **Background execution:** `flutter_foreground_task` (Android foreground service with its own Flutter engine)
- **Notifications:** `flutter_local_notifications`
- **Secure storage:** `flutter_secure_storage` (Android Keystore-backed)
- **Public downloads:** local `public_downloads` plugin (Kotlin, `MediaStore.Downloads`)
- **Connectivity:** `connectivity_plus`
- **Video:** `video_player` (ExoPlayer / Media3 on Android)
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

### Responsive UI and spacing

The app uses the project's own responsive utilities; no second system was added.

- **`lib/configs/responsive/responsive_ui.dart` (`ResPonsiveUi`).** Breakpoints (`isMobile` below 800 dp, `isTablet`, `isDesktop`) and the `mobile` / `tablet` / `desktop` builder.
  - **Every screen body goes through that builder** via `ResPonsiveUi.body(child: …)`: full width on phones, a centered 720 dp column on tablets and 960 dp on desktop. The app bar and the persistent transfer bar stay full width.
  - Screens: splash, login and register (through `AuthFormLayout`, which also keeps the form at 440 dp), Home, Upload, Server files, Transfer center, Transfer details, and the video player's loading and error states. The video surface itself stays full screen.
  - Dialogs (`Utils.confirm`, session expired) use `ResPonsiveUi.dialogInsets` instead of Material's fixed 40 dp insets. The app has no bottom sheets. It also provides screen-fraction helpers: `width(context, f)`, `height(context, f)`, `padding(context, horizontal:, vertical:)`, `paddingLTRB(...)`, `pagePadding` (about 16 dp on a 393 × 852 phone) and `cardPadding` (about 20 dp).
- **`lib/configs/res/sizedbox_spaccing.dart` (`SizedboxSpaccing`).** Gaps as a fraction of the screen: `width01` to `width035` follow the width, and `height005` to `height04` follow the height.
- **Rule.** Horizontal values scale with the screen width and vertical values with the screen height.
  - Both read `MediaQuery.sizeOf`, so opening the keyboard doesn't rebuild them.
  - The existing pixel values were mapped to the closest step on a 393 × 852 phone (8 → `height01`, 16 → `height02`, 12 → `width03`, …). The design looks the same there and scales on smaller and larger screens.
- **Text is not scaled by screen size.** It comes from the theme and respects the user's Android font size; layouts were made to tolerate large text instead.
- **Deliberately fixed values:**
  - icon sizes, corner radii, stroke widths and the progress-bar thickness;
  - chip padding, icon-badge padding, and the spinner slot that matches a 48 dp button;
  - the theme's text-field padding and the 440 dp maximum width of the login/register form.
- **Layout bugs fixed** (found by the audit below):
  - button labels shrink to fit instead of overflowing (`RoundButton`, up to 76 px);
  - a transfer's status chip and size wrap onto two lines instead of overflowing (`TransferTile`, up to 127 px);
  - dashboard tiles grow with the text size, and their titles and stats stay on one line;
  - empty and error states scroll on short screens.
- **Audit.** `test/view/responsive_layout_test.dart` renders every screen with long realistic content. It fails on any overflow, if a screen body doesn't use `ResPonsiveUi`, or if a card is wider than the tablet/desktop content column:
  - **Screens:** splash, login, register, dashboard, Upload (with and without transfers), Server files (list, empty, error), Transfer center, Transfer details (running, failed, video), the video player (loading, error), the confirmation and session-expired dialogs, and the persistent transfer bar.
  - **10 configurations:** 320 × 568 (also at 1.3× text), 393 × 852, 430 × 932 (also at 1.5× text), 852 × 393 landscape (also at 1.3× text), 568 × 320 landscape, an 800 × 1280 tablet and a 1280 × 800 desktop / large tablet, at densities from 1.5× to 3.5×.

## 5. Folder structure

```
lib/
├── configs/
│   ├── buttons/round_button.dart
│   ├── res/                         app_config, app_url, color, text_styles
│   ├── services/
│   │   ├── connectivity_services/   online/offline changes (connectivity_plus)
│   │   ├── navigator_services/      navigatorKey + notification deep links
│   │   ├── notification_services/   per-transfer notifications
│   │   └── session_expired_services/
│   ├── utils/                       file_names, formatters, routes, utils (flushbar, confirm dialog)
│   ├── validations/auth_validation.dart
│   └── widgets/                     text field, empty/error states, transfer/* widgets
├── data/
│   ├── app_exceptions.dart
│   ├── network/                     base_api_services, network_api_service, token_manager
│   ├── response/                    api_response, status
│   ├── storage/                     base_download_storage, public_download_storage
│   └── transfer/                    transfer_manager, transfer_store, transfer_task_handler
├── model/                           user/session, server_file, transfer/{task, command}, video/{source, args}
├── repository/                      auth, file, transfer, video
├── theme/app_theme.dart
├── view/                            splash, auth, home, upload, download, transfers, video_player
├── view_model/                      auth, server_files, transfer, video_player
└── main.dart
packages/public_downloads/           local Android plugin: MediaStore / legacy public Downloads
test/                                unit + widget tests
integration_test/                    on-device tests (live API flow, public Downloads)
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
2. **Download** creates a task whose working file is in app-private staging (`<app support>/download_staging/<original name>`). If another queued download already uses that name, it becomes `name (1).ext` so two downloads never share a partial file. Unsafe filename characters are replaced. On Android 7–9 the storage permission is requested at this point (see below).
3. Data streams into `<staging file>.part`.
   - If the partial file exists, the request sends `Range: bytes=<length>-`.
   - `206` → append.
   - `200` (Range ignored) → restart from zero.
   - `416` → treat as complete if `Content-Range: */total` matches the local length; otherwise discard and restart.
4. A short body (received < expected) is treated as an interruption and resumed.
5. Only a **complete** file is published to `Download/LaanTech/` (see next section) and the staging copy is deleted. The task's local path becomes the public path, e.g. `/storage/emulated/0/Download/LaanTech/products.csv`.

### Saving to Download/LaanTech

Completed downloads are saved in the public **`Internal storage/Download/LaanTech/`** folder, visible in the Files app and over USB. The folder name is `AppConfig.publicDownloadFolder`.

Downloads finish inside the foreground-service isolate, which has its own Flutter engine. A `MethodChannel` registered in `MainActivity` would not exist there, so the native code is a small **local Flutter plugin** (`packages/public_downloads`), which Flutter registers in every engine. The data layer reaches it through `BaseDownloadStorage` → `PublicDownloadStorage`, injected into `TransferManager` (tests use a fake).

| Android | Mechanism | Permission |
|---|---|---|
| 10+ (API 29+) | `MediaStore.Downloads` insert with `RELATIVE_PATH = Download/LaanTech/` and `IS_PENDING = 1` while copying, then `IS_PENDING = 0` | **None** |
| 7–9 (API 24–28) | Copy to the public Downloads directory through a hidden `.name.pending` file, rename, then media scan | `WRITE_EXTERNAL_STORAGE`, declared with `maxSdkVersion="28"` and requested when a download starts |

- **No partial files are exposed.** Partial data lives only in app-private staging; MediaStore keeps the entry pending (hidden) until the copy finishes, and a failed copy deletes the entry.
- **No overwriting.** A taken name becomes `name (1).ext`, `name (2).ext`, … Files owned by other apps (or a previous install) are not visible to the app on Android 11+, so MediaStore's own unique-name handling is the safety net, and the name MediaStore actually used is read back and stored. Original names and extensions are kept; MIME types come from the extension.
- **Errors:** missing permission, full disk (`ENOSPC`) and I/O errors become `StorageException`s with clear messages. A failed save keeps the complete partial file, so **Retry** publishes it again without re-downloading (the Range request for a complete file returns `416`).
- `MANAGE_EXTERNAL_STORAGE` is **not** requested.
- Publishing copies the file, so a download needs free space for two copies for a moment.

### Playing uploaded videos

Tapping a finished video transfer (Upload screen or Transfer center), the **Play video** button on Transfer details, or a video on the **Server files** screen opens a dedicated player (`VideoPlayerView` → `VideoPlayerViewModel` → `VideoRepository`). Videos are recognised by `AppConfig.videoExtensions` (mp4, mov, mkv, webm, avi) or a `video/*` server type. On video tiles the details screen is one tap away through the ⓘ button.

1. **Probe:** `VideoRepository.streamSource` sends `Range: bytes=0-1` through the shared Dio client. The Bearer interceptor, error mapping and session-expired flow all apply.
2. **Stream (preferred):** on `206` + `Content-Range`, the server URL is opened with `VideoPlayerController.networkUrl(..., httpHeaders: {Authorization: Bearer …})`. The token is sent **only as a header**: it is never put in the URL and never logged. ExoPlayer then fetches with HTTP Range requests, so seeking (and MP4s whose index is at the end) work without downloading the whole file.
3. **Download-first fallback:** if the server does not answer Range requests, or the stream fails to initialise, the file is downloaded with the same resumable `downloadFileApi` into `<cache>/video_playback/` with a progress bar, then played from disk. The copy is deleted when the player closes, and leaving the screen cancels the download.
4. **Errors:** an expired session shows the usual message and re-login dialog. If neither source can be played, the screen says the format or codec is not supported, with a Retry button. A failure mid-playback (e.g. lost connection) shows an error with Retry.

Player controls: play/pause (replay at the end), a seek slider with the buffered range, current position and duration, fullscreen (immersive, rotates to landscape for wide videos and stays portrait for tall ones; Back leaves fullscreen first) and a buffering indicator. Controls auto-hide while playing. The controller, timers and any fallback download are released when the screen closes.

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
| Paused | Non-ongoing "Download paused" · "file · N%", ending in "· Connection Lost" when the network stayed down too long |
| Network state (running) | Same notification, updated in place. The title is "Uploading…" / "Downloading…" on a good connection, otherwise the network label ("Poor Connection", "Reconnecting", "Connection Lost"). The body is "file · N% · speed" |
| Completed | Persistent "Upload/Download complete" (`transfer_results` channel, high importance) |
| Failed | "Upload/Download failed: reason" |
| Service | "Transferring files · N active · P%", plus the network label (Poor Connection / Reconnecting / Connection Lost) when relevant (foreground-service channel) |

- **Throttling:** progress notifications update at most once per second per transfer, and only when the percentage changes; a change of network state updates immediately. Each transfer keeps a single notification id, so state changes never create duplicates. The UI snapshot is throttled to 500 ms.
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
| No connection / connection dropped mid-transfer | "No internet connection…" / "The connection was interrupted…" (`NetworkException`) | Yes, as soon as the network returns |
| Timeout / stalled transfer (no bytes for 60 s) | "The connection timed out…" / "The transfer stalled…" (`NetworkException`) | Yes |
| 5xx, 408, 429 | "Server is temporarily unavailable (503)…" | Yes |
| 401/403 with a token | Session-expired dialog → sign in again | No |
| 401 on login | Server message ("Invalid username or password") | No |
| 404 | "File not found" | No |
| 413 / 415 | "File is too large" / server whitelist message | No |
| Source file deleted | "The selected file is no longer available…" | No |
| Disk full (`ENOSPC`) | "Not enough storage space on this device." | No |
| Unexpected termination | Downloads resume on next launch; uploads are marked for retry | — |

Notes:
- **Backoff:** up to 5 automatic retries at 3, 6, 12, 24 and 48 s (capped at 60 s). For downloads, an attempt that made progress resets the budget, so a long download on a flaky link isn't abandoned while it keeps advancing. Failures caused by losing the network do not use the budget at all (see below). Permanent errors are never retried.
- **Stall detection:** Dio's `sendTimeout` covers the *entire* request body, which would abort large uploads on slow links. Instead, uploads use a progress watchdog and downloads use a per-chunk idle timeout (`AppConfig.transferIdleTimeout`).

### Network health and transfer recovery

A slow network, a stalled transfer and a lost connection are different situations, so they are detected and shown separately. A slow but working connection never pauses a transfer.

**Design.** The measurement happens where the bytes move, in the transfer engine inside the foreground-service isolate, never in widgets:

| Piece | Role |
|---|---|
| `NetworkHealth` (`model/transfer/network_health.dart`) | `good`, `resumed`, `poor`, `stalled`, `reconnecting`, `offline`, ordered by severity, plus the one shared `label` |
| `ThroughputTracker` (`data/transfer/`) | Per attempt: real bytes over elapsed time → speed and good / poor / stalled; whether any byte moved |
| `TransferNetworkMonitor` (`data/transfer/`) | The isolate's **only** connectivity listener (`ConnectivityService` / `connectivity_plus`); `whenOnline()` and `nextChange()` for event-driven waits |
| `TransferManager` | Waits, retries and resumes; writes `networkHealth` and `bytesPerSecond` onto the `TransferTask` |

The health and speed travel with each task in the existing snapshots, so the Upload screen, Server files, Transfer center, Home, Transfer details, the app-wide bar and the notifications all show the same state from one source. Progress (`transferredBytes`) is a separate field and is never changed by health. Colors are visual only and never affect the transfer.

**Network status UI.** Only four labels exist, shown as one small line under the progress bar (icon, label and speed while data moves), with no explanatory sentences or banners:

| Label | Internal states | Progress bar | Speed |
|---|---|---|---|
| Good Connection | `good`, `resumed` | Normal color | "1.2 MB/s" |
| Poor Connection | `poor`, `stalled` | Amber | "10.0 KB/s" (hidden when stalled) |
| Reconnecting | `reconnecting` (retrying; no data yet) | Amber | — |
| Connection Lost | `offline` | Red | — |

Paused, failed and finished transfers show no network line; the status chip and the existing message cover them. The percentage and the pause / resume / retry / cancel controls are unchanged.

**Poor network detection.**
- On every 1 s tick, the speed is the bytes moved over a sliding 8 s window, measured up to *now*, so it falls when data stops instead of freezing at its last value.
- Below 32 KiB/s the connection is *poor*. It must climb back above 64 KiB/s to count as *good* again, so the label doesn't flicker.
- The first 3 s of an attempt are not classified, because of TCP slow start and the burst into the socket buffer.
- No new bytes for 10 s while online counts as *stalled*. An upload that has sent everything and is waiting for the server's reply is not a stall.
- A task is only updated when its state changes or its speed moves by more than 10%.
- The thresholds are in `AppConfig`.

**Connection loss detection.**
- When `connectivity_plus` reports no network, running transfers show *Connection Lost* immediately.
- **While still offline,** the request is aborted only if its data has also stopped for 10 s. A brief blip that doesn't stop the data doesn't kill the transfer.
- **When the network returns,** a request that was in flight during the loss is treated as dead once it receives nothing for 3 s (`AppConfig.reconnectStallAfter`). It is aborted and resumed at once instead of hanging until the 60 s idle timeout.
  - A few buffered bytes may still arrive after the loss, so "nothing since the loss" isn't a reliable test; the emulator showed exactly that.
- A socket error, timeout or stall mid-transfer is a `NetworkException`, unlike a 5xx, which is a server error.

**Automatic retry strategy.**
1. While the device is offline, nothing is sent. The wait is event driven: no polling, no probes.
2. When connectivity returns, the transfer is retried **immediately**, showing *Reconnecting* until its first bytes arrive. The retried request is itself the reachability check: a Range request costs no more than a probe.
3. A connection that was delivering data is retried at once. Only consecutive failures that move no data back off (3 s, 6 s, 12 s … capped at 60 s), so an unreachable server isn't hammered. Any connectivity change ends a backoff early, so a reconnection is never slept through.
4. Network failures don't use up the retry budget for downloads, which resume. An upload that keeps dropping while online does use it (5 attempts), because each retry re-sends the whole file. Server errors (5xx/408/429) keep the existing 5-attempt budget.
5. If the network stays unusable for 30 minutes, a download is **paused** ("Paused: connection lost.", resumable later) and an upload **fails** ("Connection lost. Retry to upload again."). The foreground service then stops instead of running indefinitely.
6. Each transfer has one run loop. Pausing and resuming (or retrying) while a transfer waits for the network can never produce two requests for the same transfer.

**Upload resumability (backend limitation).** The live server was probed (unauthenticated requests only, observing the routes):
- `OPTIONS /upload` returns `Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS`, and `Access-Control-Allow-Headers` lists only `Authorization, Content-Type`. That means no `Content-Range`, `Upload-Offset` or `Tus-Resumable` headers.
- `PUT /upload` and `PATCH /upload` return `405`.
- `/upload/init`, `/upload/chunk`, `/upload/session`, `/chunk`, `/resumable`, `/tus`, `/files/upload`, `/api`, `/docs`, `/swagger.json` and `/openapi.json` return `404`.
- `POST /upload` accepts only one complete multipart body.

So there are no upload sessions, no chunk endpoint and no byte-offset continuation. **An upload cannot resume from 80%: it restarts from 0%, and the app shows exactly that.** True resume needs a backend change: for example a tus endpoint, or `POST /upload/session` → `PUT` chunks with `Content-Range` → a query for the confirmed offset. The app's transfer engine already persists what a resume would need (task, size, last progress).

What the app does instead:
- While waiting for the network, the last progress stays on screen. When the network returns, the bar visibly starts again from 0%; it never jumps back to 80%.
- Bytes written to the socket are not bytes the server has accepted, so the bar stops at **99%** until the server's response confirms the upload.
- **No duplicate server files:** if a previous attempt had sent the whole body but the response was lost, the retry first lists the server files. It adopts an existing file instead of uploading again when:
  - the file has the same original name and size;
  - it was uploaded since that attempt, allowing 2 minutes for clock differences;
  - no other transfer already refers to it.
- Retries are bounded (see the retry strategy above), and pause stays disabled for uploads.

**Download Range support and fallback.** The server answers `Range` with `206` + `Content-Range` and sends an `ETag`. A resumed download:
- sends `Range: bytes=<partial length>-` and, when the stored `ETag` is strong, `If-Range`;
- **appends only if** the response is `206` *and* `Content-Range` starts exactly at the partial length *and* the `ETag` is unchanged. Otherwise the partial file is discarded and the download restarts cleanly, so data from two versions is never mixed;
- `200` (Range ignored) → restart from zero, overwriting the partial file. `416` → complete if `Content-Range: */total` matches;
- partial data stays in private staging; only a complete file is published to `Download/LaanTech` (see [Saving to Download/LaanTech](#saving-to-downloadlaantech)).

Duplicate downloads are prevented in the engine (the same server file cannot be queued twice while one is queued, running or paused) and in the UI.

**Android background limitations.** All of this runs in the `dataSync` foreground service, so it keeps working with the app minimised or swiped away. The connectivity listener lives in the service's own engine. While the transfer waits for the network, the service stays alive, but no longer than the 30-minute limit above. Doze, OEM battery managers and the Android 15 six-hour `dataSync` budget (see [Android platform restrictions](#15-android-platform-restrictions)) still apply. If the service is stopped while a download waits, the partial file is kept and resumes on the next start.

### Download resume after reconnection: regression investigation

**Symptom.** After the network-health work (`4f66d9a`), downloads took noticeably longer to resume after the connection returned.

**Method.**
- `4cc1b72` is the commit just before network monitoring and progress colors were added. I compared it with `4f66d9a`.
- I measured both on the Android 15 emulator with the same harness: a 40 MB download from a local Range/`ETag` server throttled to 700 KB/s.
- The script switched Wi-Fi and mobile data off for 4 s, 20 s and 8 s.
- Latency is measured from Android's "online" event to the first new bytes.

| Outage | `4cc1b72` (before) | `4f66d9a` (regression) | Fixed (`cb9bedc`) |
|---|---|---|---|
| 4 s | 5.1 s | 0.04 s | 0.25 s |
| 20 s | 0.96 s | 0.09 s | 0.24 s |
| 8 s | **32.9 s** | **32.9 s** | **3.5 s** |

**Root causes.**
1. **A dead connection was never abandoned when the network came back.**
   - During a short outage, the request was not aborted, because the offline abort needs 10 s without data.
   - After reconnection it sat "stalled" until the socket finally errored (about 30 s on the emulator, up to the 60 s idle timeout on a device).
   - This existed before too. The new connection-loss abort only covered outages longer than 10 s, and a few buffered bytes arriving after the loss defeated a "nothing received since the loss" test.
2. **`4f66d9a` put extra steps between reconnection and the Range request:**
   - a `HEAD` reachability probe (up to 8 s each) that backed off 3 s → 6 s → 12 s … 60 s when it failed;
   - a 3 s retry backoff that ignored connectivity events, applied when the socket error arrived before the "offline" event.

   On a phone, a probe that fails right after reconnecting (network not routable yet) adds 3–20 s or more. The emulator runs didn't hit this path, but it is a real delay source on a device.

**Fix (keeps the network status UI and monitoring).**
- A request that crossed a connectivity loss and stays idle for 3 s once the device is online is aborted and resumed with Range straight away.
- The probe is gone: the retried Range request is the reachability check.
- Only consecutive failures that move no data back off, and a connectivity change ends any backoff.

What was verified:
- the partial file and byte offset are preserved: the server logs show `Range: bytes=<partial length>-` with `If-Range`;
- `206`, `Content-Range` and the `ETag` are still validated before appending;
- the same file still can't be downloaded twice at once;
- completed files still go to `Download/LaanTech`.

### Server files: automatic recovery after network loss

If Server files was opened offline, it used to stay on "No internet connection" until the user tapped Retry. Now `ServerFilesViewModel`:

- listens to `ConnectivityService` (`connectivity_plus`), which emits only real online/offline flips, and **reloads automatically when the connection returns** if it is showing a network-type error. A list loaded before the outage is refreshed in the background and kept if that refresh fails;
- also re-checks when the app returns to the foreground, because connectivity events can be missed in the background;
- treats connectivity as a hint, not proof. "Connected" does not mean the API is reachable (DNS still settling, captive portal, server down), so a reload that still fails with a retryable error is retried after 2, 5 and 10 s (`AppConfig.reconnectRetryDelays`) and then waits for the user or the next reconnect. Nothing polls while the device is offline, and permanent errors (4xx) are not retried;
- shares a single in-flight request between Retry, pull-to-refresh, reconnect and the retry timer, so requests are never duplicated;
- cancels the connectivity subscription, retry timer and lifecycle observer in `dispose()`. The view model belongs to the screen, so leaving and reopening Server files starts cleanly, and a request that finishes after the screen closed is ignored.

The error view tells the user the list will reload automatically.

## 14. Storage

- **Downloads:** public `Download/LaanTech/` (`/storage/emulated/0/Download/LaanTech/`), see [Saving to Download/LaanTech](#saving-to-downloadlaantech). The full path is shown on the details screen. Files stay there when a transfer is removed from history or the app is uninstalled.
- **Partial downloads:** app-private `<app support>/download_staging/`, invisible to other apps and deleted after publishing or cancelling. Downloads that were already paused before this change keep their old staging path and are still published to `Download/LaanTech` when they finish.
- **Video fallback copies:** `<cache>/video_playback/`, deleted when the player closes.
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
- **Scoped storage (Android 10+):** downloads are written through `MediaStore.Downloads`, which needs no storage permission. The app cannot see files other apps put in `Download/LaanTech`; MediaStore still gives new files unique names, so nothing is overwritten.
- **Android 7–9:** `WRITE_EXTERNAL_STORAGE` (`maxSdkVersion="28"`) is requested from the UI when a download starts, because the background service has no Activity to ask from. If it is denied, the download is not queued and a message explains why.
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
| `connectivity_plus` | Online/offline changes for automatic Server files recovery |
| `video_player` | In-app playback (ExoPlayer on Android) with custom HTTP headers for the Bearer token |
| `public_downloads` *(local, `packages/`)* | Kotlin plugin for `MediaStore.Downloads` / legacy public Downloads. Written in-repo: it has to be a plugin to run in the service engine, and pub.dev options such as `media_store_plus` replace existing files with the same name |
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
flutter test                      # 275 unit and widget tests
```

| Suite | Covers |
|---|---|
| `test/data/transfer_manager_test.dart` | Upload success/server reference, retry with backoff, retry limit, permanent errors, manual retry, no upload pause, download pause/resume from partial, cancel cleanup, safe naming (staging and public), partial data kept out of the public folder, failed save → retry publishes without re-downloading, restore after crash, offline command application, history clearing, progress-reset retry budget, temp-copy cleanup |
| `test/data/network_api_service_test.dart` | Bearer header on protected endpoints only, status → exception mapping (401 session hook, 415, 503, 404), Range resume (206 append, 200 restart, 416 complete), Range-support probe, mid-stream connection drop, missing upload source, **206 with a wrong start or no `Content-Range` is never appended, changed `ETag` discards the partial file, `If-Range` only with strong `ETag`s, network vs server errors** |
| `test/data/transfer_recovery_test.dart` | Real `TransferManager` + `TransferNetworkMonitor` with scripted connectivity: nothing sent while offline and the request sent as soon as the network returns (no probe, no backoff), backoff only for failures that move no data and cut short by a network change, **a dead request after a short outage is aborted on reconnection and resumed from its byte offset (buffered bytes after the loss included)**, a blip that doesn't stop the data is left alone, no explanatory messages stored, upload progress held at 99% until the server confirms, connection lost mid-download keeps progress and resumes from the partial file (progress never goes backwards), connection lost mid-upload keeps progress while waiting then restarts from 0, lost upload response adopts the server copy (no duplicate) or uploads again when there is none, pause/resume while waiting never sends two requests, offline failures don't use the retry budget, give-up pauses downloads / fails uploads, duplicate download enqueue ignored |
| `test/data/throughput_tracker_test.dart`, `transfer_network_monitor_test.dart` | Good / poor / stalled classification, warm-up, hysteresis, decay when data stops, awaiting-response is not a stall, resumed notice; single connectivity listener, `nextChange` (also released on dispose), missing plugin fallback |
| `test/view_model/*` | `AuthViewModel` (login/register/logout/errors), `TransferViewModel` (snapshot mirroring, stats, upload selection, download enqueue, controls), `ServerFilesViewModel` (reload on reconnect, no polling offline, backoff when connected but unreachable, retry budget, no retry for 4xx, single in-flight request, silent refresh keeps data, dispose cleanup), `VideoPlayerViewModel` (authenticated stream, download-first when Range is unsupported or the stream fails, unsupported format, session errors, progress, dispose) |
| `test/repository/*` | `AuthRepository` (form-encoded credentials, session persistence, logout), `VideoRepository` (token only in headers, no-Range fallback, missing session, cached fallback copy) |
| `test/view/*`, `test/widgets/*` | Splash routing (no/expired/valid session), login validation, `TransferTile` states and controls, cancel confirmation, video tap → player, details button, non-video tap → details, **only the four network labels, progress color per label (normal / amber / red), compact KB/s and MB/s speed, percentage unchanged by health, the same labels in notifications** |
| `test/view/responsive_layout_test.dart` | Every screen (splash, login, register, dashboard, upload, server files list/empty/error, transfer center, transfer details running/failed/video, video player loading/error, confirm and session-expired dialogs, persistent bar) on 10 screen configurations; fails on any overflow, on a body not built with `ResPonsiveUi`, or on a card wider than the tablet/desktop column |

**Integration test (live server, Android device/emulator).** It logs in through the UI, uploads through the foreground service, downloads from the Server files screen, and compares the bytes. Use your own account; credentials are passed at run time and never stored:

```bash
flutter test integration_test/transfer_flow_test.dart -d <device-id> \
  --dart-define=TEST_USERNAME=<username> --dart-define=TEST_PASSWORD=<password>
```

It is skipped when no credentials are provided.

**Public Downloads test (any Android device/emulator, no account needed).** Publishes through the real plugin and checks `Download/LaanTech/` paths and conflict naming:

```bash
flutter test integration_test/public_download_storage_test.dart -d <device-id>
adb shell ls /sdcard/Download/LaanTech      # the test files are left there to inspect
```

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

**Public storage, network recovery and video playback** (Android 15 / API 35 emulator):

- `public_download_storage_test.dart` passed. Checked with `adb`, the files are in `/sdcard/Download/LaanTech/`, a second file with the same name became `… (1).csv` with the first untouched, and MediaStore lists both with `relative_path=Download/LaanTech/`, `is_pending=0` and `mime_type=text/comma-separated-values`. No storage permission was granted.
- `ConnectivityService` on the emulator: turning Wi-Fi and mobile data off and on emitted `false` then `true`.
- Authenticated playback against a local server that requires `Authorization: Bearer …` and serves Range requests (the live server needs an account, see below). The Range probe passed. ExoPlayer sent the Bearer header on **every** request and used Range requests to read the MP4 index and to seek (`bytes=12739086-`, `bytes=3232-`, …). Playback and a seek to 2.5 s worked. The same request without the header was rejected (401). The download-first fallback file played from disk.
- `flutter analyze`: no issues. `flutter test`: 69 passed (102 after the network health work). `flutter build apk --debug`: success.

**Network health and recovery, first run** (commit `4f66d9a`, before the UI was reduced to four labels; Android 15 / API 35 emulator; real `TransferManager`, `TransferNetworkMonitor`, `connectivity_plus`, Dio, MediaStore storage and notifications; requests redirected to a local server that implements the same Range/`ETag` behaviour with a controllable rate, because the live server needs an account; Wi-Fi and mobile data switched off and on with `adb shell svc`):

| Step | Observed |
|---|---|
| 40 MB download at 2 MB/s | *good*; notification "Downloading… · 17% · 1.3 MB/s" |
| Server slowed to 12 KB/s | *poor* after the window filled (measured 11 KB/s); notification "Poor network connection · 22% · 10.8 KB/s"; download kept running |
| Wi-Fi + data off | *Connection lost*, progress held at 9,371,648 bytes (22%); notification "Waiting for network"; no requests sent |
| Network on | *Reconnecting* → reachability `HEAD` → *Resumed*; server log `Range: bytes=9371648-` with `If-Range: "<etag>"`; notification "Resuming download…" → *good* at 1.5 MB/s |
| Completion | Published to `/sdcard/Download/LaanTech/`; SHA-1 identical to the server file |
| 12 MB upload, network off mid-way | *Connection lost* with progress held at 9%, message says it will restart from the beginning; on reconnect "Restarting upload…" from 0% → completed |

One finding from this run is recorded under [Known limitations](#21-known-limitations): upload throughput is measured at the socket.

**Reconnection speed** (Android 15 emulator, same harness on `4cc1b72`, `4f66d9a` and the fix): see the table in [Download resume after reconnection](#download-resume-after-reconnection-regression-investigation).

**Interruptions at 20%, 50% and 80%.** This was the current code on the Android 15 emulator, with a local server at 700 KB/s. The controller watched real progress and switched Wi-Fi and mobile data off when each threshold was crossed: 5 s at 20%, 15 s at 50% and 8 s at 80%.

| Transfer | Observed |
|---|---|
| 40 MB download | *Connection Lost* (red) at each outage, progress held. *Reconnecting* when the network returned, then data again after **0.37 s** (20%), **0.25 s** (50%) and **3.8 s** (80%: a dead connection, detected after 3 s). Every resume was a `Range: bytes=<partial>-` request with `If-Range`. The completed file landed in `/sdcard/Download/LaanTech/` with SHA-1 `f9f4c124…`, identical to the server file. |
| 30 MB upload | *Connection Lost* at each outage, last progress held. On reconnect it restarted from 0% (shown as such), with data again within 0.18–0.43 s. Completed, and the server stored it **exactly once** (one `POST complete` despite five attempts). |
| Android network handover | Two upload attempts were also reset with no outage, each about 34 s after reconnecting. Logcat shows `handleLingerComplete for [CELLULAR]` at exactly those times. Mobile data came back first, the upload started on it, then Android switched to Wi-Fi and tore mobile down after its 30 s linger, destroying the socket. The app recovered at once (in under 0.3 s); see [Known limitations](#21-known-limitations). |

**Responsive layout.** The audit in [Responsive UI and spacing](#responsive-ui-and-spacing) passes: 170 renders (17 screens and states × 10 configurations), with no overflow, every body through `ResPonsiveUi` and no card wider than the content column. Layout was verified by widget tests, not by screenshots on physical phones.

**Final checks:** `flutter pub get`, `flutter analyze` (no issues), `flutter test` (275 passed) and `flutter build apk --debug` (success).

**Still to test manually on a device, with a real account on the live server:**

1. Download an image, a video and a CSV from Server files → the Files app shows them in `Download/LaanTech/`. Downloading the same file again gives `name (1).ext`.
2. On an Android 7–9 device: the storage permission prompt appears on the first download, and denying it shows the error message.
3. Turn on airplane mode, open Server files (offline message), turn airplane mode off → the list loads by itself. Repeat after leaving and reopening the screen.
4. Upload an MP4, tap it on the Upload screen → it plays. Check seek, fullscreen in both orientations, and Back from fullscreen. Then play a video from Server files.
5. Regression: background upload/download, pause/resume, notifications and swipe-away still behave as listed above.
7. Responsive layout on real phones: a small phone (or *Display size: Largest*), a large phone, *Font size: Largest*, and landscape → no clipped or overlapping content on every screen.
6. Network health on a physical phone, through the foreground service, against the live server:
   - throttle the network (developer options or a slow hotspot) during a large upload and a large download → *Poor Connection*, amber bar;
   - switch on airplane mode at about 20%, 50% and 80% → *Connection Lost*, red bar, progress held;
   - switch it off → *Reconnecting* → the download continues within a few seconds from the same percentage, and the upload restarts from 0%;
   - check that the server lists each uploaded file once;
   - check the notification shade at each step, and repeat with the app swiped away.

Not verified on a physical device: OEM-specific battery killers, the Android 15 six-hour `dataSync` timeout, and session expiry on device (24 h token lifetime). Session-expiry handling is covered by unit tests.

## 21. Known limitations

- Upload pause/resume is not possible with this backend. Uploads restart from zero after cancellation or interruption.
- Publishing a download copies it from staging into `Download/LaanTech`, so for a moment there are two copies (the staging copy is deleted right after).
- On Android 11+ the app cannot see files that other apps (or a previous install) put in `Download/LaanTech`. MediaStore's unique naming still prevents overwrites, but the "(n)" number may skip.
- Removing a download from history does not delete the public file (by design).
- Video playback streams from the server, even for videos that were downloaded. Formats and codecs are limited to what the device's ExoPlayer supports. If streaming fails for a reason other than the network (e.g. an unsupported codec), the download-first fallback still downloads the file before reporting that it cannot be played.
- Authenticated playback was verified against a local server with the same auth and Range behaviour, not against the live server (no test account was available).
- The API has no token refresh or revoke. Sessions last 24 h, after which the user signs in again; background transfers that hit an expired token fail with a clear message.
- The integrity check compares the final size with `Content-Range`/`Content-Length` and, for resumed downloads, the start of `Content-Range` and the `ETag`. The server exposes no file hash, so the bytes themselves are not checksummed.
- Uploads restart from zero after a connection loss (backend limitation, see [Network health and transfer recovery](#network-health-and-transfer-recovery)). Detecting an upload that the server already received relies on name, size and upload time. Two identical files uploaded within the clock-skew tolerance, where the first response was lost, could be matched to the wrong copy. Both copies are still on the server, so nothing is lost.
- Network health thresholds (32/64 KiB/s, 10 s stall, 30 min wait) are fixed in `AppConfig`, not adapted to file size or network type.
- Upload speed is measured from the bytes Dio writes to the socket. OS and network buffers can absorb several MB, so on a slow uplink an upload can show *Good Connection* and climb to 99% before the server has received everything. The bar waits at 99% for the server's confirmation. In the first emulator run, 12 MB was buffered at once. Download speed is measured from bytes actually received and has no such gap.
- When the connection drops, the socket error can arrive a moment before Android reports "offline". For that moment the transfer shows *Reconnecting* before switching to *Connection Lost*.
- After a short outage, a connection that died silently is detected 3 s after the network returns (`AppConfig.reconnectStallAfter`). A shorter threshold would risk aborting connections that survived the blip.
- **Android network handover.** When Wi-Fi and mobile data come back together, a transfer can start on mobile data. Android then moves the default network to Wi-Fi and tears mobile data down 30 s later, which kills that connection (seen in the emulator logs as `handleLingerComplete`). A download resumes from its byte offset within a second. An upload restarts from 0%, because the backend can't resume uploads.
- Network health was verified on an emulator, with the engine in the test's isolate and a local server. It was not verified inside the foreground-service engine on a physical device, nor against the live server (no test account).
- The responsive layout is verified by the widget-test audit (10 screen configurations), not by screenshots on physical phones or tablets. Text follows the user's font size; very large settings beyond 1.5× were not audited.
- Transfer history is stored per device and cleared on logout.
- iOS background execution is not implemented.
- The Android application ID is still the template's `com.example.laantech_pos_task`.

## 22. Future improvements

- Android 14+ **user-initiated data transfer jobs** (native) as an alternative to the `dataSync` foreground service, avoiding the Android 15 six-hour limit.
- Resumable uploads (chunked or tus protocol), if the backend adds support. The engine already persists task state and would only need the session id and the confirmed offset.
- "Open file" / share actions for completed downloads (through the stored MediaStore URI).
- Wi-Fi-only mode for large files, and ETA display based on the measured speed.
- Play downloaded videos from the local public copy instead of streaming.
- Native iOS `URLSession` background transfers via a platform channel.
- Checksum validation if the API exposes hashes.
