# Changelog

## 1.0.5 — 2026-10-19

- Open the system file picker directly from editing tools, with multiple file selection.
- Keep PDF links active in extraction and result previews.
- Choose a single PDF or separate page files after selecting pages to extract.
- Save edited copies to Downloads / DocumentZ, add them to Recent and return there after saving.
- Use the same save flow for compression, booklets and exports; retain failed results for retry.

## 1.0.4 — 2026-10-17

- Open supported documents from Android file managers and Share menus.
- Reuse the existing library entry when opening an identical file under another name, preserving saved marks and reading position.
- Save the device-library index for faster launches and searches.
- Find new downloads and file changes automatically, including through Android background checks.
- Add manual update checks and optional update notifications in Settings.
- Download GitHub release APKs and verify their checksum, version, package and signing certificate before installation.

The initial library scan runs in the background. Android may delay background discovery and update checks under battery restrictions or force-stop. Updates still require confirmation in Android's installer.
