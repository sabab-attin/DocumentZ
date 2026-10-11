import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../data/pdf_editing.dart';

class PdfFormScreen extends StatefulWidget {
  const PdfFormScreen({super.key, required this.bytes});
  final Uint8List bytes;
  @override
  State<PdfFormScreen> createState() => _PdfFormScreenState();
}
class _PdfFormScreenState extends State<PdfFormScreen> {
  late final sf.PdfDocument document = PdfEditing.open(widget.bytes, '');
  final controllers = <int, TextEditingController>{};
  bool saving = false;
  @override
  void dispose() { for (final c in controllers.values) { c.dispose(); } document.dispose(); super.dispose(); }
  Future<void> save() async {
    setState(() => saving = true);
    try {
      final bytes = await PdfEditing.save(document);
      if (mounted) Navigator.pop(context, bytes);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save form values.')));
    } finally { if (mounted) setState(() => saving = false); }
  }
  Widget field(int index) {
    final value = document.form.fields[index];
    final label = value.tooltip.isNotEmpty ? value.tooltip : value.name ?? 'Field ${index + 1}';
    if (value is sf.PdfTextBoxField) {
      final controller = controllers.putIfAbsent(index, () => TextEditingController(text: value.text));
      return Padding(padding: const EdgeInsets.all(12), child: TextField(controller: controller,
        readOnly: value.readOnly, maxLines: value.multiline && !value.isPassword ? 4 : 1, obscureText: value.isPassword,
        maxLength: value.maxLength > 0 ? value.maxLength : null,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()), onChanged: (text) => value.text = text));
    }
    if (value is sf.PdfCheckBoxField) {
      return CheckboxListTile(title: Text(label), value: value.isChecked,
        onChanged: value.readOnly ? null : (checked) => setState(() => value.isChecked = checked ?? false));
    }
    if (value is sf.PdfComboBoxField) {
      return Padding(padding: const EdgeInsets.all(12), child: DropdownButtonFormField<int>(
        initialValue: value.selectedIndex >= 0 && value.selectedIndex < value.items.count ? value.selectedIndex : null,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: [for (int i = 0; i < value.items.count; i++) DropdownMenuItem(value: i, child: Text(value.items[i].text))],
        onChanged: value.readOnly ? null : (i) {
          if (i != null) { setState(() => value.selectedIndex = i); }
        }));
    }
    if (value is sf.PdfRadioButtonListField) {
      return Padding(padding: const EdgeInsets.all(12), child: DropdownButtonFormField<int>(
        initialValue: value.selectedIndex >= 0 && value.selectedIndex < value.items.count ? value.selectedIndex : null,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: [for (int i = 0; i < value.items.count; i++) DropdownMenuItem(value: i, child: Text(value.items[i].value))],
        onChanged: value.readOnly ? null : (i) { if (i != null) { setState(() => value.selectedIndex = i); } }));
    }
    if (value is sf.PdfListBoxField) {
      return Column(children: [ListTile(title: Text(label)),
      for (int i = 0; i < value.items.count; i++) CheckboxListTile(title: Text(value.items[i].text), value: value.selectedIndexes.contains(i),
        onChanged: value.readOnly ? null : (checked) => setState(() {
          final selected = List<int>.of(value.selectedIndexes);
          if (checked == true) {
            if (!value.multiSelect) { selected.clear(); }
            selected.add(i);
          } else { selected.remove(i); }
          value.selectedIndexes = selected;
        })),
      ]);
    }
    return ListTile(title: Text(label), subtitle: Text(value is sf.PdfSignatureField ? 'Use Signature to sign this document.' : 'This field is not editable here.'));
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Fill form'), actions: [
    TextButton(onPressed: saving || document.form.fields.count == 0 ? null : save, child: Text(saving ? 'Saving…' : 'Continue')),
  ]), body: document.form.fields.count == 0 ? const Center(child: Padding(padding: EdgeInsets.all(24),
    child: Text('No interactive fields. Use Add text to fill a flat document.')))
    : ListView.builder(itemCount: document.form.fields.count, itemBuilder: (context, i) => field(i)));
}
