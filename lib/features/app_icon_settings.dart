import 'package:flutter/material.dart';

import '../core/reader_platform.dart';

class AppIconSettings extends StatefulWidget {
  const AppIconSettings({super.key});
  @override
  State<AppIconSettings> createState() => _AppIconSettingsState();
}

class _AppIconSettingsState extends State<AppIconSettings> {
  String selected = 'classic';
  bool loading = true, busy = false;
  @override
  void initState() {
    super.initState();
    if (ReaderPlatform.isAndroid) {
      _load();
    } else {
      loading = false;
    }
  }

  Future<void> _load() async {
    try {
      final value = await ReaderPlatform.currentIcon();
      if (mounted) setState(() => selected = value);
    } catch (_) {
      /* Use the original icon until the plugin becomes available. */
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _choose(String icon) async {
    if (busy || selected == icon) return;
    setState(() => busy = true);
    try {
      await ReaderPlatform.changeIcon(icon);
      if (mounted) setState(() => selected = icon);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not change the app icon. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ReaderPlatform.isAndroid) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text('App icon', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'Choose your home-screen icon. All three support themed icons when enabled in your launcher.',
        ),
        const SizedBox(height: 12),
        if (loading || busy) const LinearProgressIndicator(),
        Row(
          children: [
            for (final entry in const {
              'classic': 'Original',
              'kawaii': 'Kawaii',
              'medieval': 'Medieval',
            }.entries)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Semantics(
                    selected: selected == entry.key,
                    button: true,
                    child: Material(
                      color: selected == entry.key
                          ? Theme.of(context).colorScheme.secondaryContainer
                          : Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(18),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: loading || busy
                            ? null
                            : () => _choose(entry.key),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 4,
                          ),
                          child: Column(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.asset(
                                  'assets/app_icons/${entry.key}.jpg',
                                  width: 64,
                                  height: 64,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(entry.value),
                              const SizedBox(height: 4),
                              Icon(
                                selected == entry.key
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const Text(
          'Your launcher may take a moment to update the icon. Pinned shortcuts can retain their previous appearance.',
        ),
      ],
    );
  }
}
