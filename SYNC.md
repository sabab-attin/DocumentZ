# Annotation sync

Sync is optional. Android phones default to direct nearby pairing; Windows connections use the existing local network mode. Neither mode uses a hosted annotation server or cloud account.

## Two nearby Android phones

1. Install the updated app on both phones and switch on Wi-Fi and Bluetooth. No shared Wi-Fi network or manually configured hotspot is needed.
2. Import identical original documents on both phones. Save your annotations and close the reader before syncing.
3. Open Settings → Annotation sync on both, choose Nearby phones and enable sync. Allow Nearby devices access when Android asks.
4. Scan the other phone's QR. Compare DocumentZ's verification numbers and approve only if they match. A fresh invitation expires after ten minutes and is consumed by an authenticated pairing attempt.
5. Saved annotations exchange after approval. Both phones must confirm the saved data before the updated protocol reports success. Reopen the document on each phone to see the received marks.
6. For later saved changes, tap Sync now on one phone. Sync remains enabled when leaving the screen while the app is running; switching it off stops its radio activity and closes transfers.

This is short-range pairing, not remote internet sync. Both phones need current Google Play services. Wi-Fi and Bluetooth radios must remain enabled. On older Android versions, Android may also require location permission for discovery. Device or system restrictions can still interrupt a connection; the app reports failures and supports a safe retry.

## Computer / local network mode

Switch sync off, select Computer / local network on the Android phone, then enable sync on both devices. This existing mode requires a reachable shared local network. Pair using its QR or displayed local address and one-time code. The Windows installer registers local-subnet firewall access for its installed executable on Public and Private profiles. TCP uses the first available port from 45831–45839; UDP discovery uses 45832. Android local-network connections prefer a matching Wi-Fi interface and retain normal system routing when a VPN is active. Guest-network isolation can block this mode. The Android phone-to-phone nearby mode avoids that IP setup.

## What is exchanged

Saved notes, highlights, text marks, bookmarks, drawings, signatures and note/image attachments are exchanged only for originals with matching format and content fingerprints. Original files, filesystem paths, full library lists, account credentials, reading positions and reading preferences are not transferred. This includes Markdown documents: saved annotations sync, but edits to the Markdown source do not. Changing original file bytes creates a different fingerprint.

An operation graph preserves edit and removal history. Concurrent edits are retained as separate editable marks; concurrent deletion cannot erase an edit. Review overlapping conflict copies. Repeated sync is idempotent, and old snapshots cannot resurrect recorded removals. Sync never deletes documents. Text marks retain source offsets; freehand/image overlays retain normalized geometry, so different ebook typography can change their alignment. PDF geometry remains fixed.

## Security design

- Pairing uses a random 128-bit QR secret, never a permanent peer key. The secret is not transmitted in the connection handshake.
- Each session has fresh X25519 keys and nonces. HMAC-SHA256 authenticates role-separated transcripts; HKDF-SHA256 derives directional keys; ChaCha20-Poly1305 authenticates and encrypts annotation messages.
- Nearby connection authentication digits are bound into the authenticated transcript. Different underlying bindings are rejected. Accepting a tentative native radio connection does not trust a peer: valid app-level proof and explicit first-pairing approval are required before annotation exchange.
- Sequence checks and session keys reject reordered/replayed messages. Native byte frames and unauthenticated input are bounded. Each updated side saves the merge and confirms a matching canonical-history SHA-256 digest; an absent/mismatched acknowledgement cannot report completed sync.
- Permanent paired-device secrets use secure device storage and are excluded from Android backup/device transfer. Inaccessible keys never cause plaintext fallback. Unpair locally on both devices to remove both stored relationships; saved marks remain intact.
- An interrupted annotation apply uses a recoverable write-ahead record, checked before the reader loads annotations. Retrying is safe.

Nearby advertises only a random app-device identifier, with no document metadata or pairing secret. Active discovery runs during a user-initiated connection attempt and stops once the chosen peer is found. The Google Play services SDK may collect connection-performance and device diagnostics under Google's Usage & diagnostics setting. DocumentZ does not upload document content or plaintext annotation data to a cloud backend. See https://developers.google.com/nearby/connections/overview .

## Limits and validation

Annotation snapshots are bounded to 16 MB, with 30,000 historical operations per document; annotation counts, geometry and images are validated. Large image histories fail visibly rather than being truncated. Local annotation/history storage remains app-private storage; this feature does not add document encryption at rest. An unlocked/compromised phone or an approved paired device can access its annotations. The application protocol has not had an independent security audit.

Run analysis, the full test suite and Android/Windows builds before release, then verify real phone pairing, notes/bookmarks in both directions, edits/removals, declined approval, interrupted transfers and unpairing. Automated protocol tests and native compilation do not replace live radio tests on the actual devices.
