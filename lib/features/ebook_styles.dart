import 'dart:convert';
import 'dart:typed_data';

import 'package:csslib/parser.dart' as css;
import 'package:csslib/visitor.dart' as css;
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../data/epub_document.dart';

/// Resolve only styles stored in the book. Never fetch a stylesheet or execute
/// publisher scripts. Keep the original elements and annotation block identities.
void applyEbookStyles(
  dom.Document document,
  String path,
  Map<String, Uint8List> resources,
) {
  final cascade = <dom.Element, Map<String, ({int priority, String value})>>{};
  final loaded = <String>{};
  void declarations(
    dom.Element element,
    Iterable<css.TreeNode> nodes,
    int specificity,
  ) {
    final values = cascade.putIfAbsent(element, () => {});
    for (final node in nodes.whereType<css.Declaration>()) {
      final property = node.property.toLowerCase();
      final expression = node.expression;
      if (expression == null) {
        continue;
      }
      // Source spans on numeric terms can omit their CSS unit. Serialize the
      // expression tree so em/rem/px/pt/% and shorthand values stay intact.
      final printer = css.CssPrinter();
      expression.visit(printer);
      final value = printer.toString();
      if (value.isEmpty) {
        continue;
      }
      final priority = (node.important ? 1000000000 : 0) + specificity;
      final previous = values[property];
      if (previous == null || priority >= previous.priority) {
        values[property] = (priority: priority, value: value);
      }
    }
  }

  late void Function(String source, String base, int depth) stylesheet;
  stylesheet = (source, base, depth) {
    if (depth > 12) {
      return;
    }
    final sheet = css.parse(source);
    for (final node in sheet.topLevels) {
      if (node is css.ImportDirective) {
        final reference = epubResourcePath(base, node.import);
        final bytes = resources[reference];
        if (bytes != null && loaded.add(reference)) {
          stylesheet(
            utf8.decode(bytes, allowMalformed: true),
            reference,
            depth + 1,
          );
        }
      } else if (node is css.RuleSet) {
        for (final selector
            in node.selectorGroup?.selectors ?? <css.Selector>[]) {
          final query = selector.span?.text.trim();
          if (query == null || query.isEmpty || query.contains('::')) {
            continue;
          }
          // CSS specificity, with stylesheet source order as the tiebreaker.
          final ids = RegExp(r'#[\w-]+').allMatches(query).length;
          final classes = RegExp(r'\.[\w-]+|\[[^\]]+\]|:[\w-]+')
              .allMatches(query)
              .length;
          final tags = RegExp(r'(^|[\s>+~])([a-zA-Z][\w-]*)')
              .allMatches(query)
              .length;
          final priority = ids * 10000000 + classes * 100000 + tags * 1000;
          try {
            for (final element in document.querySelectorAll(query)) {
              declarations(
                element,
                node.declarationGroup.declarations,
                priority,
              );
            }
          } on FormatException {
            // Unsupported selectors cannot discard the surrounding book text.
            continue;
          } on UnimplementedError {
            continue;
          }
        }
      }
    }
  };

  for (final element in document.querySelectorAll('link,style')) {
    if (element.localName == 'style') {
      stylesheet(element.text, path, 0);
    } else if ((element.attributes['rel'] ?? '')
        .toLowerCase()
        .split(' ')
        .contains('stylesheet')) {
      final reference = epubResourcePath(
        path,
        element.attributes['href'] ?? '',
      );
      final bytes = resources[reference];
      if (bytes != null && loaded.add(reference)) {
        stylesheet(utf8.decode(bytes, allowMalformed: true), reference, 0);
      }
    }
  }
  for (final element in document.querySelectorAll('[style]')) {
    final sheet = css.parse('*{${element.attributes['style']}}');
    for (final rule in sheet.topLevels.whereType<css.RuleSet>()) {
      declarations(element, rule.declarationGroup.declarations, 100000000);
    }
  }

  const inherited = {
    'text-align',
    'text-indent',
    'white-space',
    'direction',
    'font-style',
    'font-weight',
    'font-variant',
    'text-decoration',
  };
  void resolve(
    dom.Element element,
    Map<String, String> parent,
    double parentSize,
    String language,
  ) {
    final own =
        cascade[element]?.map((key, value) => MapEntry(key, value.value)) ??
        <String, String>{};
    final values = <String, String>{
      for (final key in inherited)
        if (parent.containsKey(key)) key: parent[key]!,
      ...own,
    };
    for (final key in inherited) {
      if (values[key] == 'inherit' || values[key] == 'unset') {
        if (parent.containsKey(key)) {
          values[key] = parent[key]!;
        } else {
          values.remove(key);
        }
      }
    }
    final heading = RegExp(r'^h[1-6]$').hasMatch(element.localName ?? '');
    final size = ebookLength(
      own['font-size'],
      parentSize,
      fallback: parentSize * (heading ? 1.25 : 1),
    );
    values['font-size'] = '${size}em';
    element.attributes['data-book-size'] = '$size';
    final dir = element.attributes['dir'];
    if (!own.containsKey('text-align') &&
        element.attributes.containsKey('align')) {
      values['text-align'] = element.attributes['align']!;
    }
    if (dir != null && (dir == 'rtl' || dir == 'ltr')) {
      values['direction'] = dir;
    }
    language =
        element.attributes['lang'] ??
        element.attributes['xml:lang'] ??
        language;
    if (language.isNotEmpty) {
      element.attributes['data-book-lang'] = language;
    }
    element.attributes['data-book-style'] = values.entries
        .map((e) => '${e.key}:${e.value}')
        .join(';');
    // The HTML renderer handles containers, lists, tables and image sizing. Do
    // not pass publisher clipping/fixed heights on to reflowable book content.
    // Preserve the HTML engine's supported visual box properties. Reject
    // clipping and remote resource fetches rather than dropping all borders.
    const clippedLayout = {
      'position',
      'top',
      'bottom',
      'left',
      'right',
      'height',
      'max-height',
      'overflow',
      'overflow-x',
      'overflow-y',
      'max-lines',
      '-webkit-line-clamp',
      'text-overflow',
    };
    element.attributes['style'] = own.entries
        .where(
          (entry) =>
              !clippedLayout.contains(entry.key) &&
              !entry.value.toLowerCase().contains('url(') &&
              !(entry.key == 'display' && entry.value == 'none') &&
              !(entry.key == 'visibility' && entry.value != 'visible'),
        )
        .map((entry) => '${entry.key}:${entry.value}')
        .join(';');
    if (element.text.trim().isEmpty &&
        element.querySelector('img,image,svg,object') == null &&
        own.containsKey('height')) {
      element.attributes['style'] =
          '${element.attributes['style']};min-height:${own['height']}';
    }
    for (final child in element.children) {
      resolve(child, values, size, language);
    }
  }

  final html = document.documentElement;
  if (html != null) {
    resolve(html, {}, 1, '');
  }
  for (final element in document.querySelectorAll('script,style,link')) {
    element.remove();
  }
}

