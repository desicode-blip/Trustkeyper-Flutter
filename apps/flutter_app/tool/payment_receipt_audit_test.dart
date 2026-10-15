import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/features/payments/data/rent_payments.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('render the captured TEST receipt returned by Firebase', () async {
    const source = String.fromEnvironment('TRUSTKEYPER_TEST_RECEIPT_SOURCE');
    const destination = String.fromEnvironment(
      'TRUSTKEYPER_TEST_RECEIPT_OUTPUT',
    );
    expect(source, isNotEmpty);
    expect(destination, isNotEmpty);
    final values = jsonDecode(await File(source).readAsString());
    final payment = RentPaymentData(Map<String, dynamic>.from(values as Map));
    expect(payment.paid, isTrue);
    expect(payment.text('mode'), 'test');
    expect(payment.text('paymentId'), matches(RegExp(r'^pay_[A-Za-z0-9]+$')));
    expect(payment.text('receiptNumber'), startsWith('TK-TEST-'));
    expect(payment.amount('amountPaise'), greaterThan(0));
    final bytes = await paymentReceipt(payment);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    await File(destination).writeAsBytes(bytes, flush: true);
  });
}
