import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/testing/participant_fixture.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/broker/data/private_documents.dart';
import 'package:trustkeyper/src/features/participants/data/participant_repository.dart';
import 'package:trustkeyper/src/features/participants/data/participant_workspace.dart';
import 'package:trustkeyper/src/features/participants/presentation/participant_workspace_screen.dart';
import 'package:trustkeyper/src/features/participants/presentation/repair_photo_widgets.dart';

import 'support/document_preview_wait.dart';

final photoBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAI0lEQVR4nGM0TPjPQApgIkk1w6gG4gATkergYFQDMYDkUAIA+V4BsKI64joAAAAASUVORK5CYII=',
);
DocumentFile testPhoto() =>
    DocumentFile(name: 'TEST-PHOTO.png', bytes: photoBytes);

class CapturingWriter implements ParticipantIssueWriter {
  bool fail = false;
  final received = <IssueInput>[];
  @override
  Future<String> create(IssueInput input) async {
    received.add(input);
    if (fail) throw StateError('Temporary upload failure');
    return input.reportId;
  }
}

class PhotoReader implements IssuePhotoReader {
  int calls = 0;
  bool fail = false;
  @override
  Future<Uint8List> readPhoto(String issueId, String path) async {
    calls++;
    if (fail) throw StateError('Temporary private read failure');
    return photoBytes;
  }
}

Future<void> pickPhoto(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Add a photo'));
  await tester.tap(find.text('Add a photo'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Choose photo'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'repair photo preview explains report sending, not document delivery to a broker',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ParticipantIssueScreen(
            agreements: [OfflineParticipantFixture.agreement],
            writer: CapturingWriter(),
            pickPhoto: (_) async => testPhoto(),
          ),
        ),
      );
      await pickPhoto(tester);
      await waitForDocumentPreview(
        tester,
        reviewTitle: 'Review selected photo',
      );
      expect(find.text('Review selected photo'), findsOneWidget);
      expect(find.textContaining('press Send on the report'), findsOneWidget);
      expect(find.textContaining('Send to broker'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Selected · Not sent'), findsNothing);
    },
  );
  test(
    'repair input accepts only bounded image photos and generates unique safe IDs',
    () {
      IssueInput input(List<DocumentFile> photos) => IssueInput(
        agreementId: 'home',
        category: 'Water',
        description: 'The kitchen tap is leaking.',
        photos: photos,
      );
      expect(input([testPhoto()]).error, isNull);
      expect(
        input(List.generate(5, (_) => testPhoto())).error,
        contains('four'),
      );
      expect(
        input([
          DocumentFile(
            name: 'TEST.pdf',
            bytes: Uint8List.fromList(utf8.encode('%PDF-1.4 test')),
          ),
        ]).error,
        contains('JPG or PNG'),
      );
      expect(
        input([DocumentFile(name: 'bad.png', bytes: Uint8List(0))]).error,
        contains('10 MB'),
      );
      final identifiers = List.generate(100, (_) => newRepairReportId());
      expect(identifiers.toSet().length, 100);
      expect(
        identifiers.every((value) => RegExp(r'^[a-f0-9]{32}$').hasMatch(value)),
        true,
      );
    },
  );

  testWidgets(
    'selected photo can be removed and only confirmed selection reaches submission',
    (tester) async {
      final writer = CapturingWriter();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ParticipantIssueScreen(
            agreements: [OfflineParticipantFixture.agreement],
            writer: writer,
            pickPhoto: (_) async => testPhoto(),
            reviewPhoto: (_) async => true,
          ),
        ),
      );
      await pickPhoto(tester);
      expect(find.textContaining('Selected · Not sent'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove photo 1'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Selected · Not sent'), findsNothing);
      await pickPhoto(tester);
      await tester.enterText(
        find.byType(TextField),
        'The kitchen tap is leaking.',
      );
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(writer.received.single.photos.single.bytes, photoBytes);
      expect(find.text('Issue sent'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelled review and PDF selection never attach a repair photo',
    (tester) async {
      DocumentFile selected = testPhoto();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ParticipantIssueScreen(
            agreements: [OfflineParticipantFixture.agreement],
            writer: CapturingWriter(),
            pickPhoto: (_) async => selected,
            reviewPhoto: (_) async => false,
          ),
        ),
      );
      await pickPhoto(tester);
      expect(find.textContaining('Selected · Not sent'), findsNothing);
      selected = DocumentFile(
        name: 'TEST.pdf',
        bytes: Uint8List.fromList(utf8.encode('%PDF-1.4 test')),
      );
      await pickPhoto(tester);
      expect(find.textContaining('not a PDF'), findsOneWidget);
      expect(find.textContaining('Selected · Not sent'), findsNothing);
    },
  );

  testWidgets(
    'ambiguous failure retries the exact immutable report ID and photo payload',
    (tester) async {
      final writer = CapturingWriter()..fail = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ParticipantIssueScreen(
            agreements: [OfflineParticipantFixture.agreement],
            writer: writer,
            pickPhoto: (_) async => testPhoto(),
            reviewPhoto: (_) async => true,
          ),
        ),
      );
      await pickPhoto(tester);
      await tester.enterText(
        find.byType(TextField),
        'The kitchen tap is leaking.',
      );
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(find.text('Issue sent'), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
      writer.fail = false;
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(identical(writer.received[0], writer.received[1]), true);
      expect(find.text('Issue sent'), findsOneWidget);
    },
  );

  testWidgets(
    'private photo read failure has retry and report has no invented cost or capture stamp',
    (tester) async {
      final reader = PhotoReader()..fail = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ParticipantIssueDetailScreen(
            reader: reader,
            issue: ParticipantRecord('report', {
              'title': 'Water problem',
              'description': 'The kitchen tap is leaking.',
              'propertyAddress': 'TEST home',
              'status': 'open',
              'photos': [
                {'path': 'issues/report/photos/0'},
              ],
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Could not open this private photo.'), findsOneWidget);
      reader.fail = false;
      await tester.ensureVisible(find.text('Retry photo'));
      await tester.tap(find.text('Retry photo'));
      await tester.pumpAndSettle();
      expect(reader.calls, 2);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
