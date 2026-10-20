import 'highlighter_icon.dart';

import 'package:flutter/services.dart';

import '../core/desktop_platform.dart';
import '../core/reader_shortcuts.dart';
import 'text_controller_owner.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/preferences.dart';
import 'selection_panel.dart';

class ReaderControlsScope extends InheritedWidget {
  const ReaderControlsScope({
    super.key,
    required this.expanded,
    this.preferences,
    this.desktopToolbar,
    this.onToggleFullscreen,
    this.chrome,
    this.landscape = false,
    this.onSetLandscape,
    required super.child,
  });
  final ValueNotifier<bool> expanded;
  final ReaderPreferences? preferences;
  final ValueNotifier<bool>? desktopToolbar;
  static ReaderControlsScope? scopeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReaderControlsScope>();
  final ReaderChrome? chrome;
  final bool landscape;
  final Future<bool> Function(bool)? onSetLandscape;
  static bool landscapeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ReaderControlsScope>()
          ?.landscape ??
      false;
  static Future<bool> Function(bool)? setLandscapeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ReaderControlsScope>()
          ?.onSetLandscape;
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
      oldWidget.preferences != preferences ||
      oldWidget.desktopToolbar != desktopToolbar ||
      oldWidget.chrome != chrome ||
      oldWidget.landscape != landscape ||
      oldWidget.onSetLandscape != onSetLandscape ||
      oldWidget.expanded != expanded ||
      oldWidget.onToggleFullscreen != onToggleFullscreen;
}

Future<String?> showReaderDisplayModes(
  BuildContext context, {
  required String selected,
  required List<String> modes,
}) async {
  final landscape = ReaderControlsScope.landscapeOf(context);
  final setLandscape = ReaderControlsScope.setLandscapeOf(context);
  final mode = await showModalBottomSheet<String>(
    context: context,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final name in modes)
              ListTile(
                title: Text(name),
                selected: selected == name,
                onTap: () => Navigator.pop(sheet, name),
              ),
            if (setLandscape != null)
              ListTile(
                leading: const Icon(Icons.screen_rotation),
                title: Text(landscape ? 'Exit landscape' : 'Landscape'),
                subtitle: Text(
                  landscape ? 'Return to normal view' : 'Full screen',
                ),
                selected: landscape,
                onTap: () => Navigator.pop(sheet, 'readerLandscape'),
              ),
          ],
        ),
      ),
    ),
  );
  if (mode == 'readerLandscape') {
    if (context.mounted) await setLandscape?.call(!landscape);
    return null;
  }
  return mode;
}

/// Controls overlay the document without changing page geometry.
class ReaderControlsOverlay extends StatefulWidget {
  const ReaderControlsOverlay({
    super.key,
    required this.child,
    required this.controls,
    this.onTurn,
  });
  final Future<void> Function(int)? onTurn;
  final Widget child, controls;
  @override
  State<ReaderControlsOverlay> createState() => _ReaderControlsOverlayState();
}