Map<String, String> ebookStyle(dom.Element element) => {
  for (final part
      in (element.attributes['data-book-style'] ??
              element.attributes['style'] ??
              '')
          .split(';'))
    if (part.indexOf(':') > 0)
      part.substring(0, part.indexOf(':')).trim(): part
          .substring(part.indexOf(':') + 1)
          .trim(),
};

/// CSS lengths converted to the reader's chosen font scale; nonfinite and
/// unsupported values fall back without introducing a clipped page.
double ebookLength(
  String? value,
  double em, {
  double fallback = 0,
  double? percent,
}) {
  if (value == null) {
    return fallback;
  }
  final match = RegExp(r'^(-?\d*\.?\d+)\s*(em|rem|px|pt|%)?$')
      .firstMatch(value.trim());
  if (match == null) {
    return fallback;
  }
  final number = double.tryParse(match[1]!);
  if (number == null || !number.isFinite) {
    return fallback;
  }
  return switch (match[2]) {
    'em' => number * em,
    'rem' => number * em,
    '%' => number * (percent ?? em) / 100,
    'pt' => number * em / 12,
    'px' => number * em / 16,
    _ => number == 0 ? 0 : number * em,
  };
}

TextAlign ebookAlignment(dom.Element element, TextAlign fallback) =>
    switch (ebookStyle(element)['text-align'] ?? element.attributes['align']) {
      'left' => TextAlign.left,
      'right' => TextAlign.right,
      'center' => TextAlign.center,
      'justify' => fallback == TextAlign.start ? TextAlign.justify : fallback,
      'start' => TextAlign.start,
      'end' => TextAlign.end,
      _ => fallback,
    };

