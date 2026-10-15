import 'dart:convert';
import 'dart:typed_data';

Uint8List testDocumentPdf() {
  final body = 'BT /F1 20 Tf 36 160 Td (TEST DOCUMENT - NOT VALID) Tj ET';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 360 240] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length ${body.length} >>\nstream\n$body\nendstream',
  ];
  final offsets = <int>[0];
  var content = '%PDF-1.4\n';
  for (var index = 0; index < objects.length; index++) {
    offsets.add(content.length);
    content += '${index + 1} 0 obj\n${objects[index]}\nendobj\n';
  }
  final xref = content.length;
  content += 'xref\n0 ${offsets.length}\n0000000000 65535 f \n';
  for (final offset in offsets.skip(1)) {
    content += '${offset.toString().padLeft(10, '0')} 00000 n \n';
  }
  content +=
      'trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF';
  return Uint8List.fromList(utf8.encode(content));
}
