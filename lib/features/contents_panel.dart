import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class ContentsPanel extends StatelessWidget {
  const ContentsPanel({
    super.key,
    required this.outline,
    required this.onPage,
    required this.onHide,
  });
  final Future<List<PdfOutlineNode>> outline;
  final ValueChanged<int> onPage;
  final VoidCallback onHide;
  Widget node(PdfOutlineNode item) => item.children.isEmpty
      ? ListTile(
          title: Text(item.title),
          onTap: item.dest == null ? null : () => onPage(item.dest!.pageNumber),
        )
      : ExpansionTile(
          title: Text(item.title),
          children: [
            if (item.dest != null)
              ListTile(
                title: const Text('Go to section'),
                onTap: () => onPage(item.dest!.pageNumber),
              ),
            for (final child in item.children) node(child),
          ],
        );
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Column(
      children: [
        ListTile(
          title: const Text('Table of contents'),
          trailing: IconButton(
            tooltip: 'Hide contents',
            onPressed: onHide,
            icon: const Icon(Icons.close),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<PdfOutlineNode>>(
            future: outline,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('Could not load contents.'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data!.isEmpty) {
                return const Center(
                  child: Text('This PDF has no table of contents.'),
                );
              }
              return ListView(children: snapshot.data!.map(node).toList());
            },
          ),
        ),
      ],
    ),
  );
}
