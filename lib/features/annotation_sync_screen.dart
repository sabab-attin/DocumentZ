import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/services.dart';
import '../data/local_annotation_sync.dart';

class AnnotationSyncScreen extends StatefulWidget {
  const AnnotationSyncScreen({super.key, required this.repository});
  final ImportableLibrary repository;
  @override
  State<AnnotationSyncScreen> createState() => _AnnotationSyncScreenState();
}

class _AnnotationSyncScreenState extends State<AnnotationSyncScreen>
    with WidgetsBindingObserver {
  late final sync = LocalAnnotationSync(widget.repository, approve: _approve);
  bool initializing = true;
  String? failure;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      await sync.initialize();
    } catch (_) {
      failure = 'Secure device storage could not be opened. Sync is unavailable; local reading and annotations are unaffected.';
    }
    if (mounted) {
      setState(() => initializing = false);
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(sync.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    sync.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Annotation sync')),
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
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.devices),
                      title: const Text('Local Wi-Fi sync'),
                      subtitle: Text(sync.name),
                      value: sync.enabled,
                      onChanged: sync.busy && !sync.enabled
                          ? null
                          : (value) => value ? sync.start() : sync.stop(),
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
                      'Keep this screen open on both devices, connected to the same Wi-Fi or hotspot. Tap Sync now on one device. No internet or account is needed.',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Only saved annotations and bookmarks for identical documents are exchanged. Original documents stay on each device.',
                    ),
                    const SizedBox(height: 16),
                    if (sync.busy) ...[
                      const LinearProgressIndicator(),
                      TextButton.icon(
                        onPressed: sync.stop,
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
                      if (sync.pairingCode != null)
                        Card.outlined(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Enter this one-time code on your other device. It expires in 5 minutes. Keep it private.',
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
                      Text(
                        'Nearby devices',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (sync.nearby.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'No devices found yet. You can also enter the other device’s local address.',
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
                    const SizedBox(height: 20),
                    Text(
                      'Paired devices',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (sync.peers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No paired devices. Enable sync on both devices to pair them.',
                        ),
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
                    const SizedBox(height: 20),
                    const Text(
                      'Conflicting edits are preserved as separate marks. A concurrent deletion does not erase an edit. Review overlapping marks after a conflict.',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Device discovery shares only your app device label, random device ID and local listening port while this screen is enabled. Pairing keys are stored using the device’s secure storage.',
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
