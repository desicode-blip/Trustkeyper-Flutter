import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/features/journeys/data/journey_catalog.dart';
import 'package:trustkeyper/src/features/journeys/presentation/guided_journey_screen.dart';
import 'package:trustkeyper/src/features/payments/presentation/payment_checkout_screen.dart';
import 'package:trustkeyper/src/features/participants/data/participant_repository.dart';

class EmptyPaymentAgreements implements ParticipantRepository {
  @override
  Stream<List<ParticipantRecord>> watch(String collection) => Stream.value([]);
}

void main() {
  testWidgets(
    'unconnected signing cannot show a fake signature or request real documents',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: GuidedJourneyScreen(
            journeyTitle: 'Signing',
            steps: JourneyCatalog.aadhaarSigning,
          ),
        ),
      );
      expect(find.text('This workflow is not connected yet'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('No request'), findsOneWidget);
    },
  );

  testWidgets(
    'normal payment route never collects dummy cards or presents a simulated receipt',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PaymentCheckoutScreen(
            agreementRepository: EmptyPaymentAgreements(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your payments'), findsOneWidget);
      expect(find.textContaining('no real money'), findsOneWidget);
      expect(find.text('Simulate payment'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    },
  );
}
