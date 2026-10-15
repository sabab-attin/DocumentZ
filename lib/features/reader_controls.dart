import 'highlighter_icon.dart';
import 'text_controller_owner.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/preferences.dart';
import 'selection_panel.dart';

class ReaderControlsScope extends InheritedWidget {
  const ReaderControlsScope({
    super.key,
    required this.expanded,
    this.onToggleFullscreen,
    this.chrome,
    required super.child,
  });
  final ValueNotifier<bool> expanded;
  final ReaderChrome? chrome;
  static ReaderChrome? chromeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReaderControlsScope>()?.chrome;
  final VoidCallback? onToggleFullscreen;
  static ValueNotifier<bool>? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ReaderControlsScope>()
      ?.expanded;
  static VoidCallback? toggleFullscreenOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ReaderControlsScope>()
      ?.onToggleFullscreen;
  @override
  bool updateShouldNotify(ReaderControlsScope oldWidget) =>
      oldWidget.chrome != chrome ||
      oldWidget.expanded != expanded ||
      oldWidget.onToggleFullscreen != onToggleFullscreen;
}

/// Controls overlay the document without changing page geometry.
class ReaderControlsOverlay extends StatelessWidget {
  const ReaderControlsOverlay({
    super.key,
    required this.child,
    required this.controls,
  });
  final Widget child, controls;
  @override
  Widget build(BuildContext context) {
    final expanded = ReaderControlsScope.of(context);
    if (expanded == null) return child;
    return ValueListenableBuilder<bool>(
      valueListenable: expanded,
      builder: (context, open, _) => PopScope(
        canPop: !open,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) expanded.value = false;
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: child),
            if (open)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => expanded.value = false,
                  child: ColoredBox(color: Colors.black.withValues(alpha: .24)),
                ),
              ),
            if (open)
              Positioned(
                top: 64,
                left: 12,
                right: 12,
                bottom: 12,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) => Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, -8 * (1 - value)),
                      child: child,
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Material(
                        color: readerPanelColor,
                        elevation: 12,
                        shadowColor: Colors.black54,
                        borderRadius: BorderRadius.circular(28),
                        clipBehavior: Clip.antiAlias,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: Theme(
                            data: ThemeData.dark(useMaterial3: true),
                            child: controls,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ReaderChrome extends ValueNotifier<bool> {
  ReaderChrome() : super(true);
  Timer? _timer;
  void activity({
    bool autoHide = true,
    Duration delay = const Duration(seconds: 4),
    VoidCallback? onIdle,
  }) {
    value = true;
    _timer?.cancel();
    if (autoHide) {
      _timer = Timer(delay, () {
        value = false;
        onIdle?.call();
      });
    }
  }

  void hold() {
    _timer?.cancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class ReaderBottomBar extends StatelessWidget {
  const ReaderBottomBar({
    super.key,
    required this.preferences,
    required this.label,
    required this.onPrevious,
    required this.onNext,
    this.pageInk,
  });
  final ReaderPreferences preferences;
  final String label;
  final Color? pageInk;
  final VoidCallback? onPrevious, onNext;
  @override
  Widget build(BuildContext context) {
    final chrome = ReaderControlsScope.chromeOf(context);
    final ink = pageInk ?? readerPanelInk;
    Widget bar(bool visible) => IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Material(
              color: pageInk == null ? readerPanelColor : Colors.transparent,
              borderRadius: BorderRadius.circular(28),
              elevation: pageInk == null ? 6 : 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (preferences.showPageButtons)
                      IconButton(
                        tooltip: 'Previous page',
                        onPressed: onPrevious,
                        color: ink,
                        icon: const ReaderToolIcon(Icons.chevron_left),
                      ),
                    if (preferences.showPageIndicator)
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: ink.withValues(
                                alpha: pageInk == null ? 1 : .72,
                              ),
                              fontFamily: pageInk == null
                                  ? null
                                  : preferences.fontFamily,
                              fontSize: pageInk == null ? null : 12,
                              letterSpacing: pageInk == null ? null : .3,
                            ),
                          ),
                        ),
                      ),
                    if (preferences.showPageButtons)
                      IconButton(
                        tooltip: 'Next page',
                        onPressed: onNext,
                        color: ink,
                        icon: const ReaderToolIcon(Icons.chevron_right),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (!preferences.showPageButtons && !preferences.showPageIndicator) {
      return const SizedBox.shrink();
    }
    return chrome == null
        ? bar(true)
        : ValueListenableBuilder<bool>(
            valueListenable: chrome,
            builder: (context, visible, _) => bar(visible),
          );
  }
}

Future<void> showReaderControlOptions(
  BuildContext context,
  ReaderPreferences preferences,
) => showModalBottomSheet<void>(
  context: context,
  builder: (context) => SafeArea(
    child: ListenableBuilder(
      listenable: preferences,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text('Reader controls')),
          SwitchListTile(
            title: const Text('Hide controls when idle'),
            value: preferences.autoHideControls,
            onChanged: (value) =>
                preferences.setReaderControls(autoHide: value),
          ),
          SwitchListTile(
            title: const Text('Bottom page buttons'),
            value: preferences.showPageButtons,
            onChanged: (value) =>
                preferences.setReaderControls(pageButtons: value),
          ),
          SwitchListTile(
            title: const Text('Page indicator'),
            value: preferences.showPageIndicator,
            onChanged: (value) =>
                preferences.setReaderControls(pageIndicator: value),
          ),
        ],
      ),
    ),
  ),
);

Future<void> showReaderZoom(
  BuildContext context, {
  required double current,
  required ValueChanged<double> onZoom,
  required VoidCallback onBestFit,
  VoidCallback? onFitWidth,
  String title = 'Page fitting',
  List<int> percentages = const [50, 59, 75, 100, 125, 150, 200, 300, 400],
}) async {
  final input = TextEditingController(text: (current * 100).round().toString());
  bool inputOwnedByRoute = false;
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) {
        inputOwnedByRoute = true;
        return TextControllerOwner(
          controller: input,
          child: StatefulBuilder(
            builder: (sheet, update) => SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  20 + MediaQuery.viewInsetsOf(sheet).bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(sheet).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          label: const Text('Best fit'),
                          onPressed: () {
                            Navigator.pop(sheet);
                            onBestFit();
                          },
                        ),
                        if (onFitWidth != null)
                          ActionChip(
                            label: const Text('Fit width'),
                            onPressed: () {
                              Navigator.pop(sheet);
                              onFitWidth();
                            },
                          ),
                        for (final percent in percentages)
                          ActionChip(
                            label: Text('$percent%'),
                            onPressed: () {
                              Navigator.pop(sheet);
                              onZoom(percent / 100);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: input,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Custom percentage',
                        suffixText: '%',
                        helperText: '10–800%',
                      ),
                      onSubmitted: (value) {
                        final percent = double.tryParse(value);
                        if (percent == null || percent < 10 || percent > 800) {
                          return;
                        }
                        Navigator.pop(sheet);
                        onZoom(percent / 100);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  } finally {
    if (!inputOwnedByRoute) input.dispose();
  }
}
