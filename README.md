# DocumentZ

A document reader and PDF editor for Android and Windows. Read local files, add notes and bookmarks, and work with PDFs without a DocumentZ account.

## Download

- [Android ARM64](https://github.com/sabab-attin/DocumentZ/releases/latest/download/app-arm64-v8a-release.apk) — most phones, including Pixel 6a and Galaxy S25 FE.
- [Android ARM32](https://github.com/sabab-attin/DocumentZ/releases/latest/download/app-armeabi-v7a-release.apk) — devices that need 32-bit ARM apps.
- [Android x86_64](https://github.com/sabab-attin/DocumentZ/releases/latest/download/app-x86_64-release.apk) — Android devices and emulators with Intel/AMD processors.
- [Release notes and checksums](https://github.com/sabab-attin/DocumentZ/releases/latest).

Open the APK and allow installation from the browser or file manager when Android asks. Updates need the same signing certificate as your installed copy. Keep your existing installation if Android reports a signature conflict: uninstalling can remove local documents and annotations.

These downloads are Android apps, including the x86_64 build. Windows can be built from source. Android 7.0 is the configured minimum; some features have additional device requirements.

## What's new in v1.0.3

- Pair nearby Android phones by QR, without joining the same Wi-Fi or setting up a hotspot.
- Keep sync enabled when leaving its screen; pairing codes last ten minutes.
- Scan QR codes inside the app without downloading a scanner, or open them from a compatible camera app.
- Exchange saved annotations after pairing, with confirmation that both devices saved the same history.
- Shorter pairing instructions, with document requirements behind an info button.
- Remove the 100 MB import cap. Large files still need enough memory and storage.
- Slightly slower, smoother page turns.
- Extract PDF pages without cropping wide slides, with fewer steps.

## Reading and annotation

- Read PDFs, EPUBs, text, Markdown, saved web pages, images and supported Office files. See [FORMATS.md](FORMATS.md) for the full list and conversion requirements.
- Search documents, follow supported internal links, use contents and bookmarks, and return to recent files.
- Adjust fonts, text size, alignment, zoom and fullscreen view where the format supports them.
- Ebook pages have adaptive margins and paper textures in light and dark modes. Publisher styles, borders and image proportions are preserved where supported.
- Highlight, underline, strike through, draw, place text and images, and attach notes or image attachments.
- Look up selected words through Google.

Ebook page counts change with screen size and font settings. They may differ from a printed edition or another reader. EPUB and Office views do not reproduce every publisher layout, and DRM-protected books are unsupported.

## PDF tools

Merge, split, extract, reorder, rotate and delete pages. Create booklets, compress files, fill supported forms, add signatures, redact areas, export text or page images, and print or share copies. Android also supports document scanning and Latin-script OCR.

Some operations simplify the output. Redaction creates image pages; image-based compression loses searchable text and interactive content. Editing may invalidate digital signatures, and merge/split may not preserve all forms, outlines or links. Review generated copies before sharing them.

## Sync between devices

For two Android phones:

1. Turn on Wi-Fi and Bluetooth. Open **Settings → Annotation sync** on both phones and enable **Nearby phones** sync.
2. Allow Nearby devices access, then scan the other phone's QR.
3. Compare the verification numbers and approve only if they match.

Both phones need the updated app and current Google Play services. Keep them nearby with DocumentZ running. They do not need the same Wi-Fi network. For later changes, tap **Sync now** on one phone.

**Import the exact same original document on both devices.** Save your annotations and leave the reader before syncing. Reopen it afterward to see received marks. Matching filenames alone are not enough.

Sync exchanges saved annotations, drawings, note attachments and bookmarks. It does not transfer original files, Markdown source edits, reading positions or settings. Conflicting edits are kept for review. Ebook layout changes can shift drawing overlays.

For Windows, select **Computer / local network** and keep both devices on a reachable local network. Firewall access may be required. [SYNC.md](SYNC.md) explains pairing, security and limits.

## Storage and privacy

Documents and annotations are stored locally. Imported files are copied into app storage; clearing app data or uninstalling can remove them. File actions in the device library can affect the original, so read deletion confirmations.

Sync is optional and encrypted, with approval required for new devices. DocumentZ does not use a hosted document-sync server. Google Play services Nearby may collect connection diagnostics under Google's Usage & diagnostics setting. The sync protocol has not had an independent security audit.

Annotations are stored as app overlays. Sharing the original file does not automatically embed those marks. Sharing, web lookups and cloud file providers use the services you choose. Windows conversion runs locally; Android OCR runs on the device.

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

Configure your own release signing before distributing Android builds. Official updates must retain the existing app's signing identity. Keep keystores, passwords and debug symbols private. Windows distribution needs the complete release directory, including its libraries and data.

## Licenses

Dependencies are listed in [pubspec.yaml](pubspec.yaml) and [pubspec.lock](pubspec.lock). Check their licenses before distribution, including Syncfusion's licensing requirements and [FONT_NOTICE.md](FONT_NOTICE.md). The embedded QR scanner uses ZXing under Apache-2.0. Third-party notices are available in the app.

There is no project-level LICENSE file yet. A public repository alone does not grant an open-source license.

## Report a problem

[Open an issue](https://github.com/sabab-attin/DocumentZ/issues) with your app version, device, document format and steps to reproduce it. A small sample or screenshot helps. Remove private information and never include signing credentials.
