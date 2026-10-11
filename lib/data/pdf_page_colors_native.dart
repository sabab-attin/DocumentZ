import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as native;
import 'package:pdfrx/pdfrx.dart';

const supportsPdfPageColors = true;

PdfDocument applyPdfPageColors(PdfDocument document) => _DarkDocument(document);

/// Owns the source lifetime without inserting decorators into the native engine.
class _DarkDocument extends PdfDocument {
  _DarkDocument(this.source) : super(sourceName: source.sourceName) {
    _refreshPages();
  }
  final PdfDocument source;
  Future<Uint8List>? _renderBytes;
  Future<Uint8List> get renderBytes => _renderBytes ??= source.encodePdf(removeSecurity: true);
  late List<PdfPage> _pages;
  void _refreshPages() {
    _pages = List.unmodifiable(source.pages.map((page) => _DarkPage(page, this)));
  }
  @override
  List<PdfPage> get pages => _pages;
  @override
  set pages(List<PdfPage> value) => throw UnsupportedError('Display pages are read-only');
  @override
  PdfPermissions? get permissions => source.permissions;
  @override
  bool get isEncrypted => source.isEncrypted;
  @override
  Stream<PdfDocumentEvent> get events => source.events;
  @override
  Future<void> dispose() => source.dispose();
  @override
  Future<List<PdfOutlineNode>> loadOutline() => source.loadOutline();
  @override
  bool isIdenticalDocumentHandle(Object? other) =>
    source.isIdenticalDocumentHandle(other is _DarkDocument ? other.source : other);
  @override
  Future<bool> assemble() => source.assemble();
  @override
  Future<Uint8List> encodePdf({bool incremental = false, bool removeSecurity = false}) =>
    source.encodePdf(incremental: incremental, removeSecurity: removeSecurity);
  @override
  Future<T> useNativeDocumentHandle<T>(FutureOr<T> Function(int) task) => source.useNativeDocumentHandle(task);
  @override
  Future<void> reloadPages({List<int>? pageNumbersToReload}) async {
    await source.reloadPages(pageNumbersToReload: pageNumbersToReload);
    _renderBytes = null;
    _refreshPages();
  }
  @override
  Future<void> loadPagesProgressively<T>({PdfPageLoadingCallback<T>? onPageLoadProgress,
    T? data, Duration loadUnitDuration = const Duration(milliseconds: 250), int? startPageNumber}) async {
    await source.loadPagesProgressively(onPageLoadProgress: onPageLoadProgress,
      data: data, loadUnitDuration: loadUnitDuration, startPageNumber: startPageNumber);
    _refreshPages();
  }
}

/// Decorates rendering rather than the viewer: selection and marks keep their colors.
class _DarkPage extends PdfPage {
  _DarkPage(this.source, this.document);
  final PdfPage source;
  late final Future<bool> _hasText = source.loadText().then((text) => text?.fullText.trim().isNotEmpty ?? false);
  @override
  final PdfDocument document;
  @override
  int get pageNumber => source.pageNumber;
  @override
  double get width => source.width;
  @override
  double get height => source.height;
  @override
  PdfPageRotation get rotation => source.rotation;
  @override
  bool get isLoaded => source.isLoaded;
  @override
  PdfPageRenderCancellationToken createCancellationToken() => source.createCancellationToken();
  @override
  Future<PdfPageRawText?> loadText() => source.loadText();
  @override
  Future<List<PdfLink>> loadLinks({bool compact = false, bool enableAutoLinkDetection = true}) =>
    source.loadLinks(compact: compact, enableAutoLinkDetection: enableAutoLinkDetection);

  @override
  Future<PdfImage?> render({int x = 0, int y = 0, int? width, int? height,
    double? fullWidth, double? fullHeight, int? backgroundColor, PdfPageRotation? rotationOverride,
    PdfAnnotationRenderingMode annotationRenderingMode = PdfAnnotationRenderingMode.annotationAndForms,
    int flags = PdfPageRenderFlags.none, PdfPageRenderCancellationToken? cancellationToken}) async {
    if (cancellationToken?.isCanceled ?? false) return null;
    // Redaction rebuilds pages as raster images. Recoloring that generated PDF's
    // paths/masks can hide the entire image on a black canvas. Image-only pages
    // must retain the original renderer and an opaque paper background, just as
    // scans and photographs retain their colors in the reader.
    if (!await _hasText) {
      if (cancellationToken?.isCanceled ?? false) return null;
      return source.render(x: x, y: y, width: width, height: height,
        fullWidth: fullWidth, fullHeight: fullHeight, backgroundColor: 0xffffffff,
        rotationOverride: rotationOverride, annotationRenderingMode: annotationRenderingMode,
        flags: flags, cancellationToken: cancellationToken);
    }
    final fw = fullWidth ?? this.width;
    final fh = fullHeight ?? this.height;
    final w = width ?? fw.ceil();
    final h = height ?? fh.ceil();
    if (w <= 0 || h <= 0) return null;
    final request = _RenderRequest(pageNumber - 1, x, y, w, h, fw.ceil(), fh.ceil(),
      rotationOverride == null ? 0 : (rotationOverride.index - rotation.index) & 3,
      flags | (annotationRenderingMode == PdfAnnotationRenderingMode.none ? 0 : 1));
    // Serialize through the engine that owns the source callbacks. Only bytes
    // cross isolates: the rendering worker opens its own callback-free document.
    final bytes = await (document as _DarkDocument).renderBytes;
    if (cancellationToken?.isCanceled ?? false) return null;
    // PDFium also has process-wide font callbacks owned by its engine isolate.
    // Use that same worker, not Flutter compute or a suspended engine worker.
    final pixels = await PdfrxEntryFunctions.instance.compute(_renderDark, (bytes, request));
    if (cancellationToken?.isCanceled ?? false) return null;
    return PdfImage.createFromBgraData(pixels, width: w, height: h);
  }
}

