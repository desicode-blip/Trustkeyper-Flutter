import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/document_requests/data/linkedin_profile.dart';
import 'package:trustkeyper/src/features/document_requests/data/document_request_repository.dart';
import 'package:trustkeyper/src/features/document_requests/data/broker_paper_state.dart';
import 'package:trustkeyper/src/features/document_requests/presentation/linkedin_profile_fields.dart';
import 'document_request_test.dart' show information;

void main() {
  test(
    'LinkedIn accepts profile URLs, rejects other hosts and normalizes tracking',
    () {
      for (final value in [
        'linkedin.com/in/test-person',
        'https://www.linkedin.com/in/test-person/?tracking=one',
      ]) {
        expect(
          normalizeLinkedInProfile(value),
          'https://www.linkedin.com/in/test-person',
        );
      }
      for (final value in [
        '',
        'https://example.com/in/test',
        'linkedin.com.evil.test/in/test',
        'https://evil@linkedin.com/in/test',
        'javascript:alert(1)',
        'linkedin.com/company/test',
      ]) {
        expect(normalizeLinkedInProfile(value), isNull);
      }
    },
  );
  testWidgets(
    'optional LinkedIn validates inline and Skip does not require a URL',
    (tester) async {
      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: LinkedInProfileFields(
              name: 'Priya Sharma',
              onSave: (value) async => saved = value,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'example.com');
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text(linkedInProfileError), findsOneWidget);
      expect(saved, isNull);
      await tester.tap(find.text('Skip'));
      await tester.pump();
      expect(saved, {'url': '', 'skipped': true});
    },
  );
  test('LinkedIn skip stays addable and is not falsely marked uploaded', () {
    final request = DocumentRequestInfo({
      ...information(verified: true, status: 'added', paper: 'linkedin').data,
      'submission': {
        'uploadId': 'test',
        'files': {},
        'linkedInDetails': {'url': '', 'skipped': true},
      },
    });
    final state = BrokerPaperState.resolve(
      [request],
      {},
      includeLinkedIn: true,
    ).last;
    expect(state.skipped, isTrue);
    expect(state.done, isFalse);
    expect(state.label(DateTime.now()), 'Skipped · can add later');
    expect(
      BrokerPaperState.resolve([], {}, includeLinkedIn: true).last.local,
      isFalse,
    );
  });
}
