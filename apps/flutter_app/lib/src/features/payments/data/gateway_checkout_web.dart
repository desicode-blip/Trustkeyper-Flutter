import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../../broker/data/private_documents.dart';

@JS('Razorpay')
extension type _Razorpay._(JSObject _) implements JSObject {
  external factory _Razorpay(JSObject options);
  external void open();
  external void on(JSString event, JSFunction callback);
}
@JS('document')
external JSObject get _document;
@JS('window')
external JSObject get _window;
Future<void>? _loading;

Future<void> _load() => _loading ??= () async {
  if (_window.hasProperty('Razorpay'.toJS).toDart) return;
  final result = Completer<void>();
  final script = _document.callMethod<JSObject>(
    'createElement'.toJS,
    'script'.toJS,
  );
  script.setProperty(
    'src'.toJS,
    'https://checkout.razorpay.com/v1/checkout.js'.toJS,
  );
  script.setProperty(
    'onload'.toJS,
    (() {
      if (!result.isCompleted) result.complete();
    }).toJS,
  );
  script.setProperty(
    'onerror'.toJS,
    (() {
      if (!result.isCompleted) {
        result.completeError(
          const DocumentFailure(
            'The secure checkout could not load. Check your connection.',
          ),
        );
      }
    }).toJS,
  );
  _document
      .getProperty<JSObject>('head'.toJS)
      .callMethod<JSAny?>('appendChild'.toJS, script);
  try {
    await result.future.timeout(const Duration(seconds: 30));
  } catch (_) {
    _loading = null;
    rethrow;
  }
}();

Future<Map<String, String>> openGatewayCheckout(
  Map<String, dynamic> options,
) async {
  await _load();
  final result = Completer<Map<String, String>>();
  final input = Map<String, dynamic>.from(options).jsify() as JSObject;
  input.setProperty(
    'handler'.toJS,
    ((JSObject response) {
      if (result.isCompleted) return;
      final data = response.dartify() as Map;
      if (data['razorpay_order_id'] != options['order_id'] ||
          data['razorpay_payment_id'] is! String ||
          data['razorpay_signature'] is! String) {
        result.completeError(
          const DocumentFailure(
            'Check status to verify this gateway response.',
          ),
        );
      } else {
        result.complete({
          'paymentId': data['razorpay_payment_id'] as String,
          'signature': data['razorpay_signature'] as String,
        });
      }
    }).toJS,
  );
  final modal = <String, dynamic>{}.jsify() as JSObject;
  modal.setProperty(
    'ondismiss'.toJS,
    (() {
      if (!result.isCompleted) {
        result.completeError(
          const DocumentFailure(
            'Checkout closed. Check status before paying again.',
          ),
        );
      }
    }).toJS,
  );
  input.setProperty('modal'.toJS, modal);
  final checkout = _Razorpay(input);
  checkout.on(
    'payment.failed'.toJS,
    ((JSObject response) {
      if (!result.isCompleted) {
        result.completeError(
          const DocumentFailure(
            'Payment was not confirmed. Check status before trying again.',
          ),
        );
      }
    }).toJS,
  );
  checkout.open();
  return result.future.timeout(
    const Duration(minutes: 7),
    onTimeout: () => throw const DocumentFailure(
      'Confirmation timed out. Check payment status.',
    ),
  );
}
