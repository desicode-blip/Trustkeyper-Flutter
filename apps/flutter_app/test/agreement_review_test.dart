import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/features/broker/data/agreement_review_repository.dart';
import 'package:trustkeyper/src/features/broker/presentation/agreement_review_request.dart';

class ReviewFake implements AgreementReviewRepository {
  int calls = 0;
  bool fail = false;
  Completer<String>? pending;
  @override
  Future<String> request(String agreementId, int revision) async {
    calls++;
    expect(agreementId, 'draft');
    expect(revision, 2);
    if (fail) throw const ReviewFailure('Reopen the draft before retrying.');
    return pending?.future ?? 'review_requested';
  }
}

void main() {
  test('request sends only identity and displayed saved revision', () async {
    final repository = FirebaseAgreementReviewRepository(
      currentUid: () => 'broker',
      call: (payload) async {
        expect(payload, {'agreementId': 'draft', 'revision': 2});
        return {...payload, 'status': 'review_requested'};
      },
    );
    expect(await repository.request('draft', 2), 'review_requested');
  });
  test('signed out and invalid drafts do not call the server', () async {
    var calls = 0;
    String? uid;
    final repository = FirebaseAgreementReviewRepository(
      currentUid: () => uid,
      call: (payload) async {
        calls++;
        return {};
      },
    );
    await expectLater(
      repository.request('draft', 2),
      throwsA(isA<ReviewFailure>()),
    );
    uid = 'broker';
    await expectLater(
      repository.request('../draft', 2),
      throwsA(isA<ReviewFailure>()),
    );
    await expectLater(
      repository.request('draft', 0),
      throwsA(isA<ReviewFailure>()),
    );
    expect(calls, 0);
  });
  test(
    'wrong revision, record or signing response cannot show success',
    () async {
      for (final change in [
        {'revision': 3},
        {'agreementId': 'other'},
        {'status': 'signed'},
      ]) {
        final repository = FirebaseAgreementReviewRepository(
          currentUid: () => 'broker',
          call: (payload) async => {
            ...payload,
            'status': 'review_requested',
            ...change,
          },
        );
        await expectLater(
          repository.request('draft', 2),
          throwsA(isA<ReviewFailure>()),
        );
      }
    },
  );
  test(
    'account changes during request suppress success for the previous account',
    () async {
      var uid = 'broker';
      final repository = FirebaseAgreementReviewRepository(
        currentUid: () => uid,
        call: (payload) async {
          uid = 'another';
          return {...payload, 'status': 'review_requested'};
        },
      );
      await expectLater(
        repository.request('draft', 2),
        throwsA(isA<ReviewFailure>()),
      );
    },
  );
  testWidgets(
    'cancellation sends nothing; confirmation makes one request and disables repeat',
    (tester) async {
      final repository = ReviewFake()..pending = Completer<String>();
      var completed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgreementReviewRequest(
              agreementId: 'draft',
              revision: 2,
              repository: repository,
              onSubmitted: () => completed++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Request team review · Demo only'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('does not send participant links'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repository.calls, 0);
      await tester.tap(find.text('Request team review · Demo only'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request review'));
      await tester.pumpAndSettle();
      expect(repository.calls, 1);
      expect(completed, 0);
      repository.pending!.complete('review_requested');
      await tester.pumpAndSettle();
      expect(completed, 1);
      expect(find.textContaining('This demo is not signed'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'failed submission preserves retry and never reports signed or sent',
    (tester) async {
      final repository = ReviewFake()..fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgreementReviewRequest(
              agreementId: 'draft',
              revision: 2,
              repository: repository,
              onSubmitted: () => fail('Failed request must not complete'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Request team review · Demo only'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request review'));
      await tester.pumpAndSettle();
      expect(find.text('Reopen the draft before retrying.'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNotNull,
      );
    },
  );
}
