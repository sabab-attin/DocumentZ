import '../core/desktop_platform.dart';

import 'package:flutter/services.dart';

import 'annotations.dart';
import '../data/recent_documents.dart';

import 'dart:async';

import '../data/reading_progress.dart';

import 'package:flutter/material.dart';

import '../core/preferences.dart';
import '../core/reader_platform.dart';
import '../domain/book.dart';
import '../domain/services.dart';
import 'document_reader.dart';
import 'format_reader.dart';
import 'reader_controls.dart';
import 'selection_panel.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.book,
    required this.preferences,
    this.repository,
    this.annotationMode = false,
  });
  final bool annotationMode;
  final Book book;
  final ReaderPreferences preferences;
  final LibraryRepository? repository;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  final controls = ValueNotifier<bool>(false);
  final chrome = ReaderChrome();
  late final desktopToolbar = ValueNotifier<bool>(
    widget.preferences.store?.getBool('desktop.toolbarVisible') ?? true,
  );
  void _toolbarVisibilityChanged() {
    unawaited(
      widget.preferences.store?.setBool(
        'desktop.toolbarVisible',
        desktopToolbar.value,
      ),
    );
  }

  late final _documentPreferences = ReaderPreferences.forDocument(
    widget.preferences,
    widget.book.id,
  );
  late final annotations = AnnotationStore(widget.book.id, deferred: true);
  bool _leaving = false, _confirming = false;
  Future<void> _leave() async {
    if (_confirming || _leaving) return;
    // A nested menu can veto Back without any document edits.
    if (!annotations.hasChanges) return;
    if (controls.value) {
      controls.value = false;
      return;
    }
    _confirming = true;
    try {
      final navigator = Navigator.of(context);
      final readerRoute = ModalRoute.of(context);
      final prompt = DialogRoute<String>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Save changes?'),
          content: const Text(
            'Save your annotations before leaving this document.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, 'cancel'),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog, 'discard'),
              child: const Text('Discard'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, 'save'),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      final choice = await navigator.push(prompt);
      // Closing the dialog and leaving the reader are separate route transitions.
      await prompt.completed;
      if (!mounted || choice == null || choice == 'cancel') return;
      if (choice == 'save' && !await annotations.commit()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not save changes. Please try again.'),
            ),
          );
        }
        return;
      }
      if (choice == 'discard') annotations.discard();
      if (!mounted) return;
      setState(() => _leaving = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && readerRoute?.isCurrent == true) navigator.pop();
      });
    } finally {
      _confirming = false;
    }
  }

  bool fullscreen = false;
  bool _landscape = false, _orientationBusy = false;
  Future<bool> _setLandscape(bool enabled) async {
    if (_orientationBusy) return false;
    _orientationBusy = true;
    try {
      await ReaderPlatform.landscape(enabled);
      if (!mounted) {
        await ReaderPlatform.restoreOrientation();
        return false;
      }
      setState(() {
        _landscape = enabled;
        fullscreen = enabled;
      });
      await ReaderPlatform.fullscreen(fullscreen);
      if (mounted) _activity();
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not change display orientation. Please try again.',
            ),
          ),
        );
      }
      return false;
    } finally {
      _orientationBusy = false;
    }
  }

  void _toggleFullscreen() {
    if (_landscape) {
      unawaited(_setLandscape(false));
      return;
    }
    setState(() => fullscreen = !fullscreen);
    unawaited(ReaderPlatform.fullscreen(fullscreen));
    _activity();
  }

  int _pointers = 0;
  final Map<int, Offset> _touchStarts = {};
  bool _hiding = false;
  void _preferencesChanged() {
    if (mounted) _activity();
  }

  void _menuChanged() {
    if (!_hiding) _activity();
  }

  void _activity() {
    chrome.activity(
      autoHide: !isWindowsDesktop && preferences.autoHideControls,
      delay: Duration(seconds: controls.value ? 8 : 4),
      onIdle: () {
        if (!mounted) return;
        if (ModalRoute.of(context)?.isCurrent != true ||
            FocusManager.instance.primaryFocus?.context?.widget
                is EditableText) {
          _activity();
          return;
        }
        _hiding = true;
        controls.value = false;
        _hiding = false;
      },
    );
  }

  Book get book => widget.book;
  ReaderPreferences get preferences => _documentPreferences;
  LibraryRepository? get repository => widget.repository;
  @override
  void initState() {
    super.initState();
    unawaited(annotations.load());
    unawaited(RecentDocuments.instance.record(book.id));
    WidgetsBinding.instance.addObserver(this);
    controls.addListener(_menuChanged);
    desktopToolbar.addListener(_toolbarVisibilityChanged);
    preferences.addListener(_preferencesChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _activity();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && fullscreen) {
      unawaited(ReaderPlatform.fullscreen(true));
    }
    if (state != AppLifecycleState.resumed) {
      unawaited(ReadingProgress.instance.flush());
    }
  }

  @override
  void dispose() {
    if (_landscape || _orientationBusy) {
      unawaited(ReaderPlatform.restoreOrientation());
    }
    unawaited(ReaderPlatform.fullscreen(false));
    WidgetsBinding.instance.removeObserver(this);
    unawaited(ReadingProgress.instance.flush());
    controls.removeListener(_menuChanged);
    preferences.removeListener(_preferencesChanged);
    _documentPreferences.dispose();
    controls.dispose();
    desktopToolbar.removeListener(_toolbarVisibilityChanged);
    desktopToolbar.dispose();
    chrome.dispose();
    annotations.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: preferences,
    builder: (context, _) {
      if (isWindowsDesktop || !preferences.autoHideControls) {
        chrome.hold();
        chrome.value = true;
      }
      return ListenableBuilder(
        listenable: annotations,
        builder: (context, _) => ValueListenableBuilder<bool>(
          valueListenable: controls,
          builder: (context, menuWasOpen, _) => PopScope<void>(
            canPop:
                _leaving ||
                (!annotations.hasChanges && !fullscreen && !menuWasOpen),
            onPopInvokedWithResult: (didPop, result) {
              if (didPop) return;
              if (menuWasOpen) {
                controls.value = false;
              } else if (_landscape) {
                unawaited(_setLandscape(false));
              } else if (fullscreen) {
                _toggleFullscreen();
              } else {
                unawaited(_leave());
              }
            },
            child: _content(context),
          ),
        ),
      );
    },
  );

  Widget _content(BuildContext context) => !isWindowsDesktop
      ? _readerScaffold(context)
      : CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (controls.value) {
                controls.value = false;
              } else if (fullscreen) {
                _toggleFullscreen();
              }
            },
          },
          child: Focus(autofocus: true, child: _readerScaffold(context)),
        );

  Widget _readerScaffold(BuildContext context) => Scaffold(
    body: SafeArea(
      top: !fullscreen,
      bottom: !fullscreen,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          _pointers++;
          _touchStarts[event.pointer] = event.position;
          chrome.hold();
        },
        onPointerMove: (event) {
          if ((event.position - (_touchStarts[event.pointer] ?? event.position))
                  .distance >
              12) {
            chrome.value = true;
          }
          chrome.hold();
        },
        onPointerUp: (event) {
          _touchStarts.remove(event.pointer);
          _pointers--;
          if (_pointers <= 0) {
            _pointers = 0;
            _activity();
          }
        },
        onPointerCancel: (_) {
          _touchStarts.clear();
          _pointers = 0;
          _activity();
        },
        onPointerSignal: (_) => _activity(),
        child: ReaderControlsScope(
          expanded: controls,
          preferences: preferences.globalDefaults,
          desktopToolbar: desktopToolbar,
          chrome: chrome,
          onToggleFullscreen: _toggleFullscreen,
          landscape: _landscape,
          onSetLandscape: ReaderPlatform.isAndroid ? _setLandscape : null,
          child: isWindowsDesktop
              ? Column(
                  children: [
                    AppBar(
                      title: Text(
                        book.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      actions: [
                        IconButton(
                          tooltip: fullscreen
                              ? 'Exit full screen'
                              : 'Full screen',
                          icon: Icon(
                            fullscreen
                                ? Icons.fullscreen_exit
                                : Icons.fullscreen,
                          ),
                          onPressed: _toggleFullscreen,
                        ),
                        ValueListenableBuilder<bool>(
                          valueListenable: desktopToolbar,
                          builder: (_, visible, _) => IconButton(
                            tooltip: visible ? 'Hide toolbar' : 'Show toolbar',
                            icon: Icon(
                              visible
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                            ),
                            onPressed: () => desktopToolbar.value = !visible,
                          ),
                        ),
                      ],
                    ),
                    Expanded(child: _readerBody(context)),
                  ],
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      // Keep PDF content below the normal toolbar. Auto-hide does not
                      // change this inset, so pages do not jump during ordinary taps.
                      top: !fullscreen && book.format == BookFormat.pdf
                          ? 56
                          : 0,
                      child: _readerBody(context),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: ListenableBuilder(
                        listenable: Listenable.merge([controls, chrome]),
                        builder: (context, _) {
                          final open = controls.value;
                          return (!chrome.value || fullscreen) && !open
                              ? Align(
                                  alignment: Alignment.topRight,
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (fullscreen)
                                          IconButton.filled(
                                            tooltip: _landscape
                                                ? 'Exit landscape'
                                                : 'Exit full screen',
                                            onPressed: _toggleFullscreen,
                                            icon: const Icon(
                                              Icons.fullscreen_exit,
                                            ),
                                          ),
                                        IconButton.filled(
                                          tooltip: 'Open reading menu',
                                          onPressed: () =>
                                              controls.value = true,
                                          icon: const Icon(Icons.menu),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : SizedBox(
                                  height: 56,
                                  child: AppBar(
                                    backgroundColor: readerPanelColor,
                                    foregroundColor: readerPanelInk,
                                    title: Text(
                                      book.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    actions: [
                                      IconButton(
                                        tooltip: fullscreen
                                            ? 'Exit full screen'
                                            : 'Full screen',
                                        icon: Icon(
                                          fullscreen
                                              ? Icons.fullscreen_exit
                                              : Icons.fullscreen,
                                        ),
                                        onPressed: _toggleFullscreen,
                                      ),
                                      IconButton(
                                        tooltip: open
                                            ? 'Close reading menu'
                                            : 'Open reading menu',
                                        icon: Icon(
                                          open ? Icons.close : Icons.menu,
                                        ),
                                        onPressed: () => controls.value = !open,
                                      ),
                                    ],
                                  ),
                                );
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ),
    ),
  );
  Widget _readerBody(BuildContext context) =>
      repository is ImportableLibrary &&
          (book.localPath != null || book.id.startsWith('import-'))
      ? (book.format == BookFormat.pdf || book.format == BookFormat.epub
            ? DocumentReader(
                book: book,
                repository: repository as ImportableLibrary,
                preferences: preferences,
                annotationMode: widget.annotationMode,
                annotationStore: annotations,
              )
            : FormatReader(
                book: book,
                repository: repository as ImportableLibrary,
                preferences: preferences,
                annotationMode: widget.annotationMode,
                annotationStore: annotations,
              ))
      : _sample(context);

  Widget _sample(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: ListView(
        padding: const EdgeInsets.all(28),
        children: [
          if (book.text != null)
            SelectableText(
              book.text!,
              style: TextStyle(fontSize: preferences.fontSize, height: 1.75),
            )
          else
            const Text('Document unavailable'),
        ],
      ),
    ),
  );
}
