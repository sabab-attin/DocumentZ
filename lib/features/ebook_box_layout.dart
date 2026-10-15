import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import 'ebook_styles.dart';

bool _boxProperty(String key) =>
    key.startsWith('border') ||
    key.startsWith('background') ||
    key.startsWith('margin') ||
    key.startsWith('padding') ||
    {'width', 'min-width', 'max-width', 'box-sizing'}.contains(key);

bool _hasFrame(Map<String, String> styles) => styles.keys.any(
  (key) =>
      key.startsWith('border') ||
      key.startsWith('background') ||
      {'width', 'min-width', 'max-width'}.contains(key),
);

/// Custom selectable paragraphs replace their HTML element. Move their box
/// properties to a real HTML parent so the native HTML renderer can still draw
/// borders, backgrounds, width and padding without flattening the paragraph.
void prepareEbookBoxes(
  dom.Document document, {
  double? availableWidth,
  TextStyle style = const TextStyle(fontSize: 20),
  TextScaler textScaler = TextScaler.noScaling,
}) {
  for (final element in document.querySelectorAll('[data-qr-block]').toList()) {
    final values = ebookStyle(element);
    final structural = {'td', 'th', 'li'}.contains(element.localName);
    if (!_hasFrame(values) && !structural) {
      continue;
    }
    if (structural) {
      // Cells and list items must remain direct children of their table/list.
      // Keep their native box and put selectable content inside it.
      final content = dom.Element.tag('div');
      for (final attribute in [
        'data-qr-block',
        'data-book-style',
        'data-book-size',
        'data-book-lang',
      ]) {
        final value = element.attributes[attribute];
        if (value != null) {
          content.attributes[attribute] = value;
        }
      }
      content.attributes['data-book-framed'] = '1';
      content.nodes.addAll(element.nodes.toList());
      element.nodes.add(content);
      element.attributes.remove('data-qr-block');
      continue;
    }
    final frame = dom.Element.tag('div');
    frame.attributes['data-book-frame'] = '1';
    frame.attributes['data-book-style'] =
        element.attributes['data-book-style'] ?? '';
    frame.attributes['data-book-size'] =
        element.attributes['data-book-size'] ?? '1';
    frame.attributes['style'] = element.attributes['style'] ?? '';
    element.parentNode!.insertBefore(frame, element);
    frame.nodes.add(element);
    element.attributes['data-book-framed'] = '1';
    element.attributes['style'] = values.entries
        .where((entry) => !_boxProperty(entry.key))
        .map((entry) => '${entry.key}:${entry.value}')
        .join(';');
  }
  final viewportWidth = availableWidth ?? 0;
  if (!viewportWidth.isFinite || viewportWidth <= 0) {
    return;
  }
  final root = document.body;
  if (root == null) {
    return;
  }
  final minimums = <dom.Element, double>{};
  final textWidths = <dom.Element, double>{};
  double em(dom.Element element) =>
      (style.fontSize ?? 20) *
      (double.tryParse(element.attributes['data-book-size'] ?? '') ?? 1);

  InlineSpan span(dom.Node node) {
    if (node is dom.Text) {
      return TextSpan(text: node.data.replaceAll(RegExp(r'[ \t\r\n\f]+'), ' '));
    }
    if (node is! dom.Element) {
      return const TextSpan();
    }
    if (node.localName == 'br') {
      return const TextSpan(text: '\n');
    }
    return TextSpan(
      style: ebookTextStyle(node, style),
      children: node.nodes.map(span).toList(),
    );
  }

  double side(
    Map<String, String> values,
    String group,
    String name,
    double font,
    double width,
  ) {
    return ebookLength(
      _sideValue(values, group, name),
      font,
      percent: width,
    ).clamp(0.0, double.infinity).toDouble();
  }

  double minimum(dom.Element element, {bool constrained = false}) {
    final values = ebookStyle(element);
    constrained =
        constrained ||
        _hasBorder(values) ||
        values.keys.any(
          (key) => {'width', 'min-width', 'max-width'}.contains(key),
        ) ||
        side(values, 'margin', 'left', em(element), viewportWidth) +
                side(values, 'margin', 'right', em(element), viewportWidth) +
                side(values, 'padding', 'left', em(element), viewportWidth) +
                side(values, 'padding', 'right', em(element), viewportWidth) >
            viewportWidth * .2;
    if (element.attributes['data-book-framed'] == '1') {
      return 0;
    }
    if ({'img', 'image', 'svg', 'object'}.contains(element.localName)) {
      return minimums[element] = math.min(viewportWidth / 2, em(element) * 6);
    }
    if (element.attributes.containsKey('data-qr-block')) {
      if (!constrained) {
        // Ordinary prose has no fixed horizontal box to negotiate. Its normal
        // renderer will wrap it; do not shape an extra copy of every paragraph.
        return minimums[element] = 0;
      }
      final painter = TextPainter(
        text: span(element),
        textDirection: ebookDirection(element, TextDirection.ltr),
        textScaler: textScaler,
      )..layout();
      // SelectableText reserves a small caret margin beyond shaped glyphs.
      final width = painter.minIntrinsicWidth + 12;
      painter.dispose();
      textWidths[element] = width;
      return minimums[element] = width;
    }
    var inner = 0.0;
    for (final child in element.children) {
      inner = math.max(inner, minimum(child, constrained: constrained));
      // Framed leaves still contribute their unbroken word width, while their
      // outer frame owns all horizontal spacing and visual decoration.
      if (child.attributes['data-book-framed'] == '1') {
        final painter = TextPainter(
          text: span(child),
          textDirection: ebookDirection(child, TextDirection.ltr),
          textScaler: textScaler,
        )..layout();
        inner = math.max(inner, painter.minIntrinsicWidth + 12);
        child.attributes['data-book-cell-width'] =
            '${painter.minIntrinsicWidth + 12}';
        painter.dispose();
      }
    }
    textWidths[element] = inner;
    final padding =
        side(values, 'padding', 'left', em(element), viewportWidth) +
        side(values, 'padding', 'right', em(element), viewportWidth);
    return minimums[element] =
        inner + padding + _horizontalBorder(values, em(element));
  }

  minimum(root);
  const blocks = {
    'body',
    'div',
    'section',
    'article',
    'aside',
    'blockquote',
    'p',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'ul',
    'ol',
    'li',
    'dl',
    'dt',
    'dd',
    'figure',
    'figcaption',
    'table',
    'caption',
    'pre',
  };
  void fit(dom.Element element, double width) {
    if (element.attributes.containsKey('data-qr-block') &&
        ebookAlignment(element, TextAlign.start) == TextAlign.center &&
        element.text.trim().length <= 120 &&
        element.querySelector('br') != null &&
        _insideBorder(element)) {
      // Short, explicitly line-broken title labels retain their source lines.
      element.attributes['data-book-fit-label'] = '1';
    }
    if (element.attributes['data-book-framed'] == '1') {
      return;
    }
    if (!blocks.contains(element.localName)) {
      for (final child in element.children) {
        fit(child, width);
      }
      return;
    }
    final values = ebookStyle(element);
    final font = em(element);
    final border = _horizontalBorder(values, font);
    var left = side(values, 'margin', 'left', font, width);
    var right = side(values, 'margin', 'right', font, width);
    final needed = math.min(width, minimums[element] ?? 0);
    final budget = math.max(0.0, width - needed);
    if (left + right > budget && left + right > 0) {
      final factor = budget / (left + right);
      left *= factor;
      right *= factor;
    }
    final outer = math.max(1.0, width - left - right);
    final authoredPadding =
        side(values, 'padding', 'left', font, outer) +
        side(values, 'padding', 'right', font, outer);
    final extra = values['box-sizing'] == 'border-box'
        ? 0
        : authoredPadding + border;
    var used =
        (ebookLength(
                  values['width'],
                  font,
                  fallback: outer - extra,
                  percent: width,
                ) +
                extra)
            .clamp(math.min(outer, needed), outer)
            .toDouble();
    final maximum =
        ebookLength(
          values['max-width'],
          font,
          fallback: outer - extra,
          percent: width,
        ) +
        extra;
    if (maximum > 0) {
      used = math.min(used, math.max(math.min(needed, outer), maximum));
    }
    var padLeft = side(values, 'padding', 'left', font, used);
    var padRight = side(values, 'padding', 'right', font, used);
    final padBudget = math.max(
      0.0,
      used - border - math.min(textWidths[element] ?? 0, used - border),
    );
    if (padLeft + padRight > padBudget && padLeft + padRight > 0) {
      final factor = padBudget / (padLeft + padRight);
      padLeft *= factor;
      padRight *= factor;
    }
    final changes = <String, String>{
      if (_sideValue(values, 'margin', 'left') != null &&
          _sideValue(values, 'margin', 'left') != 'auto')
        'margin-left': '${left}px',
      if (_sideValue(values, 'margin', 'right') != null &&
          _sideValue(values, 'margin', 'right') != 'auto')
        'margin-right': '${right}px',
      if (values.containsKey('padding') || values.containsKey('padding-left'))
        'padding-left': '${padLeft}px',
      if (values.containsKey('padding') || values.containsKey('padding-right'))
        'padding-right': '${padRight}px',
      if (values.containsKey('width') && values['width'] != 'auto')
        'width': '${math.max(1.0, used - padLeft - padRight - border)}px',
      if (values.containsKey('max-width'))
        'max-width': '${math.max(1.0, used - padLeft - padRight - border)}px',
      if (values.containsKey('min-width'))
        'min-width':
            '${math.min(ebookLength(values['min-width'], font, percent: width), math.max(1.0, used - padLeft - padRight - border))}px',
    };
    final additions = changes.entries
        .map((entry) => '${entry.key}:${entry.value}')
        .join(';');
    element.attributes['style'] =
        '${element.attributes['style'] ?? ''};$additions';
    // The native HTML renderer consumes CSS pixels. The selectable paragraph's
    // font-relative inset helper consumes em, so do not scale these pixels twice.
    final metadata = changes.entries
        .map(
          (entry) =>
              entry.key.startsWith('margin-') ||
                  entry.key.startsWith('padding-')
              ? '${entry.key}:${double.parse(entry.value.replaceAll('px', '')) / font}em'
              : '${entry.key}:${entry.value}',
        )
        .join(';');
    element.attributes['data-book-style'] =
        '${element.attributes['data-book-style'] ?? ''};$metadata';
    final content = math.max(1.0, used - padLeft - padRight - border);
    for (final child in element.children) {
      fit(child, content);
    }
  }

  fit(root, viewportWidth);
}

