# App updates

Android Settings includes **Check for updates** and an optional **Automatic update checks** toggle. Automatic checks are off until enabled. They use the public latest stable release in `sabab-attin/DocumentZ` on GitHub, approximately every six hours when Android permits background work. They also catch up on app launch when a check is overdue. They are not instant push notifications; force-stop, battery restrictions, offline status or disabled notification permissions can delay alerts.

Tap an update notification to start a download. The download continues through Android Download Manager, including when DocumentZ is not in front. The downloaded APK is checked against the GitHub asset SHA-256 digest, its expected size, the installed package name, a higher Android version code, the release version and the installed signing certificate. The installer is opened only after these checks. Android still requires installation approval; if requested, allow updates from DocumentZ in the system's Install unknown apps screen and tap Install update again.

To publish a compatible update:

1. Increase both the semantic version and build number. This package prepares **1.0.4+8**; the next release must use a higher version and build number.
2. Use the same app ID and signing identity as existing installations.
3. Build and validate all three ABI APKs.
4. Publish a stable GitHub release, tagged `vMAJOR.MINOR.PATCH`, and mark it latest. Drafts and prereleases are ignored.
5. Upload `app-arm64-v8a-release.apk`, `app-armeabi-v7a-release.apk`, `app-x86_64-release.apk` and `SHA256SUMS.txt`. The updater chooses the supported architecture and requires GitHub's SHA-256 asset digest to be available.

Release checks send no document content, library lists or pairing identities. They do make ordinary HTTPS requests to GitHub; GitHub sees normal connection information such as the requesting IP address. Downloading uses the current connection and may use mobile data; roaming downloads are disabled.

The Android update checker does not bypass Play Protect, install silently, change signing keys or delete user documents. Windows and web builds retain their existing behavior.

# Device library index

The first library view uses Android's MediaStore metadata as a quick starting list. A separate worker then completes one full scan, preserving the existing rules for supported formats, inaccessible folders and connected-folder identities. Its results are saved in app-private storage; the next app launch reads that index rather than walking storage again. Parsing and writing index data run off the UI isolate. Search filters a cached sorted list, without disk scanning or sorting the whole list on each keystroke.

The first complete scan can still take time on a large device. It does not block opening documents through the app's separate file worker. New downloads and other file changes are discovered automatically. MediaStore and connected-provider notifications, together with file observers, trigger short background metadata checks while the app is running. Changed Download/Documents directories and known document folders are checked directly, including files not yet listed by MediaStore. Unchanged folders are not re-listed, and new subfolders are inspected without crawling the whole device again. Photos, audio, video, APKs and unfinished download extensions are excluded from Browse discovery.

When the app is closed, Android content-triggered jobs and a persisted periodic job keep a separate metadata change journal. The app also catches up automatically on resume. Deltas are merged into the saved index and acknowledged only after they are saved. Failed writes are retried with backoff, and a scan completing late cannot overwrite a newer download or deletion. Jobs are restored after reboot/update. Android can defer jobs during Doze, battery restrictions or force-stop; foreground discovery catches up when the app is opened. This is automatic file discovery, not a promise of instantaneous delivery while Android blocks background execution.

Manual Refresh remains a recovery option, not a requirement for finding new files. Permission or connected-folder changes invalidate the saved scope. Renaming and deleting inside DocumentZ update the cached entries directly. The index contains metadata only; deleting it cannot delete source documents or annotations.
