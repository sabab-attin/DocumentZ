# Windows releases

DocumentZ on Windows has Recent and Edit. Open document uses the Windows file picker and accepts multiple files. The Library tab and Android-only controls are hidden; stored documents and annotations stay in their existing folders.

## Build an installer

Install Flutter, Visual Studio with Desktop development with C++ (including Windows SDK), and [Inno Setup](https://jrsoftware.org/isdl.php). Then run from the project folder:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tool\Build-Windows-Installer.ps1
```

The helper builds the complete x64 app, downloads and verifies Microsoft's signed Visual C++ runtime, and packages both with Inno Setup. For an offline build, supply `-VcRedist` with a verified runtime installer and `-InnoCompiler` with ISCC.exe. Flutter's first Windows build can require Internet access for native dependencies.

The installer and its SHA256 checksum are written to `releases/windows`. Upload those to the matching GitHub release. Do not distribute DocumentZ.exe alone. The older `Build-Windows-Release.ps1` still creates a portable ZIP, which does not register file associations.

## Installation and opening files

Setup installs to Program Files/DocumentZ, creates a Start menu shortcut and uninstall entry, registers supported types in Open with and Default apps, and adds local-subnet sync firewall rules. Setup requests administrator approval for these machine-wide settings. It does not change the user's default reader. Windows decides which apps appear directly in its short context menu; Choose another app lists registered handlers.

Explorer opens files in the existing DocumentZ process. File paths with spaces and Unicode names are passed as data, not commands. Multiple selections are queued; the last opened reader is on top and Back returns through earlier documents. A damaged or unsupported file produces an error without discarding later files. Identical imported documents reuse their existing identity and saved marks.

Uninstall removes the program, associations and its own firewall rules. It does not remove documents, annotation data or preferences. Close DocumentZ before upgrading.

## Desktop controls

- The top toolbar shows search, annotation, viewing and editing icons. Use the title-bar arrow or F9 to hide/show it; the choice is saved.
- Click the bottom page number to jump. EPUB page numbers apply to the current chapter; continuous EPUB mode jumps between chapters.
- Drag the right scrollbar to navigate a document. Continuous views retain normal scrolling.
- Ctrl+Z undoes annotations, Ctrl+S saves them, Ctrl+F finds text and Ctrl+G opens page entry. Ctrl+D toggles a bookmark.
- Settings > Keyboard shortcuts lets you change common reader shortcuts or restore defaults. Text fields keep their normal editing shortcuts.
- EPUB page turns repaint the visible page without laying out the chapter again; text selection, marks and publisher layout remain available.

- Mouse wheel scrolls PDFs and continuous ebooks; it turns pages in paginated ebooks.
- Page Up/Page Down and Left/Right navigate paginated ebooks. PDF viewer keyboard controls remain available.
- F11 enters/exits fullscreen; Escape closes the reading menu or exits fullscreen.
- Reading controls stay visible. Mouse drag selects text in browse mode; marking tools still draw/mark deliberately.
- Windows page changes use a 240 ms live-page slide without GPU snapshot readback. Android keeps its existing animation.
- Single-page PDFs isolate the fitted page from its neighbours and refit on window resize.
- PDF browse mode uses mouse-drag text selection on Windows; touch handles stay on Android.
- Windows ebook text and mark previews repaint independently, so dragging a selection does not rebuild the paragraph.

## Android and Windows sync

Use the same trusted local network. On Android choose **Computer / local network** (turn sync off first if the mode selector is locked). Enable sync on both, scan the Windows pairing QR with Android, and approve only matching numbers. No Windows camera scanner is shown; QR image import and manual pairing remain available.

Use a trusted local network. Installer rules allow only the installed DocumentZ executable and its sync ports, on the local subnet, for Public and Private profiles; organization policies can still block it. This is local-network sync, not Internet/cloud sync. Android's direct Nearby phone mode remains unchanged.

Both devices must contain the exact same original file. Save and leave the reader before syncing. Saved marks, bookmarks, drawings and note attachments transfer both ways. Original files, Markdown source edits, reading positions and settings do not transfer. Use Sync now for later changes and reopen the document after success. Keys remain in each platform's secure storage; the existing authenticated encrypted protocol and number verification are retained.

## Release checks

Run formatting, analysis and the full Flutter test suite before packaging. Test the installer on a clean Windows PC: cold and already-running Open with, filenames with spaces/Unicode, multiple files, window resizing, mouse selection, scrolling, fullscreen, PDF links, editing, and preserved data after upgrade/uninstall. Test real Android-to-Windows and Windows-to-Android pairing/edits too; loopback protocol tests do not verify a real network or firewall.

Some older document formats need separate conversion tools; see [FORMATS.md](../FORMATS.md). Android storage discovery, camera scanning, forced rotation and APK installation are not Windows features.

### Local sync network access

The installer adds inbound rules for its installed executable, limited to the local subnet: TCP 45831-45839 and UDP discovery 45832. Both Public and Private profiles are covered; Domain policy is not changed. The listener uses the first free TCP port in that range and puts that port in its QR. Reinstall/upgrade to register the actual installed path; a copied portable executable at another location is not covered by those installer rules. Managed firewall policies can still block local connections, and the installer reports rule-creation failures.

Android-to-Android Nearby pairing uses a separate transport. Android-to-Windows pairing still requires a reachable local network; a QR alone cannot connect different networks or bypass access-point isolation. Pair approval, authenticated encryption and the existing saved-annotation rules are unchanged.

Android local-network connections prefer a Wi-Fi interface on the peer's subnet, without changing the app's default network. With an active VPN, the system route is retained. The Nearby phone-to-phone transport does not use this route bridge.
