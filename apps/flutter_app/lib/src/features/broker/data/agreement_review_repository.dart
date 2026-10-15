import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReviewFailure implements Exception {
  const ReviewFailure(this.message);
  final String message;
}

abstract interface class AgreementReviewRepository {
  Future<String> request(String agreementId, int revision);
}

class FirebaseAgreementReviewRepository implements AgreementReviewRepository {
  FirebaseAgreementReviewRepository({
    String? Function()? currentUid,
    Future<Map<String, dynamic>> Function(Map<String, dynamic>)? call,
  }) : currentUid =
           currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid),
       call = call ?? _call;

  final String? Function() currentUid;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) call;

  static Future<Map<String, dynamic>> _call(Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(
        (await FirebaseFunctions.instanceFor(region: 'asia-south1')
                .httpsCallable('requestAgreementReview')
                .call<Map<String, dynamic>>(data))
            .data,
      );

  @override
  Future<String> request(String agreementId, int revision) async {
    final uid = currentUid();
    if (uid == null) {
      throw const ReviewFailure('Log in again to request review.');
    }
    if (!RegExp(r'^[\w-]{1,150}$').hasMatch(agreementId) || revision < 1) {
      throw const ReviewFailure(
        'Save and reopen the draft before requesting review.',
      );
    }
    try {
      final result = await call({
        'agreementId': agreementId,
        'revision': revision,
      });
      if (currentUid() != uid) {
        throw const ReviewFailure('Your account changed. Log in again.');
      }
      if (result['agreementId'] != agreementId ||
          result['revision'] != revision ||
          ![
            'review_requested',
            'under_review',
            'reviewed',
          ].contains(result['status'])) {
        throw const ReviewFailure(
          'Reopen the draft to check its review status.',
        );
      }
      return result['status'] as String;
    } on FirebaseFunctionsException catch (error) {
      throw ReviewFailure(switch (error.code) {
        'aborted' => 'This draft changed. Reopen it before requesting review.',
        'permission-denied' =>
          'Only the approved broker can submit this private draft.',
        'unauthenticated' => 'Your session expired. Log in again.',
        'not-found' ||
        'unimplemented' => 'The Firebase review service is not deployed yet.',
        'failed-precondition' || 'invalid-argument' =>
          error.message ?? 'Review the saved draft details.',
        _ =>
          'Could not confirm review. Reopen the draft before retrying; it may already be submitted.',
      });
    }
  }
}
