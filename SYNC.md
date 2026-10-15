# Local annotation sync

Local sync is optional and available in the installed Android and Windows apps.
It is not a cloud service or a KDE Connect protocol implementation.

## Use

1. Import the same original document on both devices. Renaming is fine; changing
   the document bytes creates a different fingerprint.
2. Open Settings → Annotation sync on both devices and enable Local Wi-Fi sync.
3. On one device choose Show pairing code. On the other, tap the nearby device
   or choose Pair by address, and enter the displayed one-time code.
4. Compare the verification number shown on both devices and approve only if it
   matches. The 128-bit pairing code is private, expires after five minutes and
   is consumed by one authenticated pairing attempt.
5. Select Sync now. Keep both sync screens open until completion.

If discovery is blocked, enter the displayed local IPv4 address and port.
Windows Firewall may ask for access: allow the app on your private network.
Guest Wi-Fi client isolation can prevent devices communicating. Android holds a Wi-Fi multicast lock only while discovery is enabled and releases
it on exit/backgrounding. There is no
internet relay, Bluetooth transport or continuously running background service.
The listener normally uses TCP 45831 and discovery uses UDP 45832; an available
TCP port is used if 45831 is occupied. The displayed address is authoritative.

## What is exchanged

Saved annotation data, including bookmarks, drawings, text marks and note/image
attachments, is exchanged only for document fingerprints present on both
participating devices. Original document files, filesystem paths, the full
library list and account credentials are not transferred. Existing annotated
text quotes are part of annotation data. Reading position and reading preferences
are not included in this version.

Both devices can add and edit annotations while offline. A per-annotation
operation graph retains deletion records. Concurrent edits produce separate,
individually editable marks rather than silently overwriting one another.
Concurrent deletion cannot erase a concurrent edit. After a conflict, inspect
and remove unwanted overlapping marks. Deleted records remain in sync history
so older snapshots cannot resurrect them. Sync does not delete documents. Text marks retain their source offsets. Freehand
and image overlays retain the reader’s normalized geometry; different typography
on reflowable ebooks can change how those overlays align with words. PDF page
geometry remains fixed.

## Security design

- Pairing uses an out-of-band, cryptographically random 128-bit secret. It is
  never sent in a network handshake. Never send it to someone you do not trust.
- Each connection uses fresh X25519 ephemeral keys and random nonces. HMAC-SHA256
  authenticates role-separated handshake transcripts with the pairing secret
  or the already paired device secret. HKDF-SHA256 derives directional session
  keys. ChaCha20-Poly1305 authenticates and encrypts all annotation transfers.
- Authenticated sequence counters and per-session keys reject replayed messages.
- Paired device secrets are held using flutter_secure_storage, not ordinary app
  preferences. Android secure storage is excluded from backup/device transfer.
  After a restore or reinstall, pair again. Lost or inaccessible keys never cause
  sync to fall back to plaintext.
- Device discovery advertises the app device label, random device ID and local
  port only while the sync screen is enabled. It carries no document metadata.
- The user explicitly enables the listener. It closes on leaving the sync screen
  or backgrounding the app. This is a direct local connection; there is no hosted
  server, analytics service or external sync endpoint.
- Unpairing revokes the remote device locally; unpair on both devices to remove
  both stored credentials. Existing local annotations remain intact.

The primitives come from the cryptography package. This application protocol is
new and has not undergone an independent security audit. Local annotations and
merge history use existing app-private storage; this feature does not add
whole-device or document encryption at rest. A compromised/unlocked device or a
trusted paired device can access annotations available to it.

## Boundaries and validation

Local IPv4 Wi-Fi/hotspot connections are supported. Some VPNs or restricted
networks interfere with discovery or direct connections. Sync is manual using
Sync now while both screens are open. There is no scheduling or background wakeup.
Network messages, annotation counts, geometry and attachments are bounded and
validated before annotation writes. Annotation snapshots are limited to 16 MB
and 30,000 historical operations per document. These limits fail visibly without
truncating data. Very image-heavy histories can exceed them.

An interrupted annotation apply has a recoverable write-ahead record, checked
locally before a reader loads annotations. Retrying
sync is idempotent. Before release, run analyzer/tests, build both Android and
Windows, and test real pairing, offline edits/deletions, interrupted sync,
wrong-code rejection and unpairing between two actual devices. Automated tests
are supplied for graph merging, crypto/authentication/replay, framed transport,
matching, cancellation and recovery; passing them does not replace that device
validation.
