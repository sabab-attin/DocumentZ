# Changelog

## 1.0.4 — 2026-10-17

- Open supported documents from Android file managers and Share menus.
- Reuse the existing library entry when opening an identical file under another name, preserving saved marks and reading position.
- Save the device-library index for faster launches and searches.
- Find new downloads and file changes automatically, including through Android background checks.
- Add manual update checks and optional update notifications in Settings.
- Download GitHub release APKs and verify their checksum, version, package and signing certificate before installation.

The initial library scan runs in the background. Android may delay background discovery and update checks under battery restrictions or force-stop. Updates still require confirmation in Android's installer.
