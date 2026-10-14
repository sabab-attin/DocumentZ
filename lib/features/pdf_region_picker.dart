import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

class PdfRegionPicker extends StatefulWidget {
  const PdfRegionPicker({
    super.key,
    required this.bytes,
    required this.page,
    required this.title,
  });
  final Uint8List bytes;
  final int page;
  final String title;
  @override
  State<PdfRegionPicker> createState() => _PdfRegionPickerState();
}

class _PdfRegionPickerState extends State<PdfRegionPicker> {
  late final picture = Printing.raster(
    widget.bytes,
    pages: [widget.page],
    dpi: 100,
  ).first;
  late final png = picture.then((raster) => raster.toPng());
  Offset? start;
  Rect? region;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Drag a rectangle on the page.'),
        ),
        Expanded(
          child: FutureBuilder<PdfRaster>(
            future: picture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text('Could not display this page.'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final raster = snapshot.data!;
              return Center(
                child: AspectRatio(
                  aspectRatio: raster.width / raster.height,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      Offset point(Offset p) => Offset(
                        (p.dx / constraints.maxWidth).clamp(0, 1),
                        (p.dy / constraints.maxHeight).clamp(0, 1),
                      );
                      return GestureDetector(
                        onPanStart: (details) => setState(() {
                          start = point(details.localPosition);
                          region = null;
                        }),
                        onPanUpdate: (details) => setState(
                          () => region = Rect.fromPoints(
                            start!,
                            point(details.localPosition),
                          ),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            FutureBuilder<Uint8List>(
                              future: png,
                              builder: (context, image) => image.hasData
                                  ? Image.memory(image.data!, fit: BoxFit.fill)
                                  : const SizedBox(),
                            ),
                            if (region != null)
                              Positioned(
                                left: region!.left * constraints.maxWidth,
                                top: region!.top * constraints.maxHeight,
                                width: region!.width * constraints.maxWidth,
                                height: region!.height * constraints.maxHeight,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: .25),
                                    border: Border.all(
                                      color: Colors.blue,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed:
                  region == null || region!.width < .01 || region!.height < .01
                  ? null
                  : () => Navigator.pop(context, region),
              child: const Text('Use this area'),
            ),
          ),
        ),
      ],
    ),
  );
}
