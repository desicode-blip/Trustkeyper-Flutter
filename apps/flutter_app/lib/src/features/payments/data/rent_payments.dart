import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as document;

import '../../broker/data/private_documents.dart';

class RentPaymentData {
  RentPaymentData(Map<dynamic, dynamic> data)
    : data = Map<String, dynamic>.from(data);
  final Map<String, dynamic> data;
  String text(String key) => data[key] is String ? data[key] as String : '';
  int amount(String key) => data[key] is int ? data[key] as int : 0;
  bool flag(String key) => data[key] == true;
  List<RentPaymentData> rows(String key) => (data[key] as List? ?? [])
      .map((row) => RentPaymentData(row as Map))
      .toList();
  RentPaymentData? get pending =>
      data['pending'] is Map ? RentPaymentData(data['pending'] as Map) : null;
  bool get paid => text('status') == 'paid';
}

abstract interface class RentPaymentGateway {
  String operationId();
  Future<RentPaymentData> quote(String agreementId, int revision);
  Future<RentPaymentData> begin(
    String agreementId,
    int revision,
    List<String> months,
    String operationId,
  );
  Future<RentPaymentData> confirm(String intentId, Map<String, String> result);
  Future<RentPaymentData> reconcile(String intentId);
}

class FirebaseRentPaymentGateway implements RentPaymentGateway {
  FirebaseRentPaymentGateway({FirebaseAuth? auth, FirebaseFunctions? functions})
    : auth = auth ?? FirebaseAuth.instance,
      functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1');
  final FirebaseAuth auth;
  final FirebaseFunctions functions;
  Future<RentPaymentData> _call(String name, Map<String, dynamic> input) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) {
      throw const DocumentFailure('Verify your tenant phone first.');
    }
    try {
      final result = await functions
          .httpsCallable(
            name,
            options: HttpsCallableOptions(timeout: const Duration(minutes: 2)),
          )
          .call(input);
      if (auth.currentUser?.uid != uid) {
        throw const DocumentFailure('Your login changed. Reopen payments.');
      }
      return RentPaymentData(result.data as Map);
    } on FirebaseFunctionsException catch (failure) {
      throw DocumentFailure(
        failure.message ?? 'Check payment status before trying again.',
      );
    }
  }

  @override
  String operationId() =>
      FirebaseFirestore.instance.collection('payments').doc().id;
  @override
  Future<RentPaymentData> quote(String agreementId, int revision) => _call(
    'quoteRentPayment',
    {'agreementId': agreementId, 'revision': revision},
  );
  @override
  Future<RentPaymentData> begin(
    String agreementId,
    int revision,
    List<String> months,
    String operationId,
  ) => _call('beginRentPayment', {
    'agreementId': agreementId,
    'revision': revision,
    'months': months,
    'operationId': operationId,
  });
  @override
  Future<RentPaymentData> confirm(
    String intentId,
    Map<String, String> result,
  ) => _call('confirmRentPayment', {'intentId': intentId, ...result});
  @override
  Future<RentPaymentData> reconcile(String intentId) =>
      _call('reconcileRentPayment', {'intentId': intentId});
}

String paymentMoney(int paise) => NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: paise % 100 == 0 ? 0 : 2,
).format(paise / 100);

Future<Uint8List> paymentReceipt(RentPaymentData payment) async {
  String receiptMoney(int paise) => paymentMoney(paise).replaceAll('₹', 'INR ');
  if (!payment.paid ||
      payment.text('receiptNumber').isEmpty ||
      payment.text('mode') != 'test') {
    throw const DocumentFailure('A verified test receipt is required.');
  }
  final font = document.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-400.ttf'),
  );
  final pdf = document.Document();
  pdf.addPage(
    document.MultiPage(
      theme: document.ThemeData.withFont(base: font, bold: font),
      build: (_) => [
        document.Text(
          'TrustKeyper · TEST payment receipt',
          style: const document.TextStyle(fontSize: 22),
        ),
        document.SizedBox(height: 12),
        document.Text(
          'TEST MODE — no real money moved. Not a tax invoice or a legal signing confirmation.',
        ),
        document.SizedBox(height: 20),
        for (final row in <String, String>{
          'Receipt': payment.text('receiptNumber'),
          'Gateway payment': payment.text('paymentId'),
          'Gateway order': payment.text('orderId'),
          'Agreement':
              '${payment.text('agreementId')} · version ${payment.amount('revision')}',
          'Property': payment.text('propertyAddress'),
          'Tenant': payment.text('payerName'),
          'Confirmed': DateFormat('d MMM yyyy, h:mm a').format(
            DateTime.fromMillisecondsSinceEpoch(payment.amount('paidAtMs')),
          ),
          'Deposit': receiptMoney(payment.amount('depositPaise')),
        }.entries)
          document.Padding(
            padding: const document.EdgeInsets.only(bottom: 8),
            child: document.Text('${row.key}: ${row.value}'),
          ),
        for (final line in payment.rows('lines')) ...[
          document.Text(
            '${line.text('month')} rent: ${receiptMoney(line.amount('rentPaise'))}',
          ),
          document.Text(
            'Maintenance: ${receiptMoney(line.amount('maintenancePaise'))}',
          ),
          document.SizedBox(height: 8),
        ],
        document.Text(
          'Total: ${receiptMoney(payment.amount('amountPaise'))}',
          style: const document.TextStyle(fontSize: 18),
        ),
        document.SizedBox(height: 20),
        document.Text(
          'Email and WhatsApp delivery have not been sent. Save this verified receipt for your test records.',
        ),
      ],
    ),
  );
  return pdf.save();
}
