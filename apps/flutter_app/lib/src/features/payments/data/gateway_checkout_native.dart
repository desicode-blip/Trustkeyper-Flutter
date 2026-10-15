import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../broker/data/private_documents.dart';

Future<Map<String, String>> openGatewayCheckout(
  Map<String, dynamic> options,
) async {
  final checkout = Razorpay();
  final result = Completer<Map<String, String>>();
  checkout.on(Razorpay.EVENT_PAYMENT_SUCCESS, (
    PaymentSuccessResponse response,
  ) {
    if (result.isCompleted) return;
    if (response.paymentId == null ||
        response.signature == null ||
        response.orderId != options['order_id']) {
      result.completeError(
        const DocumentFailure('Check status to verify this gateway response.'),
      );
    } else {
      result.complete({
        'paymentId': response.paymentId!,
        'signature': response.signature!,
      });
    }
  });
  checkout.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
    if (!result.isCompleted) {
      result.completeError(
        const DocumentFailure(
          'Checkout was cancelled or not completed. Check status before paying again.',
        ),
      );
    }
  });
  checkout.on(Razorpay.EVENT_EXTERNAL_WALLET, (
    ExternalWalletResponse response,
  ) {
    if (!result.isCompleted) {
      result.completeError(
        const DocumentFailure(
          'Complete payment in your selected wallet, then check status.',
        ),
      );
    }
  });
  try {
    checkout.open(options);
    return await result.future.timeout(
      const Duration(minutes: 7),
      onTimeout: () => throw const DocumentFailure(
        'Confirmation timed out. Check payment status.',
      ),
    );
  } finally {
    checkout.clear();
  }
}
