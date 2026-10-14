import 'package:flutter/material.dart';

import '../core/preferences.dart';

IconData alignmentIcon(ReadingAlignment alignment) => switch (alignment) {
  ReadingAlignment.left => Icons.format_align_left,
  ReadingAlignment.right => Icons.format_align_right,
  ReadingAlignment.center => Icons.format_align_center,
  ReadingAlignment.justify => Icons.format_align_justify,
};
const readingFonts = ['Times New Roman', 'Tinos', 'sans-serif', 'monospace'];
String fontLabel(String font) => switch (font) {
  'sans-serif' => 'Sans serif',
  'monospace' => 'Monospace',
  _ => font,
};

class ReadingTypography extends StatelessWidget {
  const ReadingTypography({
    super.key,
    required this.preferences,
    this.showText = true,
  });
  final ReaderPreferences preferences;
  final bool showText;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: preferences,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          preferences.documentSpecific
              ? 'This document only'
              : 'Defaults for all documents',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (showText) ...[
          DropdownButtonFormField<String>(
            initialValue: readingFonts.contains(preferences.fontFamily)
                ? preferences.fontFamily
                : readingFonts.first,
            key: ValueKey(preferences.fontFamily),
            decoration: const InputDecoration(
              labelText: 'Reading font',
              prefixIcon: Icon(Icons.font_download_outlined),
            ),
            items: readingFonts
                .map(
                  (font) => DropdownMenuItem(
                    value: font,
                    child: Text(
                      fontLabel(font),
                      style: TextStyle(
                        fontFamily: font,
                        fontFamilyFallback: const ['Tinos'],
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: (font) {
              if (font != null) preferences.setFontFamily(font);
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'Times New Roman uses bundled Tinos on devices where Times New Roman is unavailable.',
          ),
          const SizedBox(height: 12),
          Text('Text size: ${preferences.fontSize.round()} points'),
          Slider(
            value: preferences.fontSize.clamp(16, 32),
            min: 16,
            max: 32,
            divisions: 16,
            onChanged: preferences.setFontSize,
          ),
          const Text('Text alignment'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final align in ReadingAlignment.values)
                ChoiceChip(
                  avatar: Icon(alignmentIcon(align), size: 18),
                  label: Text(align.label),
                  selected: preferences.alignment == align,
                  onSelected: (_) => preferences.setAlignment(align),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        DropdownButtonFormField<String>(
          initialValue:
              ['bestFit', 'fitWidth', 'custom'].contains(preferences.viewingFit)
              ? preferences.viewingFit
              : 'bestFit',
          key: ValueKey('fit-${preferences.viewingFit}'),
          decoration: const InputDecoration(
            labelText: 'Page viewing',
            prefixIcon: Icon(Icons.fit_screen),
          ),
          items: const [
            DropdownMenuItem(value: 'bestFit', child: Text('Best fit')),
            DropdownMenuItem(value: 'fitWidth', child: Text('Fit width')),
            DropdownMenuItem(value: 'custom', child: Text('Custom percentage')),
          ],
          onChanged: (fit) {
            if (fit != null) {
              preferences.setViewing(fit: fit, zoom: preferences.viewingZoom);
            }
          },
        ),
        if (preferences.viewingFit == 'custom')
          Slider(
            value: preferences.viewingZoom.clamp(.5, 8),
            min: .5,
            max: 8,
            divisions: 150,
            label: '${(preferences.viewingZoom * 100).round()}%',
            onChanged: (zoom) =>
                preferences.setViewing(fit: 'custom', zoom: zoom),
          ),
        if (preferences.documentSpecific)
          TextButton.icon(
            onPressed: preferences.restoreTypographyDefaults,
            icon: const Icon(Icons.restore),
            label: const Text('Use global defaults'),
          ),
        const SizedBox(height: 8),
        Text(
          preferences.viewingFit == 'bestFit'
              ? 'Best fit · automatic'
              : preferences.viewingFit == 'fitWidth'
              ? 'Fit width · automatic'
              : '${(preferences.viewingZoom * 100).round()}%',
        ),
      ],
    ),
  );
}

Future<void> showReadingTypography(
  BuildContext context,
  ReaderPreferences preferences, {
  bool showText = true,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: ReadingTypography(preferences: preferences, showText: showText),
      ),
    ),
  ),
);