bool _hasBorder(Map<String, String> values) => values.entries.any(
  (entry) =>
      entry.key.startsWith('border') &&
      RegExp(r'\b(solid|dashed|dotted|double|groove|ridge|inset|outset)\b')
          .hasMatch(entry.value),
);

String? _borderComponent(String? value, String side) {
  if (value == null || value.trim().isEmpty) return null;
  final parts = value.trim().split(RegExp(r'\s+'));
  final index = switch (side) {
    'top' => 0,
    'right' => parts.length >= 2 ? 1 : 0,
    'bottom' => parts.length >= 3 ? 2 : 0,
    _ => parts.length >= 4 ? 3 : (parts.length >= 2 ? 1 : 0),
  };
  return parts[index];
}

String? _sideValue(Map<String, String> values, String group, String side) {
  final parts = values[group]?.split(RegExp(r'\s+')) ?? [];
  final index = side == 'left'
      ? (parts.length == 4
            ? 3
            : parts.length == 1
            ? 0
            : 1)
      : (parts.length == 1 ? 0 : 1);
  return values['$group-$side'] ?? (parts.isEmpty ? null : parts[index]);
}

double _horizontalBorder(Map<String, String> values, double em) {
  if (!_hasBorder(values)) {
    return 0;
  }
  double width(String side) {
    final source =
        values['border-$side-width'] ??
        values['border-width'] ??
        values['border-$side'] ??
        values['border'] ??
        '';
    final match = RegExp(r'\b\d*\.?\d+(?:px|pt|em|rem)\b').firstMatch(source);
    return ebookLength(
      match?.group(0),
      em,
      fallback: source.contains('thick')
          ? 5
          : source.contains('thin')
          ? 1
          : 3,
    );
  }

  return width('left') + width('right');
}

