# public_downloads

Local Android plugin used by the LaanTech POS app to publish a finished
download into `Download/<folder>/`:

- **Android 10+ (API 29+):** inserts into `MediaStore.Downloads` with
  `RELATIVE_PATH = Download/<folder>/` and `IS_PENDING = 1` while copying, so
  the file is never visible half-written. No storage permission is needed.
- **Android 7–9 (API 24–28):** writes to the public Downloads directory using
  `WRITE_EXTERNAL_STORAGE` (declared with `maxSdkVersion="28"` by the app),
  through a hidden temporary file that is renamed when complete, then runs the
  media scanner.

Existing files are never overwritten: a name that is already taken becomes
`name (1).ext`, `name (2).ext`, … It lives in the app repo (not pub.dev)
because it has to be a plugin to be registered in the foreground-service
engine.
