import 'package:pdfrx/pdfrx.dart';

import 'private_documents.dart';

PdfDocumentRefData privatePdfReference(DocumentFile file) {
  file.validate();
  if (file.contentType != 'application/pdf') {
    throw const DocumentFailure('Choose a PDF document.');
  }
  return PdfDocumentRefData(
    file.bytes,
    sourceName: file.name,
    key: PdfDocumentRefKey('private-document-review', [Object()]),
    useProgressiveLoading: false,
  );
}
