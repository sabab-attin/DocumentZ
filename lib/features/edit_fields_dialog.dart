import 'package:flutter/material.dart';

Future<Map<String, String>?> showEditFields(
  BuildContext context,
  String title,
  Map<String, String> labels, {
  Set<String> secret = const {},
  Map<String, String> initial = const {},
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<Map<String, String>>(
    context: context,
    builder: (_) => _EditFieldsDialog(
      title: title,
      labels: labels,
      secret: secret,
      initial: initial,
    ),
  );
  final values = await navigator.push(route);
  // Do not start expensive editing until the dialog has actually left the tree.
  await route.completed;
  return values;
}

class _EditFieldsDialog extends StatefulWidget {
  const _EditFieldsDialog({
    required this.title,
    required this.labels,
    required this.secret,
    required this.initial,
  });
  final String title;
  final Map<String, String> labels, initial;
  final Set<String> secret;
  @override
  State<_EditFieldsDialog> createState() => _EditFieldsDialogState();
}

class _EditFieldsDialogState extends State<_EditFieldsDialog> {
  late final controllers = {
    for (final key in widget.labels.keys)
      key: TextEditingController(text: widget.initial[key]),
  };
  String? error;
  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final values = controllers.map((key, value) => MapEntry(key, value.text));
    if (values.containsKey('open') && values.containsKey('owner')) {
      final opening = values['open']!;
      final owner = values['owner']!;
      if (opening.isEmpty || owner.isEmpty || opening == owner) {
        setState(
          () => error = 'Use different, nonempty opening and owner passwords.',
        );
        return;
      }
    }
    FocusScope.of(context).unfocus();
    Navigator.pop(context, values);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in widget.labels.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: TextField(
                  controller: controllers[entry.key],
                  obscureText: widget.secret.contains(entry.key),
                  autocorrect: !widget.secret.contains(entry.key),
                  enableSuggestions: !widget.secret.contains(entry.key),
                  minLines: entry.key == 'text' ? 4 : 1,
                  maxLines: entry.key == 'text' ? 8 : 1,
                  decoration: InputDecoration(
                    labelText: entry.value,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Continue')),
    ],
  );
}
