import 'dart:convert';
import 'dart:typed_data';

/// White paper, black text, and red/green/black/white image quadrants.
Uint8List imageAndTextPdf() {
  final output = BytesBuilder(copy: false);
  final offsets = <int>[0];
  void ascii(String value) => output.add(latin1.encode(value));
  void object(int id, List<int> bytes) {
    offsets.add(output.length);
    ascii('$id 0 obj\n'); output.add(bytes); ascii('\nendobj\n');
  }
  List<int> text(String value) => latin1.encode(value);
  ascii('%PDF-1.4\n');
  object(1, text('<< /Type /Catalog /Pages 2 0 R >>'));
  object(2, text('<< /Type /Pages /Count 1 /Kids [3 0 R] >>'));
  object(3, text('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << /Font << /F1 5 0 R >> /XObject << /Im0 6 0 R >> >> /Contents 4 0 R >>'));
  final content = text('1 1 1 rg 0 0 200 200 re f\n0 0 0 rg BT /F1 18 Tf 20 160 Td (Hello PDF) Tj ET\nq 100 0 0 100 50 20 cm /Im0 Do Q');
  object(4, [...text('<< /Length ${content.length} >>\nstream\n'), ...content, ...text('\nendstream')]);
  object(5, text('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'));
  object(6, [...text('<< /Type /XObject /Subtype /Image /Width 2 /Height 2 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Length 12 >>\nstream\n'),
    255,0,0, 0,255,0, 0,0,0, 255,255,255, ...text('\nendstream')]);
  final xref = output.length;
  ascii('xref\n0 7\n0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) { ascii('${offset.toString().padLeft(10, '0')} 00000 n \n'); }
  ascii('trailer\n<< /Size 7 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return output.takeBytes();
}
