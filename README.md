# DocumentZ

Read PDFs, ebooks and other documents. Add notes, edit PDFs and sync your annotations between devices.

DocumentZ is available for Android and Windows. Your documents stay on your device, and reading does not require an account.

[Download for Android](https://github.com/sabab-attin/DocumentZ/releases/latest) · [Supported formats](FORMATS.md) · [Sync guide](SYNC.md) · [Report an issue](https://github.com/sabab-attin/DocumentZ/issues)

## Features

- **Read:** Open PDFs, EPUBs, Markdown, text, images and supported Office files. On Android, open supported documents directly from a file manager or Share menu. Search within documents, follow links and save bookmarks.
- **Make it comfortable:** Adjust fonts, text size, alignment and zoom. Choose light or dark pages, paper textures for ebooks and fullscreen reading.
- **Annotate:** Highlight, underline, strike through, draw and add notes with image attachments. Keep your marks and bookmarks between sessions.
- **Edit PDFs:** Merge, split, extract, reorder, rotate and delete pages. Compress files, create booklets, fill supported forms, add signatures and redact areas.
- **Sync across devices:** Pair by QR and exchange saved annotations and bookmarks. Nearby Android phones connect without a shared Wi-Fi network or hotspot; Windows uses local-network sync.
- **Keep files organized:** Browse your library, search device documents and return to recent files with reading progress. Android saves its document index and picks up new downloads and file changes automatically.
- **Stay up to date:** Check for Android updates in Settings, or enable notifications for new GitHub releases.

Android also supports document scanning and Latin-script OCR. Available tools depend on the document format and platform; see [FORMATS.md](FORMATS.md) for details.

## Screenshots

<table>
  <tr>
    <th>Recent documents</th>
    <th>Library</th>
    <th>Annotations</th>
  </tr>
  <tr>
    <td valign="top"><img src="docs/screenshots/recent.jpg" alt="Recent documents with covers and reading progress" width="240"></td>
    <td valign="top"><img src="docs/screenshots/library.jpg" alt="Document library with search and folder controls" width="240"></td>
    <td valign="top"><img src="docs/screenshots/annotations.jpg" alt="Reader controls for highlights, notes, bookmarks and annotation tools" width="240"></td>
  </tr>
  <tr>
    <th>Annotation sync</th>
    <th>PDF tools</th>
    <th>Reading settings</th>
  </tr>
  <tr>
    <td valign="top"><img src="docs/screenshots/sync.jpg" alt="Nearby annotation sync with QR pairing controls" width="240"></td>
    <td valign="top"><img src="docs/screenshots/pdf-tools.jpg" alt="PDF editing tools including merge, split, organize and rotate" width="240"></td>
    <td valign="top"><img src="docs/screenshots/reading-settings.jpg" alt="Font, text size, alignment and page-fit settings" width="240"></td>
  </tr>
</table>

## Download and install

| Android build | Architecture |
| --- | --- |
| [ARM64](https://github.com/sabab-attin/DocumentZ/releases/latest/download/app-arm64-v8a-release.apk) | 64-bit ARM; most Android phones and tablets |
| [ARM32](https://github.com/sabab-attin/DocumentZ/releases/latest/download/app-armeabi-v7a-release.apk) | 32-bit ARM |
| [x86_64](https://github.com/sabab-attin/DocumentZ/releases/latest/download/app-x86_64-release.apk) | 64-bit x86 Android devices and emulators |

Open the APK and allow installation from your browser or file manager if prompted. Release notes and `SHA256SUMS.txt` are available on the [releases page](https://github.com/sabab-attin/DocumentZ/releases/latest).

All three downloads are Android apps. Windows can be built from source. Android 7.0 is the configured minimum; some features have additional requirements.

Updates must use the same signing certificate as the installed app. If Android reports a signature conflict, keep your existing installation: uninstalling or clearing app data can remove local documents and annotations.

In **Settings → App updates**, check for a new version or turn on **Automatic update checks**. Tap an update notification to download it. DocumentZ checks the downloaded APK before opening Android's installer; you confirm the installation. Background checks depend on Android's scheduling and battery settings. See [UPDATES.md](UPDATES.md) for details and [CHANGELOG.md](CHANGELOG.md) for recent changes.

## Sync your annotations

For nearby Android phones:

1. Turn on Wi-Fi and Bluetooth. Open **Settings → Annotation sync** on both phones and enable **Nearby phones** sync.
2. Allow Nearby devices access, then scan the other phone's QR.
3. Compare the verification numbers and approve only if they match.

Keep both phones nearby with DocumentZ running. Both need the updated app and current Google Play services. For later changes, tap **Sync now** on one phone.

**Import the exact same original document on both devices.** Save your annotations and leave the reader before syncing, then reopen it to see received marks. Matching filenames alone are not enough.

Saved annotations, drawings, note attachments and bookmarks are exchanged. Original files, Markdown source edits, reading positions and settings are not transferred. Conflicting edits are kept for review.

For Windows, choose **Computer / local network** and connect both devices to a reachable local network. See [SYNC.md](SYNC.md) for setup, security and limits.

## Storage and privacy

Documents and annotations are stored locally. Sync is optional, encrypted and requires approval for new devices. DocumentZ does not use a hosted document-sync server. Google Play services Nearby may collect connection diagnostics under Google's Usage & diagnostics setting. The sync protocol has not had an independent security audit.

The first Android library scan runs in the background. Later launches reuse the saved index while file changes are checked automatically. Storage access or connected-folder permission is required to discover device documents. Battery restrictions and force-stop can delay background discovery; opening the app lets it catch up.

Sharing sends files through the app or provider you choose. Web lookups and cloud file providers use their own services. Android OCR and Windows document conversion process files locally.

App update checks contact GitHub. They do not send your documents, annotations or library list. Automatic update checks are off by default.

## Document limits

- Annotations are app overlays; sharing the original file does not automatically embed them.
- Ebook page counts change with screen size and font settings. EPUB and Office views may not preserve every layout detail. DRM-protected books are unsupported.
- Ebook layout changes can shift drawing overlays.
- Redaction creates image pages. Image-based compression loses searchable text and interactive content. PDF edits may invalidate signatures or omit some forms, outlines and links. Review exported copies before sharing.
- Imports have no fixed application-level file-size cap, but available memory and storage still matter.

## Build from source

Install Flutter with a Dart SDK compatible with [pubspec.yaml](pubspec.yaml). Android builds need the Android SDK and a compatible JDK. Windows builds need Visual Studio's **Desktop development with C++** workload.

```sh
flutter pub get
flutter analyze
flutter test --concurrency=1
flutter run
```

```sh
flutter build apk --release --split-per-abi
flutter build windows --release
```

Configure release signing before distributing Android builds. Official updates must retain the existing app's signing identity. Keep signing keys, passwords and debug symbols private. Windows distribution needs the complete release directory, including its libraries and data.

## Licenses

Dependencies are listed in [pubspec.yaml](pubspec.yaml) and [pubspec.lock](pubspec.lock). Review their licenses before distribution, including Syncfusion's requirements and [FONT_NOTICE.md](FONT_NOTICE.md). The QR scanner uses ZXing under Apache-2.0. Third-party notices are available in the app.

There is no project-level LICENSE file yet. Public source availability does not by itself grant an open-source license.

## Feedback

[Open an issue](https://github.com/sabab-attin/DocumentZ/issues) with your app version, operating system, document format and steps to reproduce the problem. Include a small sample or screenshot when useful, with private information removed.
