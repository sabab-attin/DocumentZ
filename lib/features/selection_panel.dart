import 'annotation_color_picker.dart';
import 'highlighter_icon.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'annotations.dart';

const selectionColors = <String, int>{
  'Black': 0xff000000,
  'White': 0xffffffff,
  'Yellow': 0xffffef70,
  'Orange': 0xffffb94f,
  'Green': 0xff83c780,
  'Blue': 0xff65b7f1,
  'Pink': 0xffeb6096,
  'Purple': 0xffb69ddd,
};
const readerPanelColor = Color(0xff1b2228);
const readerPanelInk = Color(0xffdce5ed);

/// Choose a tool, then tap a color to mark the selected text immediately.
class SelectionPanel extends StatefulWidget {
  const SelectionPanel({
    super.key,
    required this.readText,
    required this.onMark,
    required this.onClose,
  });
  final Future<String> Function() readText;
  final Future<void> Function(MarkTool, int) onMark;
  final VoidCallback onClose;
  @override
  State<SelectionPanel> createState() => _SelectionPanelState();
}

class _SelectionPanelState extends State<SelectionPanel> {
  MarkTool tool = MarkTool.highlight;
  String colorName = 'Yellow';
  int? customColor;
  bool busy = false;
  String get toolLabel => switch (tool) {
    MarkTool.underline => 'Underline',
    MarkTool.strikethrough => 'Strikethrough',
    _ => 'Highlight',
  };
  int get color => customColor ?? selectionColors[colorName]!;

  Future<void> _run(Future<void> Function() operation) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await operation();
      if (mounted) widget.onClose();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Could not complete this action. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _share() async {
    final box = context.findRenderObject();
    final origin = box is RenderBox
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    final text = await widget.readText();
    if (!mounted) return;
    await SharePlus.instance.share(
      ShareParams(text: text, sharePositionOrigin: origin),
    );
  }

  Widget _tool(MarkTool kind, String label, IconData icon) => Expanded(
    child: Semantics(
      selected: tool == kind,
      button: true,
      child: TextButton(
        onPressed: busy ? null : () => setState(() => tool = kind),
        style: TextButton.styleFrom(
          foregroundColor: readerPanelInk,
          backgroundColor: tool == kind
              ? const Color(0xff354b5c)
              : Colors.transparent,
          minimumSize: const Size(48, 64),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReaderToolIcon(icon, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _action(String label, IconData icon, VoidCallback? action) => Expanded(
    child: IconButton(
      tooltip: label,
      onPressed: action,
      icon: ReaderToolIcon(icon, size: 24),
      style: IconButton.styleFrom(
        foregroundColor: readerPanelInk,
        minimumSize: const Size(48, 48),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 160),
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.scale(
                scale: .97 + .03 * value,
                alignment: Alignment.bottomCenter,
                child: child,
              ),
            ),
            child: Material(
              color: readerPanelColor,
              elevation: 12,
              shadowColor: Colors.black54,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: Color(0xff46515a)),
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _tool(
                          MarkTool.highlight,
                          'Highlight',
                          Icons.border_color,
                        ),
                        const SizedBox(width: 4),
                        _tool(
                          MarkTool.underline,
                          'Underline',
                          Icons.format_underlined,
                        ),
                        const SizedBox(width: 4),
                        _tool(
                          MarkTool.strikethrough,
                          'Strikethrough',
                          Icons.strikethrough_s,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final entry in selectionColors.entries)
                          Expanded(
                            child: Tooltip(
                              message: entry.key,
                              child: Semantics(
                                label: '${entry.key} annotation color',
                                selected: colorName == entry.key,
                                button: true,
                                child: InkResponse(
                                  onTap: busy
                                      ? null
                                      : () {
                                          final selectedTool = tool;
                                          setState(() {
                                            colorName = entry.key;
                                            customColor = null;
                                          });
                                          _run(
                                            () => widget.onMark(
                                              selectedTool,
                                              entry.value,
                                            ),
                                          );
                                        },
                                  radius: 28,
                                  child: SizedBox(
                                    height: 52,
                                    child: Center(
                                      child: Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: Color(entry.value),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: colorName == entry.key
                                                ? Colors.white
                                                : Colors.white38,
                                            width: colorName == entry.key
                                                ? 3
                                                : 1,
                                          ),
                                        ),
                                        child: colorName == entry.key
                                            ? ReaderToolIcon(
                                                Icons.check,
                                                color:
                                                    Color(
                                                          entry.value,
                                                        ).computeLuminance() <
                                                        .35
                                                    ? Colors.white
                                                    : Colors.black,
                                                size: 22,
                                              )
                                            : null,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: busy
                          ? null
                          : () async {
                              final selected = await pickAnnotationColor(
                                context,
                                initial: Color(color),
                              );
                              if (selected == null || !mounted) return;
                              setState(() {
                                customColor = selected.toARGB32();
                                colorName = 'Custom';
                              });
                              await _run(
                                () => widget.onMark(tool, selected.toARGB32()),
                              );
                            },
                      icon: const Icon(Icons.color_lens_outlined),
                      label: const Text('Custom color wheel'),
                    ),
                    Text(
                      busy
                          ? 'Marking…'
                          : 'Tap a color to ${toolLabel.toLowerCase()}',
                      style: const TextStyle(
                        color: readerPanelInk,
                        fontSize: 12,
                      ),
                    ),
                    const Divider(color: Color(0xff46515a), height: 20),
                    Row(
                      children: [
                        _action(
                          'Copy',
                          Icons.copy_outlined,
                          busy
                              ? null
                              : () => _run(() async {
                                  await Clipboard.setData(
                                    ClipboardData(
                                      text: await widget.readText(),
                                    ),
                                  );
                                }),
                        ),
                        _action(
                          'Share',
                          Icons.share_outlined,
                          busy ? null : () => _run(_share),
                        ),
                        _action(
                          'Add note',
                          Icons.add_comment_outlined,
                          busy
                              ? null
                              : () {
                                  final selectedColor = color;
                                  _run(
                                    () => widget.onMark(
                                      MarkTool.note,
                                      selectedColor,
                                    ),
                                  );
                                },
                        ),
                        _action(
                          'Close',
                          Icons.close,
                          busy ? null : widget.onClose,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class ReaderMenuAction extends StatelessWidget {
  const ReaderMenuAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool selected;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xff334654) : null,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ReaderToolIcon(
              icon,
              size: 28,
              color: onTap == null ? Colors.grey : readerPanelInk,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.2,
                color: onTap == null ? Colors.grey : readerPanelInk,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ReaderMenuGrid extends StatelessWidget {
  const ReaderMenuGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
      return GridView.count(
        crossAxisCount: constraints.maxWidth < 300 || scale > 1.5 ? 3 : 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: scale > 1.5 ? .65 : .85,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        children: children,
      );
    },
  );
}
