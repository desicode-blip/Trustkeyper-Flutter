import '../../features/broker/data/private_documents.dart';
import '../../features/payments/data/rent_payments.dart';

class OfflinePaymentFixture implements RentPaymentGateway {
  OfflinePaymentFixture({this.firstPayment = true});
  final bool firstPayment;
  @override
  String operationId() => 'offline-no-payment';
  @override
  Future<RentPaymentData> quote(String agreementId, int revision) async =>
      RentPaymentData({
        'mode': 'fixture',
        'firstPayment': firstPayment,
        'firstPaymentMonth': '2026-10',
        'propertyAddress': 'OFFLINE TEST · Flat 402',
        'depositPaise': firstPayment ? 2200000 : 0,
        'periods': [
          for (int offset = 0; offset < 11; offset++)
            {
              'month': DateTime(
                2026,
                10 + offset,
              ).toIso8601String().substring(0, 7),
              'rentPaise': 1100000,
              'maintenancePaise': 0,
              'totalPaise': 1100000,
              'days': 30,
              'daysInMonth': 30,
              'paid': !firstPayment && offset == 0,
            },
        ],
      });
  @override
  Future<RentPaymentData> begin(
    String agreementId,
    int revision,
    List<String> months,
    String operationId,
  ) async => throw const DocumentFailure(
    'Offline layout only. No checkout or payment was created.',
  );
  @override
  Future<RentPaymentData> confirm(
    String intentId,
    Map<String, String> result,
  ) async =>
      throw const DocumentFailure('Offline fixtures cannot verify payments.');
  @override
  Future<RentPaymentData> reconcile(String intentId) async =>
      throw const DocumentFailure('Offline fixtures have no payment status.');
}