/// Preserve author accent colors but keep neutral black/white frames visible
/// when switching the reading page between light and dark paper.
Map<String, String> ebookFrameTheme(dom.Element element, String ink) {
  final values = ebookStyle(element);
  final result = <String, String>{};
  for (final side in ['top', 'right', 'bottom', 'left']) {
    final source =
        values['border-$side-color'] ??
        values['border-color'] ??
        values['border-$side'] ??
        values['border'];
    if (source != null &&
        RegExp(
          r'\b(black|white|currentcolor)\b|#(?:000(?:000)?|fff(?:fff)?)(?![0-9a-f])|rgba?\(\s*(?:0\s*,\s*0\s*,\s*0|255\s*,\s*255\s*,\s*255)\s*(?:,\s*1(?:\.0)?)?\)',
          caseSensitive: false,
        ).hasMatch(source)) {
      // The HTML renderer accepts border-left/right/top/bottom shorthands,
      // but ignores border-left-color and the other side-color longhands.
      // Resolve the existing geometry before supplying a supported shorthand.
      final shorthand = values['border-$side'] ?? values['border'] ?? '';
      final width =
          values['border-$side-width'] ??
          _borderComponent(values['border-width'], side) ??
          RegExp(r'(?:\d*\.)?\d+(?:px|pt|em|rem)|\b(?:thin|medium|thick)\b')
              .firstMatch(shorthand)
              ?.group(0) ??
          '1px';
      final line =
          values['border-$side-style'] ??
          _borderComponent(values['border-style'], side) ??
          RegExp(
            r'\b(solid|dashed|dotted|double|groove|ridge|inset|outset|none|hidden)\b',
          ).firstMatch(shorthand)?.group(0) ??
          'none';
      result['border-$side'] = '$width $line #$ink';
    }
  }
  if (element.attributes['data-book-root'] == '1') {
    result['background-color'] = 'transparent';
  } else {
    final background = values['background-color'] ?? values['background'];
    if (background != null &&
        RegExp(
          r'^(white|black|#fff(?:fff)?|#000(?:000)?)$',
          caseSensitive: false,
        ).hasMatch(background.trim())) {
      result['background-color'] = ink == 'ffffff' ? '#292824' : '#f4f0e7';
    }
  }
  return result;
}

/// Inline author declarations are parsed after customStylesBuilder. Write theme
/// overrides last in the prepared inline style, so a black border cannot win.
void applyPreparedFrameTheme(dom.Document document, String ink) {
  for (final element in document.querySelectorAll('[data-book-style]')) {
    final changes = ebookFrameTheme(element, ink);
    if (changes.isNotEmpty) {
      final css = changes.entries
          .map((entry) => '${entry.key}:${entry.value}')
          .join(';');
      element.attributes['style'] = '${element.attributes['style'] ?? ''};$css';
    }
  }
}

bool _insideBorder(dom.Element element) {
  var parent = element.parent;
  while (parent != null) {
    if (_hasBorder(ebookStyle(parent))) {
      return true;
    }
    parent = parent.parent;
  }
  return false;
}