TextDirection ebookDirection(dom.Element element, TextDirection fallback) =>
    switch (ebookStyle(element)['direction'] ?? element.attributes['dir']) {
      'rtl' => TextDirection.rtl,
      'ltr' => TextDirection.ltr,
      _ => fallback,
    };

TextStyle ebookTextStyle(
  dom.Element element,
  TextStyle base, {
  bool block = false,
}) {
  final values = ebookStyle(element);
  final tag = element.localName;
  final heading = RegExp(r'^h[1-6]$').hasMatch(tag ?? '');
  final ratio = double.tryParse(element.attributes['data-book-size'] ?? '');
  final size = (base.fontSize ?? 20) * (ratio ?? (block && heading ? 1.25 : 1));
  final weight = values['font-weight'];
  final numericWeight = int.tryParse(weight ?? '');
  final italic = values['font-style'];
  final decoration = values['text-decoration'] ?? '';
  final language = element.attributes['data-book-lang']
      ?.replaceAll('_', '-')
      .split('-');
  return base.copyWith(
    fontSize: size,
    fontWeight: numericWeight != null
        ? FontWeight.values[(numericWeight ~/ 100 - 1).clamp(0, 8)]
        : weight == 'normal'
        ? FontWeight.normal
        : weight == 'bold' || tag == 'strong' || tag == 'b'
        ? FontWeight.bold
        : block && heading && weight == null
        ? FontWeight.w600
        : null,
    fontStyle: italic == 'normal'
        ? FontStyle.normal
        : italic == 'italic' || italic == 'oblique' || tag == 'i' || tag == 'em'
        ? FontStyle.italic
        : null,
    fontFamily: tag == 'pre' || tag == 'code' ? 'monospace' : null,
    fontFeatures: tag == 'sup'
        ? const [FontFeature.superscripts()]
        : tag == 'sub'
        ? const [FontFeature.subscripts()]
        : values['font-variant'] == 'small-caps'
        ? const [FontFeature.enable('smcp')]
        : null,
    locale: language == null || language.first.isEmpty
        ? null
        : Locale.fromSubtags(
            languageCode: language.first,
            scriptCode: language
                .skip(1)
                .where((part) => part.length == 4)
                .firstOrNull,
            countryCode: language
                .skip(1)
                .where((part) => part.length == 2)
                .firstOrNull,
          ),
    decoration: TextDecoration.combine([
      if (decoration.contains('underline')) TextDecoration.underline,
      if (decoration.contains('line-through')) TextDecoration.lineThrough,
      if (decoration.contains('overline')) TextDecoration.overline,
    ]),
  );
}

EdgeInsets ebookParagraphInsets(dom.Element element, double em) {
  final values = ebookStyle(element);
  double side(String name, String side, double fallback) {
    final parts = values[name]?.split(RegExp(r'\s+')) ?? [];
    final index = switch (side) {
      'top' => 0,
      'right' => parts.length == 1 ? 0 : 1,
      'bottom' => parts.length < 3 ? 0 : 2,
      _ =>
        parts.length == 4
            ? 3
            : parts.length == 1
            ? 0
            : 1,
    };
    final shorthand = parts.isEmpty ? null : parts[index];
    return ebookLength(
      values['$name-$side'] ?? shorthand,
      em,
      fallback: fallback,
    ).clamp(0.0, em * 6).toDouble();
  }

  final heading = RegExp(r'^h[1-6]$').hasMatch(element.localName ?? '');
  return EdgeInsets.fromLTRB(
    side('margin', 'left', element.localName == 'blockquote' ? em : 0) +
        side('padding', 'left', 0),
    side('margin', 'top', heading ? em * .65 : 0) + side('padding', 'top', 0),
    side('margin', 'right', 0) + side('padding', 'right', 0),
    side('margin', 'bottom', em * .45) + side('padding', 'bottom', 0),
  );
}
