import 'package:flutter/material.dart';

Future<void> showDocumentActions(
  BuildContext context, {
  required String title,
  required VoidCallback onShare,
  VoidCallback? onRename,
  VoidCallback? onDelete,
  VoidCallback? onRemoveRecent,
  VoidCallback? onSelect,
}) => showModalBottomSheet<void>(
  context: context,
  builder: (sheet) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        if (onRename != null)
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline),
            title: const Text('Rename'),
            onTap: () {
              Navigator.pop(sheet);
              onRename();
            },
          ),
        ListTile(
          leading: const Icon(Icons.share_outlined),
          title: const Text('Share'),
          onTap: () {
            Navigator.pop(sheet);
            onShare();
          },
        ),
        if (onSelect != null)
          ListTile(
            leading: const Icon(Icons.check_box_outlined),
            title: const Text('Select documents'),
            onTap: () {
              Navigator.pop(sheet);
              onSelect();
            },
          ),
        if (onRemoveRecent != null)
          ListTile(
            leading: const Icon(Icons.history_toggle_off),
            title: const Text('Remove from Recents'),
            onTap: () {
              Navigator.pop(sheet);
              onRemoveRecent();
            },
          ),
        if (onDelete != null)
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Delete'),
            onTap: () {
              Navigator.pop(sheet);
              onDelete();
            },
          ),
      ],
    ),
  ),
);

Future<String?> askDocumentName(BuildContext context, String name) =>
    showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(name: name),
    );

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.name});
  final String name;
  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final controller = TextEditingController(text: widget.name);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename document'),
    content: TextField(
      controller: controller,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Name'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (controller.text.trim().isNotEmpty) {
            Navigator.pop(context, controller.text.trim());
          }
        },
        child: const Text('Rename'),
      ),
    ],
  );
}

Future<bool> confirmDocumentDelete(
  BuildContext context,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialog, true),
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            label: const Text('Delete'),
          ),
        ],
      ),
    ) ??
    false;
