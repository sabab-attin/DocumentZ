# Changelog

## 1.0.6 — 2026-10-20

- Compress PDF resource streams and embedded images without flattening pages; retain selectable text, links, forms and bookmarks.
- Measure real output sizes, keep stronger presets from increasing size, and leave already compact PDFs unchanged.

- Route Android local-network sync through a matching Wi-Fi interface, retaining normal routing when a VPN is active; keep phone-to-phone Nearby pairing unchanged.

- Keep Windows EPUB chapters mounted during page animations instead of reparenting all selectable text.
- Paint and hit-test only visible reflowable paragraphs in paginated and continuous Windows reading; isolate native text-selection repainting.
- Allow local sync through executable- and port-scoped installer rules on Public and Private Windows profiles, without changing the network profile.
- Keep listener fallback ports inside the permitted range and report installer firewall failures.

- Add a hideable Windows toolbar with search, annotation, editing and viewing controls.
- Add right-side document scrollbars and clickable page numbers for direct navigation.
- Add configurable reader keyboard shortcuts in Settings, including undo, save, find and page navigation.
- Keep normal text-editing shortcuts in notes and search fields.
- Reuse EPUB page layouts during navigation and index line boundaries more efficiently.

- Restore a lightweight animated Windows page transition.
- Isolate single-page PDFs, including mixed page sizes, keyboard/wheel navigation and resized windows.
- Enable Windows PDF mouse-drag selection instead of forcing touch handles.
- Cache ebook text metrics and repaint Windows selection previews without rebuilding paragraphs.

- Add a Windows installer with Open with registration, Start shortcut, uninstall entry and the Visual C++ runtime.
- Open Explorer files in the existing Windows window; preserve saved marks when reopening identical files.
- Keep Recent and Edit on Windows; use its native picker for multiple documents.
- Keep the Windows pairing QR and local-network sync with Android; hide camera scanning and Android update controls.
- Add desktop page keys, ebook mouse-wheel paging, F11/Escape and always-visible reading controls.
- Avoid desktop GPU snapshot readback during page turns; keep Android page animations unchanged.

- Use the new book logo across Android, Windows and web, with Android themed icon support.
- Remove alternate app icons and the Create PDF entry from Edit.
- Refit PDFs when fullscreen, window height or orientation changes; keep normal pages below the toolbar.
- Add fullscreen landscape reading with an exit button and Back support.
- Add a Windows release packaging script and distribution guide.

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
