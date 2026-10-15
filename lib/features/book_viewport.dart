import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class BookPageController extends ChangeNotifier {
  final _views = <RenderBookLeaf>{};
  int page = 0, count = 1, columns = 1;
  double fraction = 0;
  bool ready = false;
  double? _restore;
  ({RenderObject target, int? textOffset})? _pendingReveal;
  bool _disposed = false;
  bool turn(int direction) {
    _pendingReveal = null;
    final last = count > 0 ? ((count - 1) ~/ columns) * columns : 0;
    final next = (page + direction * columns).clamp(0, last).toInt();
    if (next == page) {
      return false;
    }
    page = next;
    _layout();
    return true;
  }

  void _layout() {
    for (final view in _views) {
      view.markNeedsLayout();
    }
  }

  void restore(double value) {
    _pendingReveal = null;
    _restore = value.clamp(0, 1);
    _layout();
  }

  void reveal(RenderObject target, {int? textOffset}) {
    if (!target.attached) {
      return;
    }
    RenderObject? parent = target.parent;
    while (parent != null && parent is! RenderBookLeaf) {
      parent = parent.parent;
    }
    if (parent is! RenderBookLeaf ||
        parent.child == null ||
        parent.controller != this) {
      return;
    }
    final view = parent;
    // An explicit link/search jump takes priority over chapter position restore.
    _restore = null;
    if (!ready || view._dirtyBreaks || view._measurementScheduled) {
      _pendingReveal = (target: target, textOffset: textOffset);
      return;
    }
    _pendingReveal = null;
    Rect? local;
    RenderObject actual = target;
    if (textOffset != null) {
      void find(RenderObject object) {
        if (local != null) {
          return;
        }
        if (object is RenderEditable && object.text != null) {
          final length = object.text!.toPlainText().length;
          if (length > 0) {
            final offset = textOffset.clamp(0, length - 1);
            final boxes = object.getBoxesForSelection(
              TextSelection(baseOffset: offset, extentOffset: offset + 1),
            );
            if (boxes.isNotEmpty) {
              local = boxes.first.toRect();
              actual = object;
            }
          }
        } else {
          object.visitChildren(find);
        }
      }

      find(target);
    }
    final actualRender = actual;
    final rect = MatrixUtils.transformRect(
      actualRender.getTransformTo(view.child),
      local ??
          (actualRender is RenderBox
              ? Offset.zero & actualRender.size
              : Rect.zero),
    );
    page = view.pageForOffset(rect.top);
    if (columns == 2) {
      page -= page % 2;
    }
    _layout();
  }

  void _changed() {
    if (!_disposed) {
      // This notification runs after layout, when descendant transforms and
      // the final page boundaries can safely be used to locate a link target.
      final pending = _pendingReveal;
      if (ready && pending != null) {
        _pendingReveal = null;
        reveal(pending.target, textOffset: pending.textOffset);
      }
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pendingReveal = null;
    _views.clear();
    super.dispose();
  }
}

/// Reserve the header/menu and footer even when controls auto-hide. Layout uses
/// actual available height, including changes to system bars and split screen.
EdgeInsets ebookPageInsets(Size viewport, int columns, EdgeInsets safe) {
  final top = math.min(
    88.0 + safe.top,
    math.max(64.0 + safe.top, viewport.height * .16),
  );
  final bottom = math.min(
    64.0 + safe.bottom,
    math.max(40.0 + safe.bottom, viewport.height * .10),
  );
  return EdgeInsets.fromLTRB(
    columns == 2 ? 18 : 24,
    top,
    columns == 2 ? 18 : 24,
    bottom,
  );
}

/// Each leaf has its own live HTML tree and composited layers. Source paragraph
/// identities are shared, but selection keys are unique to each visible leaf.
class BookViewport extends StatelessWidget {
  const BookViewport({
    super.key,
    required this.controller,
    required this.columns,
    required this.paper,
    required this.layoutToken,
    required this.builder,
  });
  final BookPageController controller;
  final int columns;
  final Color paper;
  final Object layoutToken;
  final Widget Function(int column, double pageHeight) builder;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => SizedBox(
      child: Row(
        children: [
          for (var column = 0; column < columns; column++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  columns == 2 ? 18 : 24,
                  ebookPageInsets(
                    Size(bounds.maxWidth, bounds.maxHeight),
                    columns,
                    MediaQuery.paddingOf(context),
                  ).top,
                  columns == 2 ? 18 : 24,
                  ebookPageInsets(
                    Size(bounds.maxWidth, bounds.maxHeight),
                    columns,
                    MediaQuery.paddingOf(context),
                  ).bottom,
                ),
                child: _BookLeaf(
                  controller: controller,
                  column: column,
                  columns: columns,
                  layoutToken: layoutToken,
                  child: builder(
                    column,
                    math.max(
                      1.0,
                      bounds.maxHeight -
                          ebookPageInsets(
                            Size(bounds.maxWidth, bounds.maxHeight),
                            columns,
                            MediaQuery.paddingOf(context),
                          ).vertical,
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

class _BookLeaf extends SingleChildRenderObjectWidget {
  const _BookLeaf({
    required this.controller,
    required this.column,
    required this.columns,
    required this.layoutToken,
    required super.child,
  });
  final BookPageController controller;
  final int column, columns;
  final Object layoutToken;
  @override
  RenderBookLeaf createRenderObject(BuildContext context) =>
      RenderBookLeaf(controller, column, columns, layoutToken);
  @override
  void updateRenderObject(BuildContext context, RenderBookLeaf renderObject) {
    renderObject.update(controller, column, columns, layoutToken);
  }
}

class BookAtomic extends SingleChildRenderObjectWidget {
  const BookAtomic({super.key, required super.child});
  @override
  RenderBookAtomic createRenderObject(BuildContext context) =>
      RenderBookAtomic();
}

class RenderBookAtomic extends RenderProxyBox {
  Size laidOutSize = Size.zero;

  @override
  void performLayout() {
    super.performLayout();
    // Publish plain geometry while this render box is allowed to read its size.
    // The paginator is an ancestor, not the immediate layout parent.
    laidOutSize = Size(size.width, size.height);
  }
}

class RenderBookLeaf extends RenderProxyBox {
  RenderBookLeaf(this.controller, this.column, this.columns, this.layoutToken);
  BookPageController controller;
  int column, columns;
  Object layoutToken;
  List<double> starts = [0];
  Size? _previousSize;
  double _contentHeight = -1, _paginationHeight = -1;
  bool _dirtyBreaks = true, _notifyScheduled = false;
  bool _measurementScheduled = false;
  void update(
    BookPageController next,
    int nextColumn,
    int nextColumns,
    Object token,
  ) {
    if (controller != next) {
      controller._views.remove(this);
      controller = next;
      if (attached) {
        controller._views.add(this);
      }
    }
    if (columns != nextColumns || layoutToken != token) {
      if (column == 0) {
        controller._restore ??= controller.fraction;
      }
      _dirtyBreaks = true;
    }
    column = nextColumn;
    columns = nextColumns;
    layoutToken = token;
    markNeedsLayout();
  }

  int pageForOffset(double y) {
    for (var i = starts.length - 1; i >= 0; i--) {
      if (y >= starts[i] - .01) {
        return i;
      }
    }
    return 0;
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    if (child == null || size.isEmpty) {
      if (column == 0) {
        controller.ready = false;
      }
      return;
    }
    child!.layout(
      BoxConstraints.tightFor(width: size.width),
      parentUsesSize: true,
    );
    final reportedHeight = child!.size.height;
    if (_dirtyBreaks ||
        _previousSize != size ||
        _contentHeight != reportedHeight) {
      if (column == 0) {
        controller.ready = false;
      }
      if (!_measurementScheduled) {
        _measurementScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _measurementScheduled = false;
          if (attached && child != null && hasSize && !size.isEmpty) {
            _measurePages();
          }
        });
      }
      return;
    }
    _publishPage();
  }

  void _measurePages() {
    // Descendant transforms may consult their own sizes. Inspect the completed
    // tree after layout, when those reads are legal for every render object.
    var height = child!.size.height;
    final oldY = starts[math.min(controller.page, starts.length - 1)];
    final intervals = <Rect>[];
    void inspect(RenderObject object) {
      if (object is RenderEditable || object is RenderParagraph) {
        final span = object is RenderEditable
            ? object.text
            : (object as RenderParagraph).text;
        final text = span?.toPlainText() ?? '';
        if (text.isNotEmpty) {
          final selection = TextSelection(
            baseOffset: 0,
            extentOffset: text.length,
          );
          final boxes = object is RenderEditable
              ? object.getBoxesForSelection(selection)
              : (object as RenderParagraph).getBoxesForSelection(selection);
          final transform = object.getTransformTo(child);
          for (final box in boxes) {
            final rect = MatrixUtils.transformRect(transform, box.toRect());
            if (rect.height > .1) {
              intervals.add(rect);
            }
          }
        }
        // Inline image widgets can live below a paragraph as placeholders.
        // Inspect them as well so page cuts never split their artwork.
        object.visitChildren(inspect);
        return;
      }
      final Size? mediaSize = switch (object) {
        RenderBookAtomic atomic => atomic.laidOutSize,
        RenderImage image => image.getDryLayout(image.constraints),
        _ => null,
      };
      if (mediaSize != null && mediaSize.height <= size.height + .01) {
        intervals.add(
          MatrixUtils.transformRect(
            object.getTransformTo(child),
            Offset.zero & mediaSize,
          ),
        );
        return;
      }
      object.visitChildren(inspect);
    }

    inspect(child!);
    // Text can paint beyond a publisher wrapper's reported box. Never let
    // that box silently discard the remaining lines from the page count.
    for (final rect in intervals) {
      height = math.max(height, rect.bottom);
    }

    intervals.sort((a, b) => a.top.compareTo(b.top));
    final next = <double>[0];
    var start = 0.0;
    while (start + size.height < height - .5) {
      var cut = start + size.height;
      for (final rect in intervals.reversed) {
        if (rect.top >= cut) {
          continue;
        }
        if (rect.top > start + .5 && rect.bottom > cut + .01) {
          cut = rect.top;
        }
      }
      next.add(cut);
      start = cut;
    }
    starts = next;
    if (column == 0 && controller._restore == null) {
      controller.page = pageForOffset(oldY);
    }
    _previousSize = Size(size.width, size.height);
    _contentHeight = child!.size.height;
    _paginationHeight = height;
    _dirtyBreaks = false;
    markNeedsLayout();
  }

  void _publishPage() {
    if (column != 0) {
      return;
    }
    if (controller._restore != null) {
      controller.page = pageForOffset(
        controller._restore! * math.max(0.0, _paginationHeight - size.height),
      );
      controller._restore = null;
    }
    controller.page = controller.page.clamp(0, starts.length - 1);
    if (columns == 2) {
      controller.page -= controller.page % 2;
    }
    final becameReady = !controller.ready;
    controller.count = starts.length;
    controller.columns = columns;
    controller.ready = true;
    final fraction = starts.length <= 1
        ? 0.0
        : (starts[controller.page] /
                  math.max(1.0, _paginationHeight - size.height))
              .clamp(0.0, 1.0);
    controller.fraction = fraction;
    final signature = (controller.page, starts.length, columns, fraction);
    if ((_lastNotification != signature || becameReady) && !_notifyScheduled) {
      _lastNotification = signature;
      _notifyScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _notifyScheduled = false;
        controller._changed();
      });
    }
  }

  Object? _lastNotification;
  bool get _visible => controller.page + column < starts.length;
  Rect get visiblePageRect {
    final index = controller.page + column;
    final height = index + 1 < starts.length
        ? math.min(size.height, starts[index + 1] - starts[index])
        : size.height;
    return Rect.fromLTWH(0, 0, size.width, height);
  }

  Offset get _offset =>
      Offset(0, -starts[math.min(controller.page + column, starts.length - 1)]);
  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null && _visible) {
      context.pushClipRect(
        needsCompositing,
        offset,
        visiblePageRect,
        (context, offset) => context.paintChild(child!, offset + _offset),
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      child != null &&
      _visible &&
      visiblePageRect.contains(position) &&
      result.addWithPaintOffset(
        offset: _offset,
        position: position,
        hitTest: (result, transformed) =>
            child!.hitTest(result, position: transformed),
      );
  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(_offset.dx, _offset.dy, 0, 1);
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) => visiblePageRect;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    controller._views.add(this);
  }

  @override
  void detach() {
    controller._views.remove(this);
    super.detach();
  }
}
