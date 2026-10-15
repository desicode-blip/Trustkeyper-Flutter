import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/features/payments/data/rent_payments.dart';
import 'package:trustkeyper/src/features/payments/presentation/rent_payment_screen.dart';

class TestGateway implements RentPaymentGateway {
  TestGateway({this.firstMonth = '2026-10'});
  final String firstMonth;
  bool captured = false;
  int confirmations = 0;
  List<String>? selected;
  RentPaymentData intent(String status) => RentPaymentData({
    'intentId': 'test-intent',
    'mode': 'test',
    'status': status,
    'amountPaise': 3300000,
    'depositPaise': 2200000,
    'orderId': 'order_test1',
    'keyId': 'rzp_test_example',
    'paymentId': status == 'paid' ? 'pay_test1' : null,
    'receiptNumber': status == 'paid' ? 'TK-TEST-test1' : null,
    'paidAtMs': 1800000000000,
    'lines': [
      {'month': '2026-10', 'rentPaise': 1100000, 'maintenancePaise': 0},
    ],
  });
  @override
  String operationId() => 'test-operation';
  @override
  Future<RentPaymentData> quote(String agreementId, int revision) async =>
      RentPaymentData({
        'mode': 'test',
        'firstPayment': true,
        'firstPaymentMonth': firstMonth,
        'propertyAddress': 'TEST Flat 402',
        'depositPaise': 2200000,
        'periods': [
          {
            'month': '2026-10',
            'rentPaise': 1100000,
            'maintenancePaise': 0,
            'totalPaise': 1100000,
            'days': 31,
            'daysInMonth': 31,
          },
          {
            'month': '2026-11',
            'rentPaise': 1100000,
            'maintenancePaise': 0,
            'totalPaise': 1100000,
            'days': 30,
            'daysInMonth': 30,
          },
        ],
      });
  @override
  Future<RentPaymentData> begin(
    String agreementId,
    int revision,
    List<String> months,
    String operationId,
  ) async {
    selected = months;
    return intent('awaiting_payment');
  }

  @override
  Future<RentPaymentData> confirm(
    String intentId,
    Map<String, String> result,
  ) async {
    confirmations++;
    return intent(captured ? 'paid' : 'awaiting_payment');
  }

  @override
  Future<RentPaymentData> reconcile(String intentId) async =>
      intent(captured ? 'paid' : 'awaiting_payment');
}

void main() {
  testWidgets(
    'first payment is constrained and callback alone does not show a paid receipt',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = TestGateway();
      await tester.pumpWidget(
        MaterialApp(
          home: RentPaymentScreen(
            agreementId: 'test',
            revision: 1,
            gateway: gateway,
            checkout: (_) async => {
              'paymentId': 'pay_test1',
              'signature': 'test',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('November 2026 rent'), findsNothing);
      expect(find.textContaining('TEST MODE'), findsOneWidget);
      await tester.tap(find.text('Pay ₹33,000 · test'));
      await tester.pumpAndSettle();
      expect(gateway.selected, ['2026-10']);
      expect(gateway.confirmations, 1);
      expect(find.text('Download receipt'), findsNothing);
      gateway.captured = true;
      await tester.ensureVisible(find.text('Check payment status'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check payment status'));
      await tester.pumpAndSettle();
      expect(find.text('Download receipt'), findsOneWidget);
      expect(find.text('TK-TEST-test1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'late first checkout displays only the server-selected current month',
    (tester) async {
      final gateway = TestGateway(firstMonth: '2026-11');
      await tester.pumpWidget(
        MaterialApp(
          home: RentPaymentScreen(
            agreementId: 'test',
            revision: 1,
            gateway: gateway,
            checkout: (_) async => {
              'paymentId': 'pay_test1',
              'signature': 'test',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('October 2026 rent'), findsNothing);
      expect(find.text('November 2026 rent'), findsOneWidget);
      await tester.tap(find.text('Pay ₹33,000 · test'));
      await tester.pumpAndSettle();
      expect(gateway.selected, ['2026-11']);
      expect(find.text('Download receipt'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'receipt requires captured server confirmation; output is a real PDF, not a local fake reference',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final gateway = TestGateway();
      await expectLater(
        paymentReceipt(gateway.intent('awaiting_payment')),
        throwsException,
      );
      final bytes = await paymentReceipt(gateway.intent('paid'));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(1000));
    },
  );
}