class _ReaderControlsOverlayState extends State<ReaderControlsOverlay> {
  final _actions = <String, VoidCallback?>{};
  final _fallbackShortcuts = ReaderShortcuts(null);
  bool _keys(KeyEvent event) {
    if (!mounted ||
        !isWindowsDesktop ||
        event is KeyUpEvent ||
        ModalRoute.of(context)?.isCurrent == false ||
        readerIsEditingText()) {
      return false;
    }
    final scope = ReaderControlsScope.scopeOf(context);
    final command =
        (scope?.preferences?.globalDefaults.shortcuts ?? _fallbackShortcuts)
            .match(event);
    if (command == null ||
        command == ReaderCommand.next ||
        command == ReaderCommand.previous) {
      return false;
    }
    if (command == ReaderCommand.fullscreen &&
        scope?.onToggleFullscreen != null) {
      scope!.onToggleFullscreen!();
      return true;
    }
    if (command == ReaderCommand.toolbar) {
      final visible = scope?.desktopToolbar;
      if (visible != null) visible.value = !visible.value;
      return true;
    }
    final callback = _actions[command.label];
    if (!_actions.containsKey(command.label)) return false;
    callback?.call();
    return true;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_keys);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_keys);
    _fallbackShortcuts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child, controls = widget.controls;
    if (isWindowsDesktop) {
      final visibility = ReaderControlsScope.scopeOf(context)?.desktopToolbar;
      Widget desktop(bool visible) => Column(
        children: [
          Offstage(
            offstage: !visible,
            child: Material(
              elevation: 1,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .4,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: DesktopActionsScope(
                    actions: _actions,
                    child: controls,
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      );
      final content = visibility == null
          ? desktop(true)
          : ValueListenableBuilder<bool>(
              valueListenable: visibility,
              builder: (_, visible, _) => desktop(visible),
            );
      return Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is KeyUpEvent ||
              readerIsEditingText() ||
              widget.onTurn == null) {
            return KeyEventResult.ignored;
          }
          final command =
              (ReaderControlsScope.scopeOf(context)
                          ?.preferences
                          ?.globalDefaults
                          .shortcuts ??
                      _fallbackShortcuts)
                  .match(event);
          if (command != ReaderCommand.next &&
              command != ReaderCommand.previous) {
            return KeyEventResult.ignored;
          }
          unawaited(widget.onTurn!(command == ReaderCommand.next ? 1 : -1));
          return KeyEventResult.handled;
        },
        child: content,
      );
    }
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
    this.onPageTap,
  });
  final ReaderPreferences preferences;
  final String label;
  final Color? pageInk;
  final VoidCallback? onPageTap;
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
                        child: InkWell(
                          onTap: onPageTap,
                          borderRadius: BorderRadius.circular(24),
                          child: Tooltip(
                            message: onPageTap == null ? '' : 'Go to page',
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
                        helperText:
                            '10ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œ800%',
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

Future<int?> showReaderPageNumber(
  BuildContext context, {
  required int current,
  required int count,
  String title = 'Go to page',
}) {
  final input = TextEditingController(text: '$current');
  input.selection = TextSelection(
    baseOffset: 0,
    extentOffset: input.text.length,
  );
  return showDialog<int>(
    context: context,
    builder: (dialog) => TextControllerOwner(
      controller: input,
      child: StatefulBuilder(
        builder: (dialog, update) {
          final number = int.tryParse(input.text.trim());
          final valid = number != null && number >= 1 && number <= count;
          void submit() {
            final latest = int.tryParse(input.text.trim());
            if (latest != null && latest >= 1 && latest <= count) {
              Navigator.pop(dialog, latest);
            }
          }

          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 260,
              child: TextField(
                autofocus: true,
                controller: input,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Page',
                  helperText: '1 - $count',
                  errorText: valid ? null : 'Enter a number from 1 to $count',
                ),
                onChanged: (_) => update(() {}),
                onSubmitted: (_) => submit(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: valid ? submit : null,
                child: const Text('Go'),
              ),
            ],
          );
        },
      ),
    ),
  );
}

/// Paged documents have no continuous scroll extent. This rail maps directly to
/// their actual pages; continuous views use their native scroll controller.
class DesktopPageRail extends StatelessWidget {
  const DesktopPageRail({
    super.key,
    required this.current,
    required this.count,
    required this.onPage,
  });
  final int current, count;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) => !isWindowsDesktop || count <= 1
      ? const SizedBox.shrink()
      : SizedBox(
          width: 16,
          child: LayoutBuilder(
            builder: (context, bounds) {
              final thumb = (bounds.maxHeight * .25).clamp(0.0, 40.0);
              final travel = (bounds.maxHeight - thumb).clamp(
                1.0,
                double.infinity,
              );
              void seek(double y) => onPage(
                ((y - thumb / 2) / travel * (count - 1)).round().clamp(
                  0,
                  count - 1,
                ),
              );
              return Semantics(
                label: 'Document scrollbar',
                value: '${current + 1} of $count',
                increasedValue: current < count - 1
                    ? '${current + 2} of $count'
                    : null,
                decreasedValue: current > 0 ? '$current of $count' : null,
                onIncrease: current < count - 1
                    ? () => onPage(current + 1)
                    : null,
                onDecrease: current > 0 ? () => onPage(current - 1) : null,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (e) => seek(e.localPosition.dy),
                    onVerticalDragStart: (e) => seek(e.localPosition.dy),
                    onVerticalDragUpdate: (e) => seek(e.localPosition.dy),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ColoredBox(
                            color: Theme.of(context).colorScheme.onSurface
                                .withValues(alpha: .05),
                          ),
                        ),
                        Positioned(
                          top:
                              current.clamp(0, count - 1) /
                              (count - 1) *
                              travel,
                          left: 4,
                          right: 3,
                          height: thumb,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.onSurface
                                  .withValues(alpha: .5),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
}