class _RenderRequest {
  const _RenderRequest(this.index, this.x, this.y, this.width, this.height, this.fullWidth, this.fullHeight, this.rotation, this.flags);
  final int index, x, y, width, height, fullWidth, fullHeight, rotation, flags;
}

Uint8List _renderDark((Uint8List, _RenderRequest) input) {
  final pdfium = native.getPdfium();
  final request = input.$2;
  final memory = calloc<Uint8>(input.$1.length);
  memory.asTypedList(input.$1.length).setAll(0, input.$1);
  try {
    final copy = pdfium.FPDF_LoadMemDocument64(memory.cast<Void>(), input.$1.length, nullptr);
    if (copy.address == 0) throw StateError('Could not open independent page render');
    try {
    final page = pdfium.FPDF_LoadPage(copy, request.index);
    if (page.address == 0) throw StateError('Could not load page for display');
    try {
      final channels = calloc<UnsignedInt>(4);
      try {
        for (int i = 0; i < pdfium.FPDFPage_CountObjects(page); i++) {
          _recolorObject(pdfium, pdfium.FPDFPage_GetObject(page, i), channels, 0);
        }
      } finally { calloc.free(channels); }
      final bitmap = pdfium.FPDFBitmap_Create(request.width, request.height, 1);
      if (bitmap.address == 0) throw StateError('Could not allocate page render');
      try {
        pdfium.FPDFBitmap_FillRect(bitmap, 0, 0, request.width, request.height, 0xff000000);
        pdfium.FPDF_RenderPageBitmap(bitmap, page, -request.x, -request.y,
          request.fullWidth, request.fullHeight, request.rotation, request.flags);
        final stride = pdfium.FPDFBitmap_GetStride(bitmap);
        final buffer = pdfium.FPDFBitmap_GetBuffer(bitmap).cast<Uint8>().asTypedList(stride * request.height);
        final result = Uint8List(request.width * request.height * 4);
        for (int row = 0; row < request.height; row++) {
          result.setRange(row * request.width * 4, (row + 1) * request.width * 4, buffer, row * stride);
        }
        return result;
      } finally { pdfium.FPDFBitmap_Destroy(bitmap); }
    } finally { pdfium.FPDF_ClosePage(page); }
    } finally { pdfium.FPDF_CloseDocument(copy); }
  } finally { calloc.free(memory); }
}

void _recolorObject(native.PDFium pdfium, native.FPDF_PAGEOBJECT object, Pointer<UnsignedInt> rgba, int depth) {
  if (object.address == 0 || depth > 64) return;
  final type = pdfium.FPDFPageObj_GetType(object);
  // PDFium object types: text=1, path=2, image=3, shading=4, form=5.
  // Image pixels and shading artwork are never transformed.
  if (type == 3 || type == 4) return;
  if (type == 5) {
    for (int i = 0; i < pdfium.FPDFFormObj_CountObjects(object); i++) {
      _recolorObject(pdfium, pdfium.FPDFFormObj_GetObject(object, i), rgba, depth + 1);
    }
    return;
  }
  if (type != 1 && type != 2) return;
  if (pdfium.FPDFPageObj_GetFillColor(object, rgba, rgba + 1, rgba + 2, rgba + 3) != 0) {
    final rgb = _darkColor(rgba[0], rgba[1], rgba[2], text: type == 1);
    pdfium.FPDFPageObj_SetFillColor(object, rgb.$1, rgb.$2, rgb.$3, rgba[3]);
  }
  if (pdfium.FPDFPageObj_GetStrokeColor(object, rgba, rgba + 1, rgba + 2, rgba + 3) != 0) {
    final rgb = _darkColor(rgba[0], rgba[1], rgba[2], text: type == 1);
    pdfium.FPDFPageObj_SetStrokeColor(object, rgb.$1, rgb.$2, rgb.$3, rgba[3]);
  }
}

(int, int, int) _darkColor(int r, int g, int b, {required bool text}) {
  if (text) return (255, 255, 255);
  final maxChannel = math.max(r, math.max(g, b));
  final minChannel = math.min(r, math.min(g, b));
  if (maxChannel - minChannel < 20 && minChannel >= 230) return (0, 0, 0);
  if (maxChannel - minChannel < 20 && maxChannel <= 70) return (255, 255, 255);
  return (r, g, b);
}
