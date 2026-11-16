# LaanTech POS — Background Upload/Download Module

A Flutter module for a POS SaaS app that reliably transfers large files (product catalogs, CSV imports, images, videos) in the background on Android.

Built for the **LAAN TECH USA Limited — Android POS Developer** technical assessment.

## Contents

[Overview](#overview) · [Features](#features) · [Tech stack](#tech-stack) · [Architecture](#architecture) · [Setup](#setup) · [Testing](#testing) · [Known limitations](#known-limitations)

---

## Overview

Transfers run in an Android **foreground service** with its own Flutter engine, so they keep going when the app is minimised or swiped away. Users can follow every upload and download from the app and from notifications. The app talks to the assessment mock server at `http://108.136.142.112:90`.

## Features

**Transfers**
- Multi-file upload, streamed from disk (never loaded fully into memory). Verified with 55–60 MB files on the live server.
- Downloads that resume with HTTP `Range` after a pause, a network loss or an app restart.
- Completed downloads are saved in the public **`Download/LaanTech/`** folder (MediaStore on Android 10+). Partial files are never exposed and existing files are never overwritten (`name (1).ext`).
- A queue with 2 concurrent transfers, a persisted history, and auto-resume after a crash.
- Pause / resume / retry / cancel. Upload *pause* isn't offered because the server can't resume uploads.
- In-app video playback with authenticated Range streaming and a download-first fallback.

**Network resilience**
- Each running transfer shows one of four statuses, with a matching progress colour and speed (KB/s or MB/s):

  | Status | Progress bar |
  |---|---|
  | Good Connection | Normal |
  | Poor Connection | Amber |
  | Reconnecting | Amber |
  | Connection Lost | Red |

- Nothing is sent while the device is offline. The transfer retries **as soon as the network returns**, with no probe and no fixed delay.
- A request that died during a short outage is detected 3 s after reconnecting and resumed from its byte offset.
- Exponential backoff (3 s → 60 s) applies only to repeated failures that move no data, and any connectivity change ends it early.
- A resumed download only appends data after checking `206`, `Content-Range` and the `ETag`; anything else restarts the download cleanly.
- If the network stays down for 30 minutes, downloads pause and uploads fail with a clear message.

**App**
- Login, registration, session restore, and a re-login prompt when the session expires.
- Dashboard, Upload, Server files (list / download / delete / play), Transfer center and Transfer details screens.
- A persistent bar showing active transfers under every screen.
- Notifications with live progress, network status and results. Tapping one opens that transfer, even from a cold start.
- Responsive layouts for small and large phones, landscape, tablets and large text sizes.

## Tech stack

| Area | Choice |
|---|---|
| Framework | Flutter 3.41 / Dart 3.11, Material 3 |
| State management | `provider` (MVVM ViewModels) |
| Networking | `dio`: streamed multipart, progress, cancellation, Range downloads |
| Background work | `flutter_foreground_task` (`dataSync` foreground service) |
| Notifications | `flutter_local_notifications` |
| Storage | `flutter_secure_storage` (token); local `public_downloads` Kotlin plugin (MediaStore) |
| Other | `connectivity_plus`, `video_player`, `file_picker`, `path_provider` |
| Android | minSdk 24, target/compile SDK 36 |

## Architecture

The project follows **Provider + MVVM + Repository**, reusing the starter kit's structure:

```
lib/
├── configs/      theme resources, responsive utilities, services, shared widgets
├── data/         network (Dio), storage, transfer engine
├── model/        session, server file, transfer task, video
├── repository/   auth, file, transfer, video
├── view/         splash, auth, home, upload, download, transfers, video_player
└── view_model/   auth, server_files, transfer, video_player
packages/public_downloads/   local Android plugin for the public Downloads folder
```

**Transfer flow:**

```
UI isolate                                   Foreground-service isolate
TransferViewModel → TransferRepository ──command──▶ TransferManager → NetworkApiService → API
                         ▲                              ├─▶ TransferStore (transfers.json)
                         └──── snapshots (500 ms) ──────┴─▶ NotificationService
```

- `TransferManager` owns the queue, retries and network health. When the service is stopped, the same class applies commands to the saved queue, so the rules live in one place.
- Network health is measured from real bytes moved in the service. The UI only displays it.
- **Responsive UI:** every screen body uses the project's `ResPonsiveUi` breakpoints. Phones get the full width; tablets and desktops get a centred 720 / 960 dp column.
  - Spacing uses `SizedboxSpaccing` and the `ResPonsiveUi` padding helpers (fractions of the screen size).
  - Text follows the user's font-size setting.

**API** (base URL in `lib/configs/res/app_url.dart`):

| Purpose | Request |
|---|---|
| Register / login | `POST /register`, `POST /token` (form: `username`, `password`) |
| List files | `GET /get` |
| Upload | `POST /upload` (multipart field `file`) |
| Download | `GET /get?file=NAME` with `Range: bytes=N-` |
| Delete | `DELETE /delete?file=NAME` |

## Setup

Requirements: Flutter 3.41+, Android SDK 36, and an Android device or emulator running API 24+.

```bash
git clone https://github.com/akanto99/LaanTech_Pos_Task.git
cd LaanTech_Pos_Task
flutter pub get
flutter run
```

Build a debug APK:

```bash
flutter build apk --debug          # → build/app/outputs/flutter-apk/app-debug.apk
```

There are no credentials in the repository. Create an account on the **Create account** screen. Cleartext HTTP is allowed only for the mock server's host.

## Testing

```bash
flutter analyze                    # no issues
flutter test                       # 275 tests, all passing
```

**Automated tests** cover:
- the transfer engine: queue, retries, pause/resume, Range resume, recovery after a network loss, duplicate prevention;
- the network layer: auth header, error mapping, `206` / `Content-Range` / `ETag` checks;
- the view models, repositories and transfer widgets;
- a **responsive layout audit** that renders 17 screens and states on 10 screen configurations (320 × 568 to 1280 × 800, landscape, text scale up to 1.5×). It fails on any overflow, on a screen body not built with `ResPonsiveUi`, or on a card wider than the tablet/desktop column.

**On-device tests** (`integration_test/`):

```bash
# Full flow against the live server (uses your own account)
flutter test integration_test/transfer_flow_test.dart -d <device> \
  --dart-define=TEST_USERNAME=<user> --dart-define=TEST_PASSWORD=<pass>

# Public Downloads folder (no account needed)
flutter test integration_test/public_download_storage_test.dart -d <device>
```

**Verified on an Android 15 emulator**

Against the live server:
- a 55 MB upload completed while the app was minimised;
- a 60 MB download survived being minimised, swiped away, paused, resumed and interrupted by airplane mode, and stayed byte-identical (SHA-1 match).

Against a local server with the same Range/`ETag` behaviour:
- **Network cut at 20%, 50% and 80%:**
  - the 40 MB download resumed from the exact byte offset in **0.37 s, 0.25 s and 3.8 s**, and its SHA-1 matched the server file;
  - the 30 MB upload restarted from 0% after each cut, and the server stored it **once**.
- **Reconnection regression fix:** after an 8 s outage, resume time went from 32.9 s to **3.5 s**.

## Known limitations

- **Uploads can't resume mid-file.** The server only accepts one complete multipart `POST /upload` (no chunk, session or offset support; `PUT`/`PATCH` → 405). Interrupted uploads restart from 0%, and the bar holds at 99% until the server confirms. True resume needs a backend change, such as tus or chunked uploads.
- **Android limits:**
  - Android 15 caps `dataSync` services at 6 hours per day.
  - Android 12+ can't start services from the background, so auto-resume after a kill waits for the next app launch.
  - OEM battery managers may still kill the service.
- **Network handover:** when Wi-Fi and mobile data return together, Android may close the mobile connection about 30 s later. Downloads resume within a second; uploads restart.
- Upload speed is measured at the socket, so system buffers can make a slow upload look fast for a moment.
- **iOS:** background transfers aren't implemented. They would need a native `URLSession` background configuration.
- **Not tested on a physical phone, tablet or the live server:**
  - network health was verified on the emulator against a local server;
  - the layouts were verified by widget tests.
- No token refresh: sessions last 24 h, then the user signs in again.
