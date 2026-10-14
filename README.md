# DocumentZ

A Flutter document reader and PDF editor for Android and Windows.

DocumentZ brings a personal document library, configurable reading views, annotation tools, and PDF utilities into one application. Documents are imported locally, and editing operations save new copies so original files remain available.

## Features

### Read and organize

- Import documents from local storage and supported file-picker providers.
- Browse a searchable library with PDF first-page previews and EPUB covers.
- Navigate PDFs using outlines, bookmarks, thumbnails, page jumps, and keyword search.
- Read PDFs in continuous, single-page, or two-page views.
- Read reflowable EPUB chapters with a collapsible table of contents and adjustable typography.
- Choose Light, Dark, Solarized Dark, or Kawaii appearance, with independent page dark mode.
- Apply left, right, centered, or justified alignment in supported flowing-text readers.
- Hide reader controls for an unobstructed reading view. Page-turn effects respect reduced-motion settings.

### Annotate

- Highlight, underline, strike through text, and add notes.
- Draw with selectable colors and stroke sizes, erase strokes, and undo changes.
- Add arrows, rectangles, callouts, and drawn signatures.
- Annotate immediately with a finger or stylus; use two fingers to navigate while a tool is active.
- Keep annotations and bookmarks locally between sessions.

### Work with PDFs

- Merge, split, extract, reorder, remove, and rotate pages using previews.
- Add text and images, or visually replace a selected page area.
- Fill supported AcroForm fields and stamp drawn signatures.
- Digitally sign documents using a supplied PFX/P12 certificate.
- Encrypt PDFs and redact selected regions.
- Create text PDFs, scan documents, and perform on-device Latin-script OCR on Android.
- Export extracted text to DOCX or XLSX, or export PDF pages as PNG images.
- Preview, print, and share documents through supported system integrations.

## Supported formats

| Category | Formats | Reading approach |
| --- | --- | --- |
| Documents | PDF, EPUB | PDF pages or reflowable EPUB chapters |
| Text and saved web pages | TXT, Markdown, RTF, HTML/HTM, MHTML/MHT | Text or simplified HTML views |
| Office and OpenDocument | DOCX, XLSX, PPTX, ODT, ODS, ODP | Readable content, sheets, or slide sections |
| Images | PNG, JPG/JPEG, BMP, GIF, TIFF/TIF, SVG | Image views; multi-page TIFF navigation |
| Formats requiring conversion | DOC, XLS, PPT, MOBI, PS, EPS | Local Windows conversion to PDF |

Direct Office views prioritize readable content over exact page layout. Legacy conversion requires separately installed LibreOffice, Calibre, or Ghostscript. Converted PDFs can be shared to Android.

See [FORMATS.md](FORMATS.md) for conversion setup, rendering details, and format-specific limits.

## Install on Android

When a release APK is available, download it from this repository's **Releases** page, open it on your device, and follow Android's installation prompts. Android may require permission to install apps from the browser or file manager used to open the APK.

DocumentZ currently requires Android 7.0 / API 24 or later. Once installed, the application runs independently of a development computer.

To update an existing installation, install a newer APK with the same application ID and signing certificate. Back up important documents before uninstalling or clearing application data.

## Development

### Requirements

- Flutter with a Dart SDK satisfying `^3.13.5`, as declared in `pubspec.yaml`.
- Android development tools and a compatible JDK for Android builds.
- Visual Studio's **Desktop development with C++** workload and Windows Developer Mode for Windows builds.
- A connected Android device, emulator, or Windows desktop target.

From the repository root:

```sh
flutter pub get
flutter analyze
flutter test --concurrency=1
flutter devices
flutter run -d <device-id>
```

For Windows:

```sh
flutter run -d windows
```

New native plugins require a full application restart. Hot reload alone cannot register them.

### Build for distribution

```sh
flutter build apk --release
```

The Android APK is written to `build/app/outputs/flutter-apk/app-release.apk`.

