# DocumentZ

**Read, organize, annotate, and edit your documents.**

DocumentZ is a Flutter document reader and PDF editor for Android and Windows. Browse local documents, return to recent files, customize your reading view, and work with PDFs in one app.

## Download for Android

Download the latest published **Android** release. Version 1.0.2 contains the reader and local annotation sync updates described below.

| Download | Choose this for |
| --- | --- |
| [Newer Android phones — ARM64 (v8a)](https://github.com/sabab-attin/DocumentZ/releases/latest/download/app-arm64-v8a-release.apk) | Most modern Android phones and tablets, including the Google Pixel 6a |
| [Older Android phones — ARM32 (v7a)](https://github.com/sabab-attin/DocumentZ/releases/latest/download/app-armeabi-v7a-release.apk) | Devices that require 32-bit ARM apps |
| [Android x86_64 — Intel/AMD](https://github.com/sabab-attin/DocumentZ/releases/latest/download/app-x86_64-release.apk) | Android devices and emulators using x86_64 processors |

Choose by **processor architecture**, not just the phone's age. All three downloads are Android APKs. The x86_64 APK is **not a Windows installer**.

[View release notes and all downloads](https://github.com/sabab-attin/DocumentZ/releases/latest)

### Install on Android

1. Download the APK matching your device.
2. Open it from your browser, Downloads folder, or file manager.
3. If prompted, allow **Install unknown apps** for the app opening the APK.
4. Install and launch DocumentZ.
5. Grant storage or folder access when prompted to browse local documents.

Android 7.0 / API 24 is the project's configured minimum; dependency and device requirements can impose additional limits. File access depends on your permissions and Android's storage restrictions.

Updates must use the same application ID and signing certificate as the installed app. If an update reports a signature conflict, preserve your existing installation and export important documents and notes before considering removal.

### Windows

The project includes a Windows desktop target, but **no Windows download is included in the Android assets linked above**. Developers can build it from source using the instructions below.

## Changes in v1.0.2

- Local Wi-Fi annotation and bookmark sync between explicitly paired Android and Windows devices, without a hosted server. Reading and local editing remain available offline. See [SYNC.md](SYNC.md) for pairing, security controls and limits.
- Ebook pagination through long chapters, whole-image fitting, adaptive page margins, publisher paragraph styles and framed content, with paper texture in light and dark page modes.
- Faster page-turn transitions that reuse the chapter layout, update the page footer separately, and retain one follow-up turn during an animation.
- Document browsing filtered to supported formats, with recently modified files first; larger page-organizing previews and drag-to-top/bottom controls.
- Booklet defaults to all pages in one booklet. Printing tip: choose both sides and flip on the short edge.

Ebook page counts follow the current screen size and typography; they can change with font size, orientation, or fullscreen mode. They are not guaranteed to match a printed edition or another reader.

## Features

### Your documents, organized

- **Recent:** return to recently accessed documents and see reading progress.
- **Library:** search imported documents and device files available through granted storage or folder access.
- Choose different cover sizes and list-style views, with sorting controls.
- Open file actions through the three-dot menu or a long press: share, rename, delete, and remove from Recent where applicable.
- Select multiple documents for supported editing operations.

### Read your way

- Read PDFs in continuous, single-page, or two-page views.
- Use document search and match navigation, contents, bookmarks, thumbnails, and page jumps.
- Follow embedded PDF citations and figure/table links, plus ebook chapter and footnote links.
- Select a word and choose **Look up** for Google results in an in-app browser tab on supported devices. Only the requested lookup needs an internet connection.
- Adjust fit and zoom, enable page buttons, and use full-screen reading.
- Change fonts, text size, and alignment in formats that support reflowable text.
- Set global reading defaults or customize an individual document.
- Choose Light, Dark, Solarized Dark, or Kawaii appearance, with separate page dark-mode controls.
- Switch between Classic, Kawaii, and Medieval app icons, with themed icons on compatible Android launchers.

### Annotate and take notes

- Highlight, underline, and strike through selected text.
- Choose preset colors, including black, or pick a custom color.
- Attach notes to text and add page notes with image attachments.
- Enter annotation mode from reader editing controls or the text-selection panel.
- Draw, erase, undo, and add shapes, arrows, callouts, or drawn signatures.
- Place text and images on pages, then finish placement with **Done**.
- Keep bookmarks and annotations locally between sessions.

### PDF tools

- Merge, split, extract, reorder, delete, and rotate pages.
- Create printable booklets with an interactive sheet preview.
- Compress PDFs and preview the result before saving a separate copy.
- Encrypt PDFs, redact regions, fill supported forms, and add signatures.
- Add text and images or visually replace a selected page area.
- Create text PDFs and convert supported formats to PDF.
- Scan documents and recognize Latin-script text on Android using on-device OCR.
- Export extracted text to DOCX or XLSX, or PDF pages as PNG images.
- Preview, print, and share through supported system integrations.

Availability varies by document format and platform.

## Supported formats

| Category | Formats | Reading approach |
| --- | --- | --- |
| Documents | PDF, EPUB | PDF pages or reflowable ebook pages, spreads, and continuous reading |
| Classic ebooks | MOBI (unencrypted, uncompressed or PalmDOC) | Reflowable ebook pages; other MOBI variants need Windows conversion |
| Text and saved web pages | TXT, Markdown, RTF, HTML/HTM, MHTML/MHT | Text or simplified HTML |
| Office and OpenDocument | DOCX, XLSX, PPTX, ODT, ODS, ODP | Readable content, sheets, or slide sections |
| Images | PNG, JPG/JPEG, BMP, GIF, TIFF/TIF, SVG | Image views; navigation for multi-page TIFF |
| Formats requiring external conversion | DOC, XLS, PPT, PS, EPS | Local conversion on Windows using separately installed tools |

Office and EPUB views prioritize readable content; they do not reproduce every detail of the original layout. Legacy conversion requires tools such as LibreOffice, Calibre, or Ghostscript. See [FORMATS.md](FORMATS.md) for setup and format-specific limits.

## Storage and privacy

Documents, preferences, bookmarks, and annotations are stored locally. Reading does not require a DocumentZ account. Windows conversion runs locally, and Android OCR processes text on the device.

Imported documents are copied into application storage. Device-library operations can also affect the original file: read the confirmation before deleting. Clearing app data or uninstalling can remove stored copies and annotations.

Sharing sends the chosen document through the application or provider you select. System file pickers may offer cloud providers with their own privacy policies. Google ML Kit remains an OCR dependency; this README does not claim that third-party SDKs collect no diagnostic data.

## Important document limits

- **Annotations are app overlays.** Sharing the original does not embed its DocumentZ marks, notes, or placed objects. Generated copies do not automatically inherit those overlays.
- **Compression depends on the document.** Preserve-content optimization may produce no size reduction. Image-copy modes reduce detail and discard selectable text, interactive forms, links, embedded notes, and bookmarks; explicit consent is required. Protected and signed PDFs are refused, and originals are kept unchanged.
- **Redaction flattens pages.** Output becomes images, discarding searchable text, forms, links, metadata, and existing digital signatures. Review the result before sharing.
- **Some PDF edits simplify content.** Area replacement rasterizes the affected page. Merge and split do not retain all interactive forms, outlines, or links.
- **Text exports simplify layouts.** They do not reconstruct every table, column, image, or font. Scanned pages require OCR first.
- **Forms and signatures have limits.** XFA forms, JavaScript calculations, and certificate-chain validation are not implemented. Editing can invalidate existing signatures.
- **DRM-protected books are unsupported.** Full EPUB styling and original Office page geometry are not guaranteed.
- Imports are limited to 100 MB, with additional archive and image limits in [FORMATS.md](FORMATS.md).

## Build from source

### Requirements

- Flutter with a Dart SDK matching the constraint in [pubspec.yaml](pubspec.yaml).
- Android SDK tools and a compatible JDK for Android.
- Visual Studio with **Desktop development with C++**, plus Windows Developer Mode, for Windows.

### Check and run

~~~sh
flutter pub get
flutter analyze
flutter test --concurrency=1
flutter devices
flutter run -d <device-id>
~~~

For Windows:

~~~sh
flutter run -d windows
~~~

Native plugin changes require a full restart. Test platform-dependent features on real devices before distributing a build.

### Build Android APKs

~~~sh
flutter build apk --release --split-per-abi
~~~

The APKs are written to **build/app/outputs/flutter-apk/**.

For one larger APK containing the supported architectures:

~~~sh
flutter build apk --release
~~~

Configure and retain a dedicated release signing key for public updates. The checked-in Android build configuration currently references debug signing. Keep keystores, passwords, local configuration, and diagnostic symbols out of version control. Increase the version and build number for each release.

### Build Windows

~~~sh
flutter build windows --release
~~~

Distribute the complete generated Windows release directory, including its supporting libraries and data files. An Android APK cannot serve as the Windows package.

## Dependencies and licensing

Dependencies and resolved versions are listed in [pubspec.yaml](pubspec.yaml) and [pubspec.lock](pubspec.lock). They include Flutter, pdfrx/PDFium, Syncfusion Flutter PDF, Google ML Kit, and document rendering and sharing packages.

Review the licenses for bundled libraries and fonts, including [FONT_NOTICE.md](FONT_NOTICE.md). Syncfusion Flutter PDF has its own licensing requirements.

A project-level **LICENSE** file has not yet been added. Do not assume an open-source license from the repository's public visibility.

## Feedback and bug reports

[Open an issue](https://github.com/sabab-attin/DocumentZ/issues) with:

- DocumentZ version and device or operating system.
- Document format and steps to reproduce the problem.
- Expected behavior and what happened.
- A small, non-sensitive sample document or screenshot when useful.

Remove personal information, document passwords, and signing credentials from reports.


### Annotation sync over local Wi-Fi

On the installed Android and Windows apps, open **Settings → Annotation sync**.
Enable sync on both devices, then use a one-time pairing code and confirm the
matching verification number. Select **Sync now** on a paired device to exchange
saved annotations and bookmarks. No internet connection, account or hosted
service is required. Both devices need the same original document imported;
document contents are fingerprinted locally, and whole documents are not sent.

Keep the sync screen open on both devices. Leaving it or putting the app in the
background stops its local listener and discovery. Reading, editing and local
annotation saving work independently of sync. Concurrent changes are preserved
for review. See [local sync details](SYNC.md) for security and current limits.
