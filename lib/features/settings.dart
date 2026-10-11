import 'package:flutter/material.dart';

import '../core/preferences.dart';
import '../core/themes.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.preferences});
  final ReaderPreferences preferences;
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
          Text(
            'Appearance',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
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
          Text(
            'Reading text size',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text('${preferences.fontSize.round()} points'),
          Semantics(
            label: 'Reading text size',
            child: Slider(
              value: preferences.fontSize,
              min: 16,
              max: 32,
              divisions: 8,
              label: '${preferences.fontSize.round()} points',
              semanticFormatterCallback: (value) => '${value.round()} points',
              onChanged: preferences.setFontSize,
            ),
          ),
          Text(
            'Text preview',
            style: TextStyle(fontSize: preferences.fontSize, height: 1.6),
          ),
          const SizedBox(height: 24),
          if (preferences.saveFailed)
            const Text(
              'Preferences work for this session, but could not be saved on this device.',
            ),
        ],
      ),
    ),
  );
}
