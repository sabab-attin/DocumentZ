import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/services.dart';
import '../data/local_annotation_sync.dart';
import '../data/annotation_sync_session.dart';
import '../data/sync_pairing_invite.dart';
import '../data/sync_pairing_links.dart';
import 'sync_qr.dart';

class AnnotationSyncScreen extends StatefulWidget {
  const AnnotationSyncScreen({
    super.key,
    required this.repository,
    this.initialInvite,
  });
  final ImportableLibrary repository;
  final String? initialInvite;
  @override
  State<AnnotationSyncScreen> createState() => _AnnotationSyncScreenState();
}

class _AnnotationSyncScreenState extends State<AnnotationSyncScreen> {
  late final session = AnnotationSyncSession.forLibrary(widget.repository);
  late final sync = session.engine;
  bool initializing = true;
  String? failure;
  bool _scanning = false, _handlingInvite = false;
  String? _pendingInvite;
  late final bool Function(String) _linkReceiver = _receiveLink;

  bool _receiveLink(String raw) {
    if (!mounted) {
      return false;
    }
    if (initializing) {
      _pendingInvite = raw;
    } else if (_handlingInvite || _scanning || sync.busy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Finish the current scan or pairing before opening another invitation.',
          ),
        ),
      );
    } else if (failure == null) {
      unawaited(_pairInvite(raw));
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    sync.approve = _approve;
    SyncPairingLinks.receiver = _linkReceiver;
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      await session.restore();
      await sync.initialize();
    } catch (_) {
      failure = 'Secure device storage could not be opened. Sync is unavailable; local reading and annotations are unaffected.';
    }
    if (mounted) {
      setState(() => initializing = false);
      final invite = _pendingInvite ?? widget.initialInvite;
      _pendingInvite = null;
      if (invite != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _receiveLink(invite);
          }
        });
      }
    }
  }

  Future<bool> _approve(String name, String number) async {
    if (!mounted) {
      return false;
    }
    final route = DialogRoute<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Pair this device?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name),
              const SizedBox(height: 16),
              const Text(
                'Approve only if this number matches the other device:',
              ),
              const SizedBox(height: 12),
              SelectableText(
                number,
                style: Theme.of(dialog).textTheme.headlineSmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Decline'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Numbers match'),
          ),
        ],
      ),
    );
    final navigator = Navigator.of(context);
    // The route owns its fields and closes itself if the request times out.
    final timer = Timer(const Duration(seconds: 55), () {
      if (route.isActive) {
        navigator.removeRoute(route, false);
      }
    });
    try {
      final result = await navigator.push(route);
      await route.completed;
      return result == true && mounted && sync.enabled;
    } finally {
      timer.cancel();
    }
  }

  Future<void> _pair({String? address, String? peerId}) async {
    final result = await showDialog<({String address, String code})>(
      context: context,
      builder: (_) =>
          _PairDialog(initialAddress: address ?? '', paired: peerId != null),
    );
    if (result == null || !mounted || !sync.enabled) {
      return;
    }
    if (peerId == null) {
      await sync.pair(result.address, result.code);
    } else {
      await sync.syncWith(peerId, address: result.address);
    }
  }

  Future<void> _scan({required bool camera}) async {
    if (_scanning || _handlingInvite || sync.busy) {
      return;
    }
    setState(() => _scanning = true);
    try {
      final raw = camera ? await scanSyncQr() : await readSyncQrImage();
      if (raw != null && mounted) {
        await _pairInvite(raw);
      }
    } catch (error) {
      _showInviteError(error);
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
      }
    }
  }

  void _showInviteError(Object error) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error is FormatException ? error.message.toString() : 'Could not read the pairing invitation. Try QR image or manual pairing.',
        ),
      ),
    );
  }

  Future<void> _pairInvite(String raw) async {
    if (_handlingInvite || sync.busy || !mounted) {
      return;
    }
    setState(() => _handlingInvite = true);
    try {
      final invite = SyncPairingInvite.parse(raw);
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Pair with this device?'),
          content: Text(
            invite.nearbyId != null
                ? 'Connect directly to the nearby phone? Keep Wi-Fi and Bluetooth on, then approve matching verification numbers. No hotspot or shared Wi-Fi is needed.'
                : 'Connect over the local network? Compare the verification numbers before approving on the other device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Pair'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
      final direct = invite.nearbyId != null;
      if (direct && !sync.supportsNearby) {
        throw const FormatException(
          'Direct nearby pairing requires the updated Android app on both phones.',
        );
      }
      if (sync.supportsNearby && sync.usesNearby != direct) {
        await session.setEnabled(false);
        await session.setNearbyMode(direct);
      }
      if (!sync.enabled) {
        await session.setEnabled(true);
        if (!mounted) return;
        if (!sync.enabled) {
          _showInviteError(FormatException(sync.status));
          return;
        }
      }
      if (invite.nearbyId != null) {
        await sync.pairNearby(invite.nearbyId!, invite.code);
      } else {
        await sync.pairAny(invite.addresses, invite.code);
      }
      // Older versions pair first, then require a separate sync connection.
      if (sync.status.startsWith('Paired.') && mounted && sync.enabled) {
        final peers = sync.peers.where(
          (peer) => invite.addresses.contains(peer.address),
        );
        if (peers.isNotEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
          if (mounted && sync.enabled) {
            await sync.syncWith(peers.first.id);
          }
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(sync.status)));
    } catch (error) {
      _showInviteError(error);
    } finally {
      if (mounted) {
        setState(() => _handlingInvite = false);
      }
    }
  }

  Future<void> _copyPairingCode() async {
    final code = sync.pairingCode;
    if (code == null) {
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: code));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not copy the pairing code. You can enter it manually.',
            ),
          ),
        );
      }
    }
  }

  void _showSyncInfo() {
    showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Sync requirements'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Documents',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Import the exact same original file on both devices. Matching titles alone are not enough. Edited or converted copies may not match.',
              ),
              const SizedBox(height: 16),
              const Text(
                'Before syncing',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                sync.usesNearby
                    ? 'Use the updated app on both phones. Keep them nearby with Wi-Fi, Bluetooth and sync on. Allow Nearby devices access; keep Google Play services updated. No shared Wi-Fi or hotspot is needed.'
                    : 'Keep both apps open with sync on and connected to the same local network. Allow local-network access through any firewall.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Save your annotations and leave the reader before syncing. Approve pairing only when the verification numbers match.',
              ),
              const SizedBox(height: 16),
              const Text(
                'What syncs',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Saved annotations, bookmarks, drawings and note attachments. Original documents, Markdown source edits, reading positions and settings are not transferred.',
              ),
              const SizedBox(height: 8),
              const Text(
                'For later changes, tap Sync now on one device. Wait for the success message, then reopen the document to see received marks.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Conflicting edits are kept as separate marks; review overlapping copies. Ebook font or layout changes can shift drawings.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Future<void> _rename() async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _SyncNameDialog(initial: sync.name),
    );
    if (value != null && mounted) {
      await sync.rename(value);
    }
  }

  Future<void> _forget(SyncPeer peer) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Unpair device?'),
        content: Text(
          '${peer.name} will no longer be allowed to sync with this device. Existing annotations are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Unpair'),
          ),
        ],
      ),
    );
    if (result == true && mounted) {
      await sync.forget(peer.id);
    }
  }

  @override
  void dispose() {
    if (identical(SyncPairingLinks.receiver, _linkReceiver)) {
      SyncPairingLinks.receiver = null;
    }
    sync.approve = (_, _) async => false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Annotation sync'),
      actions: [
        IconButton(
          tooltip: 'Sync requirements',
          icon: const Icon(Icons.info_outline),
          onPressed: _showSyncInfo,
        ),
      ],
    ),
    body: initializing
        ? const Center(child: CircularProgressIndicator())
        : failure != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(failure!),
            ),
          )
        : ListenableBuilder(
            listenable: sync,
            builder: (context, _) => Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (sync.supportsNearby)
                      DropdownButtonFormField<bool>(
                        key: ValueKey(sync.usesNearby),
                        initialValue: sync.usesNearby,
                        decoration: const InputDecoration(
                          labelText: 'Connect to',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: true,
                            child: Text('Nearby phones'),
                          ),
                          DropdownMenuItem(
                            value: false,
                            child: Text('Computer / local network'),
                          ),
                        ],
                        onChanged:
                            sync.enabled ||
                                sync.busy ||
                                _scanning ||
                                _handlingInvite
                            ? null
                            : (value) {
                                if (value != null) {
                                  unawaited(session.setNearbyMode(value));
                                }
                              },
                      ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.devices),
                      title: Text(
                        sync.usesNearby
                            ? 'Direct nearby sync'
                            : 'Local network sync',
                      ),
                      subtitle: Text(sync.name),
                      value: sync.enabled,
                      onChanged: sync.busy && !sync.enabled
                          ? null
                          : (value) => session.setEnabled(value),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: sync.busy ? null : _rename,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Rename device'),
                      ),
                    ),
                    const Text(
                      '1. Enable sync on both devices.\n'
                      '2. Scan the other device’s QR.\n'
                      '3. Approve matching numbers.',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      sync.usesNearby
                          ? 'Keep Wi-Fi and Bluetooth on.'
                          : 'Keep both apps on the same local network.',
                    ),
                    const SizedBox(height: 16),
                    if (sync.busy) ...[
                      const LinearProgressIndicator(),
                      TextButton.icon(
                        onPressed: () => session.setEnabled(false),
                        icon: const Icon(Icons.close),
                        label: const Text('Cancel sync'),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(sync.status, semanticsLabel: sync.status),
                    ),
                    if (sync.verification.isNotEmpty) ...[
                      const Text('Pairing verification'),
                      SelectableText(
                        sync.verification,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (sync.enabled) ...[
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: sync.busy || _scanning || _handlingInvite
                                ? null
                                : () => _scan(camera: true),
                            icon: const Icon(Icons.qr_code_scanner),
                            label: const Text('Scan QR code'),
                          ),
                          TextButton.icon(
                            onPressed: sync.busy || _scanning || _handlingInvite
                                ? null
                                : () => _scan(camera: false),
                            icon: const Icon(Icons.image_outlined),
                            label: const Text('Read QR from image'),
                          ),
                        ],
                      ),
                      if (sync.usesNearby)
                        OutlinedButton.icon(
                          onPressed: sync.busy ? null : sync.allowPairing,
                          icon: const Icon(Icons.qr_code),
                          label: const Text('New pairing QR'),
                        ),
                      if (!sync.usesNearby) ...[
                        const Text('This device’s local address'),
                        for (final address in sync.addresses)
                          SelectableText(address),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: sync.busy ? null : sync.allowPairing,
                              icon: const Icon(Icons.add_link),
                              label: const Text('Show pairing code'),
                            ),
                            OutlinedButton.icon(
                              onPressed: sync.busy ? null : () => _pair(),
                              icon: const Icon(Icons.link),
                              label: const Text('Pair by address'),
                            ),
                          ],
                        ),
                      ],
                      if (sync.pairingCode != null &&
                          (sync.addresses.isNotEmpty ||
                              sync.nearbyPairingId != null))
                        Center(
                          child: SyncQrCode(
                            value: SyncPairingInvite(
                              addresses: sync.addresses,
                              nearbyId: sync.nearbyPairingId,
                              code: sync.pairingCode!,
                            ).encode(),
                          ),
                        ),
                      if (sync.pairingCode != null && sync.usesNearby)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'QR expires in 10 minutes. Keep it private.',
                          ),
                        ),
                      if (sync.pairingCode != null && !sync.usesNearby)
                        Card.outlined(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'One-time code · Expires in 10 minutes. Keep it private.',
                                ),
                                const SizedBox(height: 12),
                                SelectableText(
                                  sync.pairingCode!,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                TextButton.icon(
                                  onPressed: _copyPairingCode,
                                  icon: const Icon(Icons.copy),
                                  label: const Text('Copy pairing code'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      if (!sync.usesNearby) ...[
                        Text(
                          'Nearby devices',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (sync.nearby.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'No devices found. Try Pair by address.',
                            ),
                          ),
                        for (final device in sync.nearby)
                          Card.outlined(
                            child: ListTile(
                              leading: const Icon(Icons.devices_other),
                              title: Text(device.name),
                              subtitle: Text(device.address),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: sync.busy
                                  ? null
                                  : () => _pair(
                                      address: device.address,
                                      peerId:
                                          sync.peers.any(
                                            (peer) => peer.id == device.id,
                                          )
                                          ? device.id
                                          : null,
                                    ),
                            ),
                          ),
                      ],
                    ],
                    const SizedBox(height: 20),
                    Text(
                      'Paired devices',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (sync.peers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('No paired devices yet.'),
                      ),
                    for (final peer in sync.peers)
                      Card.outlined(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                peer.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (peer.lastSync > 0)
                                Text(
                                  'Last synced: ${DateTime.fromMillisecondsSinceEpoch(peer.lastSync).toLocal().toString().split('.').first}',
                                ),
                              Wrap(
                                spacing: 8,
                                children: [
                                  TextButton.icon(
                                    onPressed: !sync.enabled || sync.busy
                                        ? null
                                        : () => sync.syncWith(peer.id),
                                    icon: const Icon(Icons.sync),
                                    label: const Text('Sync now'),
                                  ),
                                  if (!sync.usesNearby &&
                                      !peer.address.startsWith('nearby:'))
                                    TextButton.icon(
                                      onPressed: !sync.enabled || sync.busy
                                          ? null
                                          : () => _pair(
                                              address: peer.address,
                                              peerId: peer.id,
                                            ),
                                      icon: const Icon(
                                        Icons.edit_location_alt_outlined,
                                      ),
                                      label: const Text('Change address'),
                                    ),
                                  TextButton.icon(
                                    onPressed: sync.busy
                                        ? null
                                        : () => _forget(peer),
                                    icon: const Icon(Icons.link_off),
                                    label: const Text('Unpair'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
  );
}

class _PairDialog extends StatefulWidget {
  const _PairDialog({required this.initialAddress, required this.paired});
  final String initialAddress;
  final bool paired;
  @override
  State<_PairDialog> createState() => _PairDialogState();
}

class _PairDialogState extends State<_PairDialog> {
  late final address = TextEditingController(text: widget.initialAddress);
  final code = TextEditingController();
  @override
  void dispose() {
    address.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.paired ? 'Connect to paired device' : 'Pair another device',
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: address,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Local address',
              hintText: '192.168.1.20:45831',
            ),
          ),
          if (!widget.paired) ...[
            const SizedBox(height: 16),
            TextField(
              controller: code,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'One-time pairing code',
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, (
          address: address.text.trim(),
          code: code.text.trim(),
        )),
        child: Text(widget.paired ? 'Sync' : 'Pair'),
      ),
    ],
  );
}

class _SyncNameDialog extends StatefulWidget {
  const _SyncNameDialog({required this.initial});
  final String initial;
  @override
  State<_SyncNameDialog> createState() => _SyncNameDialogState();
}

class _SyncNameDialogState extends State<_SyncNameDialog> {
  late final input = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Device name'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: input,
            maxLength: 48,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const Text('Visible to nearby devices while local sync is enabled.'),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, input.text.trim()),
        child: const Text('Save'),
      ),
    ],
  );
}
