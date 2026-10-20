import '../core/desktop_platform.dart';
import 'app_updates.dart';
import 'keyboard_shortcuts_settings.dart';
import '../domain/services.dart';
import '../data/local_annotation_sync.dart';
import 'annotation_sync_screen.dart';

import 'package:flutter/material.dart';

import '../core/preferences.dart';
import '../core/themes.dart';
import 'reading_typography.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.preferences,
    this.showTextOptions = true,
    this.repository,
  });
  final ReaderPreferences preferences;
  final bool showTextOptions;
  final LibraryRepository? repository;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: preferences,
    builder: (context, _) => _content(context),
  );

  Widget _content(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 16),
          Text('Appearance', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),

          const SizedBox(height: 24),
          const SizedBox(height: 12),
          ...ReaderTheme.values.map(
            (theme) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Semantics(
                selected: preferences.theme == theme,
                child: Card.outlined(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.ink),
                      ),
                      child: Icon(
                        Icons.text_fields,
                        color: theme.ink,
                        size: 22,
                      ),
                    ),
                    title: Text(theme.label),

                    trailing: Icon(
                      preferences.theme == theme
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    onTap: () => preferences.setTheme(theme),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Page dark mode'),
            value: preferences.pageDark,
            onChanged: preferences.setPageDark,
          ),
          const SizedBox(height: 16),
          ReadingTypography(
            preferences: preferences,
            showText: showTextOptions,
          ),
          if (!preferences.documentSpecific &&
              localSyncAvailable &&
              repository is ImportableLibrary)
            Card.outlined(
              child: ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Annotation sync'),
                subtitle: const Text('Sync annotations between devices'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => AnnotationSyncScreen(
                      repository: repository as ImportableLibrary,
                    ),
                  ),
                ),
              ),
            ),
          if (!preferences.documentSpecific && !isWindowsDesktop)
            const AppUpdatesSettings(),
          if (isWindowsDesktop)
            KeyboardShortcutsSettings(
              shortcuts: preferences.globalDefaults.shortcuts,
            ),
          if (preferences.saveFailed)
            const Text(
              'Preferences work for this session, but could not be saved on this device.',
            ),
        ],
      ),
    ),
  );
}