The current Android configuration uses the development signing key for release builds. Configure a dedicated release signing key before public distribution and retain it securely for future updates. Increase the version and build number in `pubspec.yaml` for each release. Signing credentials and keystores must remain outside version control.

For Windows:

```sh
flutter build windows --release
```

Distribute the complete Windows release directory, including its supporting libraries and data files.

## Storage and privacy

On Android and Windows, imported documents are copied into application storage. Reading does not require a DocumentZ account or a cloud conversion service. Conversion tools run locally on Windows, and OCR runs on-device on Android.

Preferences, bookmarks, and annotations are stored locally. Browser previews use a session-only document library and provide a reduced feature set. Uninstalling the application or clearing its data may remove the library and annotations.

Sharing explicitly sends the selected document through the chosen system application or provider. File-picker providers may include external cloud services.

## Current limitations

- **Annotations are application overlays.** Sharing an original document does not embed its marks. Edited copies do not inherit the original's overlays.
- **PDF content correction is visual.** It does not provide full paragraph reflow, exact embedded-font matching, or object-level image editing. Area replacement rasterizes the affected page.
- **Redaction flattens the output.** All pages become images at 144 DPI; searchable text, forms, links, metadata, and existing digital signatures are discarded. Review the result before sharing.
- **Merge and split preserve page artwork and text**, but do not preserve interactive forms, outlines, or links.
- **Text exports simplify content.** DOCX and XLSX exports do not reconstruct original tables, columns, images, or typography. Scans need OCR before text export.
- **EPUB and Office fidelity is limited.** Complete publisher CSS, exact fixed-layout EPUB reproduction, and original Office page geometry are not guaranteed. DRM-protected books are unsupported.
- **Forms and signatures have boundaries.** XFA forms, JavaScript calculations, and certificate-chain validation are not implemented. Editing can invalidate existing signatures.
- **Page dark mode preserves image colors.** Image-only PDFs retain their original appearance; browser PDF previews retain original page colors.
- Imports are limited to 100 MB, with additional archive and image-decoding limits documented in [FORMATS.md](FORMATS.md).
- SQLite storage, Supabase synchronization, and retrieval-augmented search are planned rather than implemented.

## Project structure

```text
lib/
  core/       Themes and reader preferences
  domain/     Document models and service interfaces
  data/       Import, storage, parsing, conversion, and PDF operations
  features/   Library, readers, annotations, settings, and editing flows
test/         Unit, widget, and native PDF regression tests
android/      Android application configuration
windows/      Windows application configuration
web/          Browser preview configuration
```

Tests cover document imports, persistence, format parsing, annotation geometry, reader interactions, preferences, PDF editing, forms, and page-color rendering. Run the full suite before releasing. Physical-device checks remain important for scanning, OCR, signing, printing, sharing, gestures, and animation performance.

## Dependencies and licensing

DocumentZ uses Flutter and third-party packages including pdfrx/PDFium, Syncfusion Flutter PDF, pdf, printing, flutter_widget_from_html_core, flutter_svg, Google ML Kit text recognition, cunning_document_scanner, signature, and share_plus. The complete dependency list and resolved versions are recorded in `pubspec.yaml` and `pubspec.lock`.

Syncfusion Flutter PDF requires a commercial license or eligibility for its Community License. Review the [package's licensing information](https://pub.dev/packages/syncfusion_flutter_pdf) before distributing the application. Preserve applicable third-party license notices, including those required by bundled native components and external conversion tools.

No project-level open-source license has been selected yet. Public source availability alone does not grant permission to redistribute or modify the project; add an appropriate `LICENSE` before presenting DocumentZ as an open-source release.

## Reporting issues

Include the application version, device and operating system, document format, steps to reproduce, and expected behavior. Attach a small, non-sensitive sample document when the issue depends on a particular file. Remove personal information, passwords, and signing credentials from reports.
